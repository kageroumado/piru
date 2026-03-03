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
        let decoder = JSONDecoder()
        for (key, value) in drugDict {
            guard let valueDict = value as? [String: Any] else { continue }
            if let encoded = try? JSONSerialization.data(withJSONObject: valueDict),
               let drug = try? decoder.decode(TripSitDrug.self, from: encoded) {
                result[key] = drug
            }
        }

        return result
    }

    /// Convert a TripSit drug to our Substance model
    static func toSubstance(_ drug: TripSitDrug) -> Substance {
        let name = drug.pretty_name ?? drug.name
        let aliases = drug.aliases ?? drug.properties?.aliases ?? []
        let categoryStr = drug.categories?.first ?? drug.properties?.categories?.first ?? ""
        let category = SubstanceCategory.from(tripSitCategory: categoryStr)

        var routes: [SubstanceRoute] = []
        if let doseInfo = drug.formatted_dose {
            for (routeName, levels) in doseInfo {
                let route = RouteOfAdministration.from(string: routeName)
                let doseRange = parseDoseRange(levels)
                let unit = extractUnit(from: levels) ?? "mg"
                routes.append(SubstanceRoute(route: route, unit: unit, doses: doseRange))
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
            return lower...l
        }()
        let commonRange: ClosedRange<Double>? = {
            guard let c = common else { return nil }
            let lower = light ?? c * 0.5
            return lower...c
        }()
        let strongRange: ClosedRange<Double>? = {
            guard let s = strong else { return nil }
            let lower = common ?? s * 0.5
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
            if cleaned.hasSuffix("g") { return "g" }
        }
        return nil
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
