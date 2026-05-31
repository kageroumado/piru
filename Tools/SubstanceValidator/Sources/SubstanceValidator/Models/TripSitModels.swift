import Foundation

// MARK: - TripSit drugs.json Response

/// The top-level drugs.json is a dictionary keyed by drug name.
/// Each value is a TripSitDrug object.
typealias TripSitDrugDatabase = [String: TripSitDrug]

struct TripSitDrug: Codable {
    let aliases: [String]?
    let categories: [String]?
    let formattedDose: [String: [String: String]]?
    let formattedDuration: TripSitTiming?
    let formattedOnset: TripSitTiming?
    let formattedAftereffects: TripSitTiming?
    let doseNote: String?
    let properties: TripSitProperties?
    let pweffects: [String: String]?

    enum CodingKeys: String, CodingKey {
        case aliases
        case categories
        case properties
        case pweffects
        case formattedDose = "formatted_dose"
        case formattedDuration = "formatted_duration"
        case formattedOnset = "formatted_onset"
        case formattedAftereffects = "formatted_aftereffects"
        case doseNote = "dose_note"
    }
}

struct TripSitTiming: Codable {
    let unit: String?
    let value: String?

    enum CodingKeys: String, CodingKey {
        case unit = "_unit"
        case value
    }
}

struct TripSitProperties: Codable {
    let summary: String?
    let halfLife: String?
    let bioavailability: String?
    let avoid: String?
    let dose: String?
    let duration: String?
    let onset: String?

    enum CodingKeys: String, CodingKey {
        case summary
        case bioavailability
        case avoid
        case dose
        case duration
        case onset
        case halfLife = "half-life"
    }
}

// MARK: - Parsed Dose

struct ParsedTripSitDose {
    let min: Double
    let max: Double?
    let unit: String

    var range: ClosedRange<Double>? {
        guard let max else { return nil }
        return min ... max
    }
}

enum TripSitDoseParser {
    // Multiple regex patterns in order of specificity

    // Standard: "10-25mg", "0.5-1ml", "25mg+", "100ug"
    private static let standardRegex = try! NSRegularExpression(
        pattern: "^([0-9.]+)\\s*(?:[-\u{2013}]\\s*([0-9.]+))?\\s*([a-zA-Z\u{00B5}\u{03BC}/]+)?\\s*\\+?$",
    )
    /// Word range: "10 to 25 mg", "0.5 to 1 ml"
    private static let wordRangeRegex = try! NSRegularExpression(
        pattern: "^([0-9.]+)\\s+to\\s+([0-9.]+)\\s*([a-zA-Z\u{00B5}\u{03BC}/]+)?$",
    )
    // Weight-based: "1-2 mg/kg", "0.5mg/kg"
    private static let weightBasedRegex = try! NSRegularExpression(
        pattern: "^([0-9.]+)\\s*(?:[-\u{2013}]\\s*([0-9.]+))?\\s*(mg/kg|ug/kg|g/kg)$",
    )
    /// Unit then number: "mg 10-25" (rare but occurs)
    private static let unitFirstRegex = try! NSRegularExpression(
        pattern: "^([a-zA-Z\u{00B5}\u{03BC}]+)\\s*([0-9.]+)\\s*[-\u{2013}]\\s*([0-9.]+)$",
    )

    static func parse(_ string: String) -> ParsedTripSitDose? {
        // Strip embedded notes/parentheticals: "10-25mg (careful)" → "10-25mg"
        var trimmed = string.trimmingCharacters(in: .whitespaces)
        if let parenRange = trimmed.range(of: "(") {
            trimmed = String(trimmed[trimmed.startIndex ..< parenRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
        }

        // Try each pattern
        if let result = tryStandard(trimmed) { return result }
        if let result = tryWordRange(trimmed) { return result }
        if let result = tryWeightBased(trimmed) { return result }
        if let result = tryUnitFirst(trimmed) { return result }

        return nil
    }

    private static func tryStandard(_ s: String) -> ParsedTripSitDose? {
        let range = NSRange(s.startIndex..., in: s)
        guard let match = standardRegex.firstMatch(in: s, range: range) else { return nil }

        guard let minRange = Range(match.range(at: 1), in: s),
              let minValue = Double(s[minRange]) else { return nil }

        var maxValue: Double?
        if match.range(at: 2).location != NSNotFound,
           let maxRange = Range(match.range(at: 2), in: s) {
            maxValue = Double(s[maxRange])
        }

        var unit = "mg"
        if match.range(at: 3).location != NSNotFound,
           let unitRange = Range(match.range(at: 3), in: s) {
            unit = String(s[unitRange])
        }

        return ParsedTripSitDose(min: minValue, max: maxValue, unit: normalizeUnit(unit))
    }

    private static func tryWordRange(_ s: String) -> ParsedTripSitDose? {
        let range = NSRange(s.startIndex..., in: s)
        guard let match = wordRangeRegex.firstMatch(in: s, range: range) else { return nil }

        guard let minRange = Range(match.range(at: 1), in: s),
              let minValue = Double(s[minRange]),
              let maxRange = Range(match.range(at: 2), in: s),
              let maxValue = Double(s[maxRange]) else { return nil }

        var unit = "mg"
        if match.range(at: 3).location != NSNotFound,
           let unitRange = Range(match.range(at: 3), in: s) {
            unit = String(s[unitRange])
        }

        return ParsedTripSitDose(min: minValue, max: maxValue, unit: normalizeUnit(unit))
    }

    private static func tryWeightBased(_ s: String) -> ParsedTripSitDose? {
        let range = NSRange(s.startIndex..., in: s)
        guard let match = weightBasedRegex.firstMatch(in: s, range: range) else { return nil }

        guard let minRange = Range(match.range(at: 1), in: s),
              let minValue = Double(s[minRange]) else { return nil }

        var maxValue: Double?
        if match.range(at: 2).location != NSNotFound,
           let maxRange = Range(match.range(at: 2), in: s) {
            maxValue = Double(s[maxRange])
        }

        var unit = "mg/kg"
        if let unitRange = Range(match.range(at: 3), in: s) {
            unit = String(s[unitRange])
        }

        return ParsedTripSitDose(min: minValue, max: maxValue, unit: normalizeUnit(unit))
    }

    private static func tryUnitFirst(_ s: String) -> ParsedTripSitDose? {
        let range = NSRange(s.startIndex..., in: s)
        guard let match = unitFirstRegex.firstMatch(in: s, range: range) else { return nil }

        guard let unitRange = Range(match.range(at: 1), in: s),
              let minRange = Range(match.range(at: 2), in: s),
              let minValue = Double(s[minRange]),
              let maxRange = Range(match.range(at: 3), in: s),
              let maxValue = Double(s[maxRange]) else { return nil }

        let unit = String(s[unitRange])
        return ParsedTripSitDose(min: minValue, max: maxValue, unit: normalizeUnit(unit))
    }

    static func normalizeUnit(_ unit: String) -> String {
        switch unit.lowercased() {
        case "ug", "µg", "μg", "mcg": "µg"
        case "mg": "mg"
        case "g": "g"
        case "ml": "ml"
        case "iu": "IU"
        case "mg/kg": "mg/kg"
        case "ug/kg", "µg/kg": "µg/kg"
        default: unit
        }
    }
}
