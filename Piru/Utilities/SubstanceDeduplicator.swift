import Foundation

enum SubstanceDeduplicator {
    // MARK: - Name Normalization

    /// Normalize a substance name for deduplication comparison
    static func normalizeName(_ name: String) -> String {
        let n = name.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "α", with: "alpha")
            .replacingOccurrences(of: "β", with: "beta")
            .replacingOccurrences(of: "γ", with: "gamma")
            .replacingOccurrences(of: "δ", with: "delta")
        return n
    }

    /// Pharmaceutical salt/form suffixes that don't change the active molecule
    static let saltSuffixes: [String] = [
        "hydrochloride", "hcl", "sodium", "potassium", "calcium", "magnesium",
        "sulfate", "sulphate", "maleate", "tartrate", "fumarate", "hemifumarate",
        "mesylate", "besylate", "tosylate", "bromide", "chloride", "iodide",
        "acetate", "phosphate", "citrate", "succinate", "oxalate", "gluconate",
        "pamoate", "embonate", "valerate", "decanoate", "enanthate", "propionate",
        "monohydrate", "dihydrate", "trihydrate", "anhydrous",
    ]

    /// Strip trailing pharmaceutical salt suffixes from an already-normalized name.
    static func saltStripped(_ normalized: String) -> String {
        var result = normalized
        var changed = true
        while changed {
            changed = false
            for suffix in saltSuffixes where result.hasSuffix(suffix) && result.count > suffix.count {
                result = String(result.dropLast(suffix.count))
                changed = true
                break
            }
        }
        return result
    }

    /// Well-known name mappings for cross-source dedup
    static let knownAliases: [String: String] = [
        "mdma": "34methylenedioxymethamphetamine",
        "34methylenedioxymethamphetamine": "mdma",
        "lsd": "lysergicaciddiethylamide",
        "lysergicaciddiethylamide": "lsd",
        "thc": "delta9tetrahydrocannabinol",
        "delta9tetrahydrocannabinol": "thc",
        "ghb": "gammahydroxybutyricacid",
        "gammahydroxybutyricacid": "ghb",
        "gbl": "gammabutyrolactone",
        "gammabutyrolactone": "gbl",
        "pcp": "phencyclidine",
        "phencyclidine": "pcp",
        "dmt": "nn dimethyltryptamine",
        "dxm": "dextromethorphan",
        "dextromethorphan": "dxm",
        "mda": "34methylenedioxyamphetamine",
        "34methylenedioxyamphetamine": "mda",
        "2cb": "4bromo25dimethoxyphenethylamine",
        "nac": "nacetylcysteine",
        "nacetylcysteine": "nac",
        "paracetamol": "acetaminophen",
        "acetaminophen": "paracetamol",
        "adrenaline": "epinephrine",
        "epinephrine": "adrenaline",
        "noradrenaline": "norepinephrine",
        "norepinephrine": "noradrenaline",
    ]

    // MARK: - Deduplication

    /// Merge incoming substances into existing, deduplicating by normalized name + aliases
    static func deduplicatedMerge(existing: [Substance], incoming: [Substance]) -> [Substance] {
        var byNormalized: [String: Int] = [:]
        var result = existing
        var dupeCount = 0
        var newCount = 0

        // Index existing
        for (i, s) in result.enumerated() {
            byNormalized[s.name.lowercased()] = i
            let norm = normalizeName(s.name)
            byNormalized[norm] = i
            byNormalized[saltStripped(norm)] = i
            for a in s.aliases {
                let aNorm = normalizeName(a)
                byNormalized[a.lowercased()] = i
                byNormalized[aNorm] = i
                byNormalized[saltStripped(aNorm)] = i
            }
            if let mapped = knownAliases[norm] { byNormalized[mapped] = i }
        }

        for s in incoming {
            let nameNorm = normalizeName(s.name)
            let nameLower = s.name.lowercased()

            var matchIdx: Int? = byNormalized[nameLower]
                ?? byNormalized[nameNorm]
                ?? byNormalized[saltStripped(nameNorm)]

            if matchIdx == nil {
                if let mapped = knownAliases[nameNorm] { matchIdx = byNormalized[mapped] }
            }

            if matchIdx == nil {
                for a in s.aliases {
                    let aNorm = normalizeName(a)
                    if let idx = byNormalized[a.lowercased()] ?? byNormalized[aNorm] ?? byNormalized[saltStripped(aNorm)] {
                        matchIdx = idx
                        break
                    }
                }
            }

            if let idx = matchIdx {
                dupeCount += 1
                let existing = result[idx]
                let merged = mergeSubstances(existing, s)
                result[idx] = merged

                for a in merged.aliases {
                    byNormalized[a.lowercased()] = idx
                    byNormalized[normalizeName(a)] = idx
                }
            } else {
                newCount += 1
                let newIdx = result.count
                result.append(s)
                byNormalized[nameLower] = newIdx
                byNormalized[nameNorm] = newIdx
                byNormalized[saltStripped(nameNorm)] = newIdx
                for a in s.aliases {
                    let aNorm = normalizeName(a)
                    byNormalized[a.lowercased()] = newIdx
                    byNormalized[aNorm] = newIdx
                    byNormalized[saltStripped(aNorm)] = newIdx
                }
            }
        }

        print("[SubstanceDeduplicator] \(incoming.count) incoming → \(dupeCount) matched existing, \(newCount) added as new")
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Merge two substances: prefer the one with more complete data, combine sources + aliases
    static func mergeSubstances(_ a: Substance, _ b: Substance) -> Substance {
        let aScore = dataScore(a)
        let bScore = dataScore(b)
        let primary = aScore >= bScore ? a : b
        let secondary = aScore >= bScore ? b : a

        // Prefer the shorter, non-salt name when both normalize to the same base
        let finalName: String
        if primary.name.count > secondary.name.count,
           saltStripped(normalizeName(primary.name)) == saltStripped(normalizeName(secondary.name)) {
            finalName = secondary.name
        } else {
            finalName = primary.name
        }

        let allAliases = Set(primary.aliases + secondary.aliases + [secondary.name, primary.name])
            .filter { $0.lowercased() != finalName.lowercased() }
        let mergedAliases = Array(allAliases).sorted()

        let mergedSources = Array(Set(primary.sources + secondary.sources)).sorted()

        var routes = primary.routes
        for r in secondary.routes {
            if let idx = routes.firstIndex(where: { $0.route == r.route }) {
                routes[idx] = mergeRoutes(routes[idx], r)
            } else {
                routes.append(r)
            }
        }

        let primaryEffects = Set(primary.effects.map { $0.lowercased() })
        let newEffects = secondary.effects.filter { !primaryEffects.contains($0.lowercased()) }

        return Substance(
            name: finalName,
            aliases: mergedAliases,
            category: primary.category,
            defaultRoute: primary.defaultRoute,
            routes: routes,
            effects: primary.effects + newEffects,
            subjectiveEffects: primary.subjectiveEffects.isEmpty ? secondary.subjectiveEffects : primary.subjectiveEffects,
            toleranceInfo: primary.toleranceInfo ?? secondary.toleranceInfo,
            halfLifeMinutes: primary.halfLifeMinutes ?? secondary.halfLifeMinutes,
            sources: mergedSources,
            mechanismOfAction: primary.mechanismOfAction ?? secondary.mechanismOfAction
        )
    }

    /// Merge two routes for the same administration path, keeping the best dose
    /// data from either source and the best duration data from either source
    /// independently. Replacing a route wholesale (as we used to) silently
    /// discarded whichever field the winning source didn't have — e.g. DXM's
    /// TripSit duration vanishing because DailyMed's oral syrup had denser
    /// dose text but no pharmacokinetics.
    static func mergeRoutes(_ a: SubstanceRoute, _ b: SubstanceRoute) -> SubstanceRoute {
        let doseWinner = routeDataScore(a) >= routeDataScore(b) ? a : b
        let duration: DurationProfile? = {
            switch (a.duration, b.duration) {
            case let (ad?, bd?):
                return durationPhaseCount(ad) >= durationPhaseCount(bd) ? ad : bd
            case let (ad?, nil): return ad
            case let (nil, bd?): return bd
            case (nil, nil): return nil
            }
        }()
        return SubstanceRoute(
            route: a.route,
            unit: doseWinner.unit,
            doses: doseWinner.doses,
            duration: duration
        )
    }

    /// Count how many phase ranges a DurationProfile has populated.
    static func durationPhaseCount(_ d: DurationProfile) -> Int {
        var count = 0
        if d.onset != nil { count += 1 }
        if d.comeup != nil { count += 1 }
        if d.peak != nil { count += 1 }
        if d.offset != nil { count += 1 }
        if d.afterglow != nil { count += 1 }
        if d.total != nil { count += 1 }
        return count
    }

    /// Score how complete a single route's data is — used to pick the better source
    /// when two sources provide data for the same route.
    static func routeDataScore(_ r: SubstanceRoute) -> Int {
        var score = 0
        let d = r.doses
        if d.threshold != nil { score += 1 }
        if d.light != nil { score += 1 }
        if d.common != nil { score += 1 }
        if d.strong != nil { score += 1 }
        if d.heavy != nil { score += 1 }
        if r.duration != nil { score += 2 }
        // Prefer standard mass/volume units over non-standard (e.g. "g" over "units")
        let unit = r.unit.lowercased()
        if ["mg", "g", "µg", "ug", "ml"].contains(unit) { score += 3 }
        return score
    }

    /// Score how complete a substance's data is (higher = more data)
    static func dataScore(_ s: Substance) -> Int {
        var score = 0
        if s.halfLifeMinutes != nil { score += 3 }
        if s.toleranceInfo != nil { score += 2 }
        for r in s.routes {
            if r.doses.threshold != nil || r.doses.light != nil || r.doses.common != nil { score += 3 }
            if r.duration != nil { score += 2 }
        }
        score += s.effects.count > 0 ? 2 : 0
        if !s.subjectiveEffects.isEmpty { score += 2 }
        score += s.aliases.count
        return score
    }
}
