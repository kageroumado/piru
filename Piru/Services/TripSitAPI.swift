import Foundation

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
            }
        }
        if decodeFailures > 0 {
            print("[TripSitAPI] \(decodeFailures) drugs failed to decode")
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
                let doseRange = hasKgScaled ? DoseRange() : parseDoseRange(levels)
                let unit = extractUnit(from: levels) ?? "mg"
                routes.append(SubstanceRoute(route: route, unit: unit, doses: doseRange, duration: durationProfile))
            }
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

    private static func parseDoseRange(_ levels: [String: String]) -> DoseRange {
        func parseValue(_ str: String) -> Double? {
            let cleaned = str.replacingOccurrences(of: "[^0-9.]", with: " ", options: .regularExpression)
            return cleaned.split(separator: " ").compactMap { Double($0) }.first
        }
        func parseMax(_ str: String) -> Double? {
            let cleaned = str.replacingOccurrences(of: "[^0-9.]", with: " ", options: .regularExpression)
            let nums = cleaned.split(separator: " ").compactMap { Double($0) }
            return nums.count > 1 ? nums.last : nums.first
        }

        let threshold = levels["Threshold"].flatMap { parseValue($0) }
        let light = levels["Light"].flatMap { parseMax($0) }
        let common = levels["Common"].flatMap { parseMax($0) }
        let strong = levels["Strong"].flatMap { parseMax($0) }
        let heavy = levels["Heavy"].flatMap { parseValue($0) }

        // Build ranges from threshold->light, light->common, etc.
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

        return DoseRange(
            threshold: threshold,
            light: lightRange,
            common: commonRange,
            strong: strongRange,
            heavy: heavy ?? strong.map { $0 * 1.5 }
        )
    }

    private static func extractUnit(from levels: [String: String]) -> String? {
        for value in levels.values {
            let cleaned = value.lowercased()
            if cleaned.contains("ug") || cleaned.contains("µg") { return "µg" }
            if cleaned.contains("mg") { return "mg" }
            if cleaned.contains("ml") { return "mL" }
            // Non-standard TripSit units (standard drinks, inhalation hits)
            if cleaned.contains("unit") { return "units" }
            if cleaned.contains("hit") { return "hits" }
            if cleaned.contains("drink") { return "drinks" }
            if cleaned.hasSuffix("g") || cleaned.contains(" g") { return "g" }
        }
        return nil
    }

    /// Parse a TripSit duration/onset string like "4-8 hours" or "30-60 minutes" into a TimeRange in minutes.
    private static func parseTimeRange(_ str: String) -> TimeRange? {
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
        return TimeRange(min: lo * multiplier, max: hi * multiplier)
    }

    /// Parse pipe-separated route timings like "Oral: 20-75 minutes | Insufflated: 1-10 minutes"
    /// into per-route TimeRanges plus a fallback for unkeyed values.
    private static func parseRouteTimings(_ str: String?) -> (byRoute: [RouteOfAdministration: TimeRange], fallback: TimeRange?) {
        guard let str else { return ([:], nil) }
        var byRoute: [RouteOfAdministration: TimeRange] = [:]
        var fallback: TimeRange?

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

    /// Build a DurationProfile from onset/total TimeRanges, estimating intermediate phases.
    /// Estimated values are rounded to the nearest 5 minutes (or 15 minutes above 60 min).
    private static func buildDurationProfile(onsetRange: TimeRange?, totalRange: TimeRange?) -> DurationProfile? {
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

    /// Create a TimeRange with ±30% variance, rounded to friendly intervals.
    private static func roundedRange(midpoint: Double) -> TimeRange {
        let lo = midpoint * 0.7
        let hi = midpoint * 1.3
        return TimeRange(min: roundMinutes(lo), max: roundMinutes(hi))
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
