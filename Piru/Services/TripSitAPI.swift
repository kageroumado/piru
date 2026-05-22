import Foundation
import os

private let logger = Logger(subsystem: "dev.yumeji.piru", category: "TripSitAPI")

/// TripSit API client — fetches recreational/research substance data
struct TripSitAPI {
    static let allDrugsURL = URL(string: "https://tripsit.me/api/tripsit/getAllDrugs")!

    struct TripSitDrug: Decodable {
        let name: String
        let pretty_name: String?
        let aliases: [String]?
        let categories: [String]?
        let properties: Properties?
        let formatted_dose: [String: [String: String]]?
        let combos: [String: ComboInfo]?
        let pweffects: [String: String]?

        struct Properties: Decodable {
            let summary: String?
            let dose: String?
            let duration: String?
            let onset: String?
            let aliases: [String]?
            let categories: [String]?
            let avoid: String?
            let halfLife: String?

            enum CodingKeys: String, CodingKey {
                case summary, dose, duration, onset, aliases, categories, avoid
                case halfLife = "half-life"
            }
        }

        struct ComboInfo: Decodable {
            let status: String?
            let note: String?
        }
    }

    /// Fetch all drugs from TripSit. Returns dictionary keyed by drug name.
    static func fetchAll() async throws -> [String: TripSitDrug] {
        var request = URLRequest(url: allDrugsURL)
        request.setValue("Piru/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.badResponse
        }

        let json = try JSONSerialization.jsonObject(with: data)

        var drugDict: [String: Any] = [:]
        if let arr = json as? [[String: Any]], let first = arr.first {
            drugDict = first
        } else if let dict = json as? [String: Any],
                  let dataArr = dict["data"] as? [[String: Any]],
                  let first = dataArr.first {
            drugDict = first
        } else if let dict = json as? [String: Any] {
            drugDict = dict
        }

        var result: [String: TripSitDrug] = [:]
        var decodeFailures = 0
        let decoder = JSONDecoder()
        for (key, value) in drugDict {
            guard let valueDict = value as? [String: Any] else { continue }
            do {
                let encoded = try JSONSerialization.data(withJSONObject: valueDict)
                let drug = try decoder.decode(TripSitDrug.self, from: encoded)
                result[key] = drug
            } catch {
                decodeFailures += 1
                logger.debug("Decode failed for \(key): \(error.localizedDescription)")
            }
        }
        if decodeFailures > 0 {
            logger.warning("\(decodeFailures) drugs failed to decode")
        }

        return result
    }

    /// Name-based overrides for substances TripSit doesn't categorize well
    private static let categoryOverrides: [String: SubstanceCategory] = [
        // Analgesics tagged only as "common"
        "aspirin": .analgesic,
        "ibuprofen": .analgesic,
        "naproxen": .analgesic,
        "paracetamol": .analgesic,
        // Antihistamines
        "promethazine": .antihistamine,
        // Antidepressants / mood stabilizers
        "lithium": .antidepressant,
        "moclobemide": .antidepressant,
        // Nootropics
        "oxiracetam": .nootropic,
        // Stimulants
        "theobromine": .stimulant,
        "4-fpm": .stimulant,
        "mephtetramine": .stimulant,
        "2-nmc": .stimulant,
        "4-cic": .stimulant,
        "db-mdbp": .stimulant,
        "pv-9": .stimulant,
        "pv-10": .stimulant,
        // Empathogens
        "4-cma": .empathogen,
        "dibutylone": .empathogen,
        "dimethylone": .empathogen,
        // Synthetic cannabinoids
        "5f-akb48": .cannabinoid,
        "5f-pb-22": .cannabinoid,
        "ab-chminaca": .cannabinoid,
        "ab-fubinaca": .cannabinoid,
        "am-2201": .cannabinoid,
        // Benzodiazepines
        "4-chlorodiazepam": .benzodiazepine,
        // Opioids
        "etodesnitazene": .opioid,
        // Psychedelics
        "c30-nbome": .psychedelic,
        // Depressants
        "methoxypiperamide": .depressant,
    ]

    /// Convert a TripSit drug to our Substance model
    static func toSubstance(_ drug: TripSitDrug) -> Substance {
        let name = drug.pretty_name ?? drug.name
        let aliases = drug.aliases ?? drug.properties?.aliases ?? []
        let allCategories = drug.categories ?? drug.properties?.categories ?? []
        // Skip modifier categories (common, habit-forming, etc.) and pick the first substantive one
        let categoryStr = allCategories.first { !SubstanceCategory.modifierCategories.contains($0.lowercased()) }
            ?? allCategories.first ?? ""
        let category = categoryOverrides[name.lowercased()]
            ?? categoryOverrides[drug.name.lowercased()]
            ?? SubstanceCategory.from(tripSitCategory: categoryStr)

        // Parse per-route timing data from properties
        let (onsetByRoute, fallbackOnset) = parseRouteTimings(drug.properties?.onset)
        let (durationByRoute, fallbackDuration) = parseRouteTimings(drug.properties?.duration)

        var routes: [SubstanceRoute] = []
        if let doseInfo = drug.formatted_dose {
            for (routeName, levels) in doseInfo {
                let route = RouteOfAdministration.from(string: routeName)
                let routeOnset = onsetByRoute[route] ?? fallbackOnset
                let routeTotal = durationByRoute[route] ?? fallbackDuration
                let durationProfile = buildDurationProfile(onsetRange: routeOnset, totalRange: routeTotal)

                // Body-weight-scaled doses ("1.5-2.5mg/kg") can't be rendered as
                // absolute amounts without the user's weight, and pretending they
                // are would be dangerously misleading (e.g. DXM). Emit the route
                // with empty doses so duration/timeline rendering still works and
                // a per-substance dose override or another source can supply
                // correct absolute doses.
                let hasKgScaled = levels.values.contains(where: { $0.lowercased().contains("/kg") })
                let (doseRange, unit) = hasKgScaled
                    ? (DoseRange(), "mg")
                    : parseDoseRangeAndUnit(levels)
                routes.append(SubstanceRoute(route: route, unit: unit, doses: doseRange, duration: durationProfile))
            }
        }

        // TripSit often ships per-route duration data for routes that have no
        // dose data (e.g. cannabis publishes both Smoked and Oral timings but
        // only Smoked dose ranges). Without these dose-less routes the
        // single-route fallback in Substance.resolveDuration would hand the
        // user one route's timing for an entirely different ROA. Materialise
        // any leftover timed routes here so each ROA carries its own timeline.
        let coveredRoutes = Set(routes.map(\.route))
        let timedRoutes = Set(onsetByRoute.keys).union(durationByRoute.keys)
        for route in timedRoutes.subtracting(coveredRoutes) {
            let durationProfile = buildDurationProfile(
                onsetRange: onsetByRoute[route] ?? fallbackOnset,
                totalRange: durationByRoute[route] ?? fallbackDuration
            )
            routes.append(SubstanceRoute(route: route, unit: "mg", doses: DoseRange(), duration: durationProfile))
        }

        var halfLifeMinutes: Double? = nil
        if let hlStr = drug.properties?.halfLife {
            halfLifeMinutes = parseHalfLifeMinutes(hlStr)
        }

        let effects = drug.pweffects?.keys.map { String($0) } ?? []
        let defaultRoute = routes.first?.route ?? .oral

        return Substance(
            name: name,
            aliases: aliases,
            category: category,
            defaultRoute: defaultRoute,
            routes: routes,
            effects: effects,
            subjectiveEffects: [],
            toleranceInfo: nil,
            halfLifeMinutes: halfLifeMinutes,
            sources: ["TripSit"]
        )
    }

    /// Mass-unit conversion factors to milligrams. Used to normalise mixed-unit
    /// dose ranges (e.g. TripSit aspirin: Threshold/Light/Common in mg, Heavy in g).
    private static let massUnitsToMg: [String: Double] = ["µg": 0.001, "mg": 1, "g": 1000]

    /// Detect the unit substring in a TripSit dose-level string. Returns nil if no
    /// recognized unit is present (the caller then assumes the prevailing unit).
    private static func detectUnit(_ value: String) -> String? {
        let cleaned = value.lowercased()
        if cleaned.contains("ug") || cleaned.contains("µg") { return "µg" }
        if cleaned.contains("mg") { return "mg" }
        if cleaned.contains("ml") { return "mL" }
        if cleaned.contains("unit") { return "units" }
        if cleaned.contains("hit") { return "hits" }
        if cleaned.contains("drink") { return "drinks" }
        // 'g' check has to come after mg/µg so they don't fall through.
        if cleaned.hasSuffix("g") || cleaned.contains(" g") { return "g" }
        return nil
    }

    /// Parse a TripSit dose-level dictionary into a DoseRange plus the canonical
    /// unit it's expressed in. Per-level units are detected individually and, if
    /// they mix across mass units, all values are converted to the smallest unit
    /// present (preserving precision). Non-mass units (units/hits/drinks/mL) pass
    /// through unchanged — they shouldn't mix with mass units in practice.
    private static func parseDoseRangeAndUnit(_ levels: [String: String]) -> (DoseRange, String) {
        func parseFirst(_ str: String) -> Double? {
            let cleaned = str.replacingOccurrences(of: "[^0-9.]", with: " ", options: .regularExpression)
            return cleaned.split(separator: " ").compactMap { Double($0) }.first
        }
        func parseLast(_ str: String) -> Double? {
            let cleaned = str.replacingOccurrences(of: "[^0-9.]", with: " ", options: .regularExpression)
            let nums = cleaned.split(separator: " ").compactMap { Double($0) }
            return nums.count > 1 ? nums.last : nums.first
        }

        // Detect a unit per level; choose canonical unit.
        let perLevelUnit = levels.compactMapValues { detectUnit($0) }
        let presentUnits = Set(perLevelUnit.values)
        let canonicalUnit: String = {
            if presentUnits.count == 1, let u = presentUnits.first { return u }
            // Mixed mass units → normalise to the smallest present (preserves precision).
            let massPresent = presentUnits.intersection(massUnitsToMg.keys)
            if !massPresent.isEmpty {
                return massPresent.min { massUnitsToMg[$0]! < massUnitsToMg[$1]! } ?? "mg"
            }
            return perLevelUnit.values.first ?? "mg"
        }()

        func scaled(_ raw: Double?, in levelKey: String) -> Double? {
            guard let raw else { return nil }
            guard let levelUnit = perLevelUnit[levelKey],
                  let from = massUnitsToMg[levelUnit],
                  let to = massUnitsToMg[canonicalUnit],
                  levelUnit != canonicalUnit else { return raw }
            return raw * from / to
        }

        let threshold = scaled(levels["Threshold"].flatMap(parseFirst), in: "Threshold")
        let light = scaled(levels["Light"].flatMap(parseLast), in: "Light")
        let common = scaled(levels["Common"].flatMap(parseLast), in: "Common")
        let strong = scaled(levels["Strong"].flatMap(parseLast), in: "Strong")
        let heavy = scaled(levels["Heavy"].flatMap(parseFirst), in: "Heavy")

        let lightRange: ClosedRange<Double>? = {
            guard let l = light else { return nil }
            let lower = threshold ?? l * 0.5
            guard lower <= l else { return nil }
            return lower...l
        }()
        let commonRange: ClosedRange<Double>? = {
            guard let c = common else { return nil }
            let lower = light ?? c * 0.5
            guard lower <= c else { return nil }
            return lower...c
        }()
        let strongRange: ClosedRange<Double>? = {
            guard let s = strong else { return nil }
            let lower = common ?? s * 0.5
            guard lower <= s else { return nil }
            return lower...s
        }()

        let range = DoseRange(
            threshold: threshold,
            light: lightRange,
            common: commonRange,
            strong: strongRange,
            heavy: heavy ?? strong.map { $0 * 1.5 }
        )
        return (range, canonicalUnit)
    }

    /// Parse a TripSit duration/onset string like "4-8 hours" or "30-60 minutes" into a DurationRange in minutes.
    private static func parseTimeRange(_ str: String) -> DurationRange? {
        let first = str.components(separatedBy: "|").first?
            .trimmingCharacters(in: .whitespaces) ?? str

        let lower = first.lowercased()
        let isHours = lower.contains("hour")
        let isMinutes = lower.contains("min")
        let multiplier: Double = isHours ? 60 : (isMinutes ? 1 : 60)

        let nums = first.replacingOccurrences(of: "[^0-9.]", with: " ", options: .regularExpression)
            .split(separator: " ").compactMap { Double($0) }
        guard let lo = nums.first else { return nil }
        let hi = nums.count > 1 ? nums[1] : lo
        guard lo > 0 else { return nil }
        return DurationRange(min: lo * multiplier, max: hi * multiplier)
    }

    /// Parse pipe-separated route timings like "Oral: 20-75 minutes | Insufflated: 1-10 minutes"
    /// into per-route DurationRanges plus a fallback for unkeyed values.
    private static func parseRouteTimings(_ str: String?) -> (byRoute: [RouteOfAdministration: DurationRange], fallback: DurationRange?) {
        guard let str else { return ([:], nil) }
        var byRoute: [RouteOfAdministration: DurationRange] = [:]
        var fallback: DurationRange?

        let segments = str.components(separatedBy: "|")
        for segment in segments {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))

            var routeName: String?
            var timePortion: String = trimmed

            if let colonIdx = trimmed.firstIndex(of: ":") {
                // "Oral: 20-75 minutes" format
                routeName = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                timePortion = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            } else {
                // Try "Insufflated 2-5 hours" format (no colon)
                let words = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
                if words.count >= 2 {
                    let candidate = RouteOfAdministration.from(string: words[0])
                    if candidate != .other {
                        routeName = words[0]
                        timePortion = words[1]
                    }
                }
            }

            if let routeName, let range = parseTimeRange(timePortion) {
                byRoute[RouteOfAdministration.from(string: routeName)] = range
            } else if let range = parseTimeRange(timePortion) {
                fallback = fallback ?? range
            }
        }

        return (byRoute, fallback)
    }

    /// Build a DurationProfile from onset/total DurationRanges, estimating intermediate phases.
    /// Estimated values are rounded to the nearest 5 minutes (or 15 minutes above 60 min).
    private static func buildDurationProfile(onsetRange: DurationRange?, totalRange: DurationRange?) -> DurationProfile? {
        guard totalRange != nil || onsetRange != nil else { return nil }

        let totalMid = totalRange?.midpoint ?? 240
        let onsetMid = min(onsetRange?.midpoint ?? totalMid * 0.10, totalMid * 0.25)
        let remaining = max(totalMid - onsetMid, totalMid * 0.5)

        let comeup = remaining * 0.15
        let peak = remaining * 0.40
        let offset = remaining * 0.30
        let afterglow = remaining * 0.15

        return DurationProfile(
            onset: onsetRange ?? roundedRange(midpoint: onsetMid),
            comeup: roundedRange(midpoint: comeup),
            peak: roundedRange(midpoint: peak),
            offset: roundedRange(midpoint: offset),
            afterglow: roundedRange(midpoint: afterglow),
            total: totalRange ?? roundedRange(midpoint: totalMid)
        )
    }

    /// Create a DurationRange with ±30% variance, rounded to friendly intervals.
    private static func roundedRange(midpoint: Double) -> DurationRange {
        let lo = midpoint * 0.7
        let hi = midpoint * 1.3
        return DurationRange(min: roundMinutes(lo), max: roundMinutes(hi))
    }

    /// Round minutes to the nearest 5 (under 60 min) or nearest 15 (60 min and above), no decimals.
    private static func roundMinutes(_ value: Double) -> Double {
        let step: Double = value < 60 ? 5 : 15
        return max(step, (value / step).rounded() * step).rounded()
    }

    private static func parseHalfLifeMinutes(_ str: String) -> Double? {
        let nums = str.replacingOccurrences(of: "[^0-9.]", with: " ", options: .regularExpression)
            .split(separator: " ").compactMap { Double($0) }
        guard let value = nums.first else { return nil }
        if str.lowercased().contains("hour") { return value * 60 }
        if str.lowercased().contains("day") { return value * 60 * 24 }
        return value
    }

    enum APIError: Error {
        case badResponse
    }
}
