import Foundation

/// Merges `SourcedSubstance` lists into a single deduplicated `BundledSubstance`
/// list. Precedence on conflict:
///   curated overlay > Erowid PIHKAL/TIHKAL > TripSit > Wikidata/PubChem stub.
///
/// Dedup key cascade:
///   1. InChIKey (most reliable — derived from canonical 3D structure)
///   2. PubChem CID
///   3. Normalized name (lowercased, prefix/salt-stripped, alphanumeric only)
///
/// When two records collide, we keep the higher-precedence record's scalar
/// fields (name/category/defaultRoute) but UNION arrays (aliases, sources,
/// effects, tags) and fill in missing fields (halfLifeMinutes, mechanism,
/// routes) from the lower-precedence record.
enum Merger {
    /// Returns the merged list plus per-source counters for the report.
    struct Result {
        let substances: [BundledSubstance]
        let countsByProvenance: [String: Int]
        let mergedCount: Int
    }

    static func merge(_ all: [SourcedSubstance]) -> Result {
        // Sort the input deterministically so dictionary iteration order
        // can't influence which record "wins" name-collision tie-breaks.
        // Higher-provenance records first; within the same provenance, sort
        // by name so the same set of sources always produces the same output.
        let sortedAll = all.sorted { lhs, rhs in
            if lhs.provenance != rhs.provenance {
                return lhs.provenance > rhs.provenance
            }
            return lhs.substance.name.lowercased() < rhs.substance.name.lowercased()
        }

        // Group by primary dedup key.
        var groups: [String: [SourcedSubstance]] = [:]
        var origCounts: [String: Int] = [:]
        for s in sortedAll {
            origCounts[s.provenance.label, default: 0] += 1
            let key = primaryKey(s)
            groups[key, default: []].append(s)
        }

        // Build name → key index for the secondary pass: collapse stub
        // wikidata records into TripSit/Erowid records sharing a normalized
        // name even when neither has an InChIKey. Iterate groups in a
        // deterministic order so collisions resolve identically every run.
        var nameToKey: [String: String] = [:]
        let sortedGroupKeys = groups.keys.sorted()
        for key in sortedGroupKeys {
            let members = groups[key]!
            for m in members {
                let n = NameNormalizer.normalize(m.substance.name)
                if !n.isEmpty {
                    // Prefer keys backed by InChIKey/CID over name-only keys.
                    if nameToKey[n] == nil || key.hasPrefix("k_") || key.hasPrefix("c_") {
                        nameToKey[n] = key
                    }
                }
                for alias in m.substance.aliases {
                    let an = NameNormalizer.normalize(alias)
                    if !an.isEmpty, nameToKey[an] == nil {
                        nameToKey[an] = key
                    }
                }
            }
        }

        // Second pass: collapse name-only groups when they share a normalized
        // name with a structurally-keyed group. Iterate sorted to keep merge
        // order deterministic.
        var collapsed: [String: [SourcedSubstance]] = [:]
        for key in sortedGroupKeys {
            let members = groups[key]!
            if key.hasPrefix("n_") {
                let n = String(key.dropFirst(2))
                if let other = nameToKey[n], other != key {
                    collapsed[other, default: []].append(contentsOf: members)
                    continue
                }
            }
            collapsed[key, default: []].append(contentsOf: members)
        }

        var merged: [BundledSubstance] = []
        merged.reserveCapacity(collapsed.count)
        var mergedCount = 0
        for key in collapsed.keys.sorted() {
            let members = collapsed[key]!
            // Already pre-sorted by provenance via `sortedAll`, but explicit
            // sort makes the contract obvious to future readers.
            let sorted = members.sorted { $0.provenance > $1.provenance }
            var base = sorted[0].substance
            // Apply DEA schedule tag if available, regardless of provenance.
            applyScheduleTag(&base)

            if sorted.count > 1 {
                mergedCount += sorted.count - 1
                for other in sorted.dropFirst() {
                    base = combine(higher: base, lower: other.substance)
                }
            }
            merged.append(base)
        }

        // Final pass: sort by name for stable output, normalize trailing
        // whitespace, and dedup tags/aliases/sources defensively.
        merged.sort { $0.name.lowercased() < $1.name.lowercased() }
        for i in merged.indices {
            merged[i].aliases = uniqueSorted(merged[i].aliases) { NameNormalizer.normalize($0) }
            merged[i].tags = uniqueSorted(merged[i].tags) { $0 }
            merged[i].sources = uniqueSorted(merged[i].sources) { $0 }
            merged[i].effects = uniqueOrderPreserving(merged[i].effects)
        }

        return Result(
            substances: merged,
            countsByProvenance: origCounts,
            mergedCount: mergedCount,
        )
    }

    // MARK: - Key + combine

    private static func primaryKey(_ s: SourcedSubstance) -> String {
        if let k = s.inchiKey?.trimmingCharacters(in: .whitespaces), !k.isEmpty {
            return "k_\(k)"
        }
        if let cid = s.pubchemCID { return "c_\(cid)" }
        return "n_\(NameNormalizer.normalize(s.substance.name))"
    }

    private static func applyScheduleTag(_ s: inout BundledSubstance) {
        if let tag = DEAScheduleSource.scheduleTag(for: s.name), !s.tags.contains(tag) {
            s.tags = Tagger.merge(s.tags, [tag])
        }
        for alias in s.aliases {
            if let tag = DEAScheduleSource.scheduleTag(for: alias), !s.tags.contains(tag) {
                s.tags = Tagger.merge(s.tags, [tag])
            }
        }
    }

    /// Combine a higher-precedence record with a lower-precedence record:
    /// keep the higher's scalar fields, union arrays, fill in any missing
    /// optionals.
    private static func combine(higher h: BundledSubstance, lower l: BundledSubstance) -> BundledSubstance {
        var out = h
        // Aliases — union, preserving the higher record's order first.
        out.aliases = mergeStrings(out.aliases, l.aliases, normalizer: NameNormalizer.normalize)
        // Effects — append lower's effects after higher's (skipping dupes).
        out.effects = uniqueOrderPreserving(out.effects + l.effects)
        // Sources — union, preserving order.
        out.sources = mergeStrings(out.sources, l.sources, normalizer: { $0 })
        // Tags — union.
        out.tags = Tagger.merge(out.tags, l.tags)
        // Routes — union by route name, prefer higher.
        var routesByName: [String: JSONRoute] = [:]
        for r in l.routes {
            routesByName[r.route] = r
        }
        for r in h.routes {
            routesByName[r.route] = r
        }
        out.routes = Array(routesByName.values).sorted { $0.route < $1.route }
        // Half-life — keep higher's, fall back to lower.
        out.halfLifeMinutes = h.halfLifeMinutes ?? l.halfLifeMinutes
        // Tolerance / mechanism — keep higher's, fall back to lower.
        out.toleranceInfo = h.toleranceInfo ?? l.toleranceInfo
        out.mechanismOfAction = h.mechanismOfAction ?? l.mechanismOfAction
        // Subjective effects — union by name.
        var seenSE = Set(out.subjectiveEffects.map { $0.name.lowercased() })
        for se in l.subjectiveEffects where !seenSE.contains(se.name.lowercased()) {
            out.subjectiveEffects.append(se)
            seenSE.insert(se.name.lowercased())
        }
        return out
    }

    private static func mergeStrings(_ a: [String], _ b: [String], normalizer: (String) -> String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for v in a + b {
            let k = normalizer(v)
            if k.isEmpty || seen.contains(k) { continue }
            seen.insert(k)
            out.append(v)
        }
        return out
    }

    private static func uniqueSorted(_ values: [String], normalizer: (String) -> String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for v in values {
            let k = normalizer(v)
            if k.isEmpty || seen.contains(k) { continue }
            seen.insert(k)
            out.append(v)
        }
        return out.sorted { $0.lowercased() < $1.lowercased() }
    }

    private static func uniqueOrderPreserving(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for v in values {
            let k = v.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if k.isEmpty || seen.contains(k) { continue }
            seen.insert(k)
            out.append(v)
        }
        return out
    }
}
