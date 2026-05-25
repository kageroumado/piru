import Foundation

// MARK: - TripSit JSON Schema (subset)

private struct RawTripSitDrug: Codable {
    let aliases: [String]?
    let categories: [String]?
    let formattedDose: [String: [String: String]]?
    let formattedDuration: RawTiming?
    let formattedOnset: RawTiming?
    let formattedAftereffects: RawTiming?
    let properties: RawProperties?
    let pweffects: [String: String]?

    enum CodingKeys: String, CodingKey {
        case aliases, categories, properties, pweffects
        case formattedDose = "formatted_dose"
        case formattedDuration = "formatted_duration"
        case formattedOnset = "formatted_onset"
        case formattedAftereffects = "formatted_aftereffects"
    }
}

private struct RawTiming: Codable {
    let unit: String?
    let value: String?
    enum CodingKeys: String, CodingKey { case unit = "_unit", value }
}

private struct RawProperties: Codable {
    let summary: String?
    let halfLife: String?
    let bioavailability: String?
    enum CodingKeys: String, CodingKey {
        case summary, bioavailability
        case halfLife = "half-life"
    }
}

// MARK: - Source

/// Fetches and converts the TripSit `drugs.json` snapshot.
struct TripSitSource {
    let cache: HTTPCache
    private let url = URL(string: "https://raw.githubusercontent.com/TripSit/drugs/master/drugs.json")!

    func fetch() async throws -> [SourcedSubstance] {
        Log.info("TripSit: fetching \(url.absoluteString)")
        let data = try await cache.fetch(url: url, scope: "tripsit")
        Log.info("TripSit: \(data.count / 1024) KB downloaded/cached")

        let dict = try JSONDecoder().decode([String: RawTripSitDrug].self, from: data)
        Log.info("TripSit: \(dict.count) raw entries")

        var out: [SourcedSubstance] = []
        out.reserveCapacity(dict.count)
        for rawName in dict.keys.sorted() {
            let raw = dict[rawName]!
            // TripSit includes pseudo-entries with no actual data and bookkeeping
            // keys like "categories". Skip ones with no aliases/categories/dose.
            let hasAnyData = (raw.aliases?.isEmpty == false)
                || (raw.categories?.isEmpty == false)
                || (raw.formattedDose?.isEmpty == false)
                || (raw.properties?.summary != nil)
            guard hasAnyData else { continue }

            // Skip TripSit's internal keys (no compound named "categories" exists).
            let lname = rawName.lowercased()
            if ["categories", "drug name", "tripsit"].contains(lname) { continue }

            let name = displayName(rawName)
            let aliases = (raw.aliases ?? []).filter { !$0.isEmpty }

            // Route → DoseRange. TripSit gives us dose by named tier in mg/g/µg.
            // Iterate routes in sorted order so output is deterministic.
            var routes: [JSONRoute] = []
            if let doseByRoute = raw.formattedDose {
                for rawRoute in doseByRoute.keys.sorted() {
                    let levels = doseByRoute[rawRoute]!
                    let route = RouteMapper.map(rawRoute)
                    var dose = JSONDoseRange()
                    var unit = "mg"
                    // Sort level keys so the final `unit` value (last write
                    // wins) is deterministic.
                    for level in levels.keys.sorted() {
                        let str = levels[level]!
                        guard let p = DoseParser.parse(str) else { continue }
                        unit = p.unit
                        let range: JSONRange? = (p.max.map { JSONRange(p.min, $0) })
                        switch level.lowercased() {
                        case "threshold": dose.threshold = p.min
                        case "light": dose.light = range ?? JSONRange(p.min, p.min)
                        case "common": dose.common = range ?? JSONRange(p.min, p.min)
                        case "strong":
                            if let range { dose.strong = range }
                            else { dose.heavy = p.min }
                        case "heavy": dose.heavy = p.min
                        default: break
                        }
                    }
                    let duration = parseDuration(value: raw.formattedDuration, onset: raw.formattedOnset, after: raw.formattedAftereffects)
                    routes.append(JSONRoute(
                        route: route, unit: unit, doses: dose, duration: duration
                    ))
                }
            }

            let category = CategoryMapper.map(labels: raw.categories ?? [], name: name)
            let halfLifeMinutes = parseHalfLifeMinutes(raw.properties?.halfLife)
            let defaultRoute = routes.first?.route ?? "oral"

            var effects = extractEffects(raw.pweffects)
            // Append the TripSit summary as a synthetic effect-style note if
            // we have nothing else — keeps the detail view from looking empty.
            if effects.isEmpty, let s = raw.properties?.summary, !s.isEmpty {
                effects.append(s)
            }

            var tags = Tagger.tags(for: name, sourceClasses: raw.categories ?? [])
            // Carry TripSit's modifier flags through as tags.
            for cat in raw.categories ?? [] {
                let l = cat.lowercased().trimmingCharacters(in: .whitespaces)
                if CategoryMapper.modifierLabels.contains(l) { tags.append(l) }
            }
            tags = Tagger.merge(tags)

            let warnings = SafetyWarnings.warnings(for: name, tags: tags)
            effects.append(contentsOf: warnings)

            let sub = BundledSubstance(
                name: name,
                aliases: aliases,
                category: category,
                defaultRoute: defaultRoute,
                routes: routes,
                effects: effects,
                halfLifeMinutes: halfLifeMinutes,
                sources: ["TripSit drugs.json: https://github.com/TripSit/drugs"],
                tags: tags
            )
            out.append(SourcedSubstance(
                substance: sub,
                provenance: .tripSit,
                inchiKey: nil, pubchemCID: nil, cas: nil
            ))
        }
        Log.info("TripSit: emitted \(out.count) sourced entries")
        return out
    }

    // MARK: - Helpers

    private func displayName(_ raw: String) -> String {
        // TripSit names are usually lowercase ("2c-b"). Title-case but preserve
        // recognizable acronyms.
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return s }
        // Compact common prefixes/abbreviations
        let acronyms: Set<String> = ["LSD", "MDMA", "MDA", "DMT", "PCP", "2C-B", "2C-E",
                                     "2C-I", "2C-T-7", "DOI", "DOM", "DOB", "DOC",
                                     "JWH", "JWH-018", "NBOMe", "5-MeO-DMT",
                                     "5-MeO-DiPT", "GHB", "GBL", "MXE", "DXM",
                                     "AMT", "DPT", "DiPT"]
        let upper = s.uppercased()
        if acronyms.contains(upper) { return upper }
        // For names containing dashes, just titlecase each segment intelligently.
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    private func parseHalfLifeMinutes(_ raw: String?) -> Double? {
        guard let raw = raw?.lowercased() else { return nil }
        // Examples: "3-5 hours", "12-15 hours", "30-60 minutes"
        let r = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        let pat = try! NSRegularExpression(pattern: #"([0-9]+(?:\.[0-9]+)?)\s*(?:[-–]\s*([0-9]+(?:\.[0-9]+)?))?\s*(hour|hr|h|minute|min|m|day|d)"#)
        guard let m = pat.firstMatch(in: raw, range: r),
              let r0 = Range(m.range(at: 1), in: raw),
              let lo = Double(raw[r0]) else { return nil }
        var hi = lo
        if m.range(at: 2).location != NSNotFound, let r1 = Range(m.range(at: 2), in: raw), let v = Double(raw[r1]) { hi = v }
        guard let r2 = Range(m.range(at: 3), in: raw) else { return nil }
        let unit = String(raw[r2])
        let midpoint = (lo + hi) / 2
        switch unit {
        case "hour", "hr", "h": return midpoint * 60
        case "minute", "min", "m": return midpoint
        case "day", "d": return midpoint * 60 * 24
        default: return nil
        }
    }

    private func extractEffects(_ map: [String: String]?) -> [String] {
        guard let map else { return [] }
        var out: [String] = []
        for key in map.keys {
            // PsychonautWiki URLs: extract the path component.
            if key.contains("/wiki/"), let last = key.components(separatedBy: "/wiki/").last {
                let pretty = last.replacingOccurrences(of: "_", with: " ").removingPercentEncoding ?? last
                if !pretty.isEmpty { out.append(pretty) }
            } else if !key.isEmpty {
                out.append(key)
            }
        }
        return out.sorted()
    }

    private func parseDuration(value: RawTiming?, onset: RawTiming?, after: RawTiming?) -> JSONDurationProfile? {
        // Convert "{value: '3-5', _unit: 'hours'}" → JSONDurationRange in minutes.
        func toMinutes(_ t: RawTiming?) -> JSONDurationRange? {
            guard let t, let v = t.value, let unit = t.unit?.lowercased() else { return nil }
            let parts = v.replacingOccurrences(of: "+", with: "").components(separatedBy: CharacterSet(charactersIn: "-–"))
            guard let lo = Double(parts[0].trimmingCharacters(in: .whitespaces)) else { return nil }
            let hi = parts.count > 1 ? (Double(parts[1].trimmingCharacters(in: .whitespaces)) ?? lo) : lo
            let factor: Double = unit.contains("hour") ? 60 : (unit.contains("min") ? 1 : (unit.contains("day") ? 1440 : 60))
            return JSONDurationRange(min: lo * factor, max: hi * factor)
        }
        let p = JSONDurationProfile(
            onset: toMinutes(onset),
            comeup: nil, peak: nil, offset: nil,
            afterglow: toMinutes(after),
            total: toMinutes(value)
        )
        return p.isEmpty ? nil : p
    }
}
