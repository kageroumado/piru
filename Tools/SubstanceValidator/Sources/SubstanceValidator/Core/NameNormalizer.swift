import Foundation

/// Normalizes substance names for fuzzy matching and builds match indices.
struct NameNormalizer {
    /// Normalize a substance name for comparison.
    /// Lowercases, strips non-alphanumeric characters, removes stereochemistry prefixes.
    func normalize(_ name: String) -> String {
        var s = name.lowercased()

        // Remove stereochemistry prefixes
        let prefixes = ["(+)-", "(-)-", "(±)-", "dl-", "d-", "l-", "r-", "s-"]
        for prefix in prefixes {
            if s.hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count))
            }
        }

        // Keep only alphanumeric characters
        s = s.filter { $0.isLetter || $0.isNumber }

        return s
    }

    /// Build an index mapping normalized names/aliases → local substance.
    func buildIndex(from substances: [ParsedLocalSubstance]) -> MatchIndex {
        var nameIndex: [String: ParsedLocalSubstance] = [:]
        var aliasIndex: [String: [ParsedLocalSubstance]] = [:]

        for substance in substances {
            let normalizedName = normalize(substance.name)
            nameIndex[normalizedName] = substance

            for alias in substance.aliases {
                let normalizedAlias = normalize(alias)
                aliasIndex[normalizedAlias, default: []].append(substance)
            }
        }

        return MatchIndex(nameIndex: nameIndex, aliasIndex: aliasIndex)
    }

    /// Find a local match for an API substance.
    func findMatch(for apiSubstance: UnifiedSubstance, in index: MatchIndex) -> (ParsedLocalSubstance, MatchResult.MatchType)? {
        // Tier 1: Exact normalized name match
        if let match = index.nameIndex[apiSubstance.normalizedName] {
            return (match, .exactName)
        }

        // Tier 2: Exact normalized alias match
        for normalizedAlias in apiSubstance.normalizedAliases {
            if let match = index.nameIndex[normalizedAlias] {
                return (match, .exactAlias)
            }
        }

        // Tier 2b: Check if API name matches any local alias
        if let matches = index.aliasIndex[apiSubstance.normalizedName], let first = matches.first {
            return (first, .exactAlias)
        }

        // Tier 2c: Check API aliases against local aliases
        for normalizedAlias in apiSubstance.normalizedAliases {
            if let matches = index.aliasIndex[normalizedAlias], let first = matches.first {
                return (first, .exactAlias)
            }
        }

        // Tier 3: Guarded fuzzy matching with strict safety constraints
        let apiName = apiSubstance.normalizedName
        guard apiName.count >= 8 else { return nil } // Short names are too ambiguous

        var bestMatch: (ParsedLocalSubstance, Int)?

        for (normalizedKey, substance) in index.nameIndex {
            let distance = levenshteinDistance(apiName, normalizedKey)
            guard distance <= 2 else { continue }

            // Require ≥75% character overlap (Jaccard-like similarity)
            let overlap = characterOverlap(apiName, normalizedKey)
            guard overlap >= 0.75 else { continue }

            // Require similar lengths (within 20%)
            let lenRatio = Double(min(apiName.count, normalizedKey.count)) / Double(max(apiName.count, normalizedKey.count))
            guard lenRatio >= 0.80 else { continue }

            // Block confusable suffixes: substances sharing a class suffix
            // but differing in the prefix are usually different drugs
            if hasConfusableSuffixMismatch(apiName, normalizedKey) {
                continue
            }

            if bestMatch == nil || distance < bestMatch!.1 {
                bestMatch = (substance, distance)
            }
        }

        if let (match, _) = bestMatch {
            return (match, .fuzzy)
        }

        return nil
    }

    // MARK: - Similarity Helpers

    /// Character-level overlap ratio (intersection / union of character multisets).
    func characterOverlap(_ a: String, _ b: String) -> Double {
        var aFreq: [Character: Int] = [:]
        var bFreq: [Character: Int] = [:]
        for c in a {
            aFreq[c, default: 0] += 1
        }
        for c in b {
            bFreq[c, default: 0] += 1
        }

        let allKeys = Set(aFreq.keys).union(bFreq.keys)
        var intersection = 0
        var union = 0
        for key in allKeys {
            let aCount = aFreq[key] ?? 0
            let bCount = bFreq[key] ?? 0
            intersection += min(aCount, bCount)
            union += max(aCount, bCount)
        }

        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    /// Detect if two normalized names share a confusable drug-class suffix
    /// but differ in their prefix (meaning they're probably different drugs).
    /// e.g., "diazepam" vs "pinazepam" — same "-azepam" suffix, different prefix.
    func hasConfusableSuffixMismatch(_ a: String, _ b: String) -> Bool {
        let confusableSuffixes = [
            "azepam", "azolam", "azenil", "azepate", // benzodiazepines
            "etamine", "amine", "idine", // dissociatives/amines
            "orphine", "orphan", "adone", "adol", // opioids
            "nbome", "nboh", "nbf", // psychedelic NBx series
            "phetamine", // amphetamines
            "cathinone", "edrone", // cathinones
            "tryptamine", // tryptamines
            "phenidine", "cyclidine", // arylcyclohexylamines
            "fentanyl", "fentanil", // fentanyl analogues
        ]

        for suffix in confusableSuffixes {
            let aHas = a.hasSuffix(suffix)
            let bHas = b.hasSuffix(suffix)
            if aHas, bHas {
                // Both share the suffix — check if prefixes differ significantly
                let aPrefix = String(a.dropLast(suffix.count))
                let bPrefix = String(b.dropLast(suffix.count))
                if aPrefix != bPrefix, levenshteinDistance(aPrefix, bPrefix) > 1 {
                    return true // Different drugs in the same class
                }
            }
        }

        return false
    }

    /// Standard Levenshtein edit distance.
    func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 0 ... m {
            matrix[i][0] = i
        }
        for j in 0 ... n {
            matrix[0][j] = j
        }

        for i in 1 ... m {
            for j in 1 ... n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1, // deletion
                    matrix[i][j - 1] + 1, // insertion
                    matrix[i - 1][j - 1] + cost, // substitution
                )
            }
        }

        return matrix[m][n]
    }
}

struct MatchIndex {
    let nameIndex: [String: ParsedLocalSubstance]
    let aliasIndex: [String: [ParsedLocalSubstance]]
}
