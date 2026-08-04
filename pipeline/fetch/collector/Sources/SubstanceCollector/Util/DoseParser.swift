import Foundation

/// Shared parser for "10-25 mg" style dose strings — used by both the
/// TripSit and Erowid pipelines.
enum DoseParser {
    struct Parsed: Hashable {
        let min: Double
        let max: Double?
        let unit: String
    }

    /// Liberal regex permitting unicode dash variants, optional spaces, decimal
    /// or whole numbers, and trailing `+` markers for "≥".
    private static let rangePattern: NSRegularExpression = {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(?:[-–—~tо]|to)\s*([0-9]+(?:\.[0-9]+)?)\s*([a-zA-ZµμμΜ/]+)"#
        return try! NSRegularExpression(pattern: pattern)
    }()
    private static let singlePattern: NSRegularExpression = {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*([a-zA-ZµμμΜ/]+)"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    static func parse(_ raw: String) -> Parsed? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip parentheticals: "10-25 mg (oral)" → "10-25 mg"
        if let paren = s.firstIndex(of: "(") {
            s = String(s[..<paren]).trimmingCharacters(in: .whitespaces)
        }
        // Strip leading/trailing labels: "common: 10-25 mg" → "10-25 mg"
        if let colon = s.lastIndex(of: ":") {
            s = String(s[s.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }

        let nsr = NSRange(s.startIndex ..< s.endIndex, in: s)
        if let m = rangePattern.firstMatch(in: s, range: nsr),
           let r0 = Range(m.range(at: 1), in: s),
           let r1 = Range(m.range(at: 2), in: s),
           let r2 = Range(m.range(at: 3), in: s),
           let lo = Double(s[r0]),
           let hi = Double(s[r1]) {
            let unit = normalizeUnit(String(s[r2]))
            return Parsed(min: lo, max: hi, unit: unit)
        }
        if let m = singlePattern.firstMatch(in: s, range: nsr),
           let r0 = Range(m.range(at: 1), in: s),
           let r2 = Range(m.range(at: 2), in: s),
           let v = Double(s[r0]) {
            return Parsed(min: v, max: nil, unit: normalizeUnit(String(s[r2])))
        }
        return nil
    }

    static func normalizeUnit(_ unit: String) -> String {
        let u = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        switch u.lowercased() {
        case "ug", "µg", "μg", "mcg", "ug.": return "µg"
        case "mg", "mg.": return "mg"
        case "g", "gm", "gram", "grams": return "g"
        case "ml", "mls", "ml.": return "ml"
        case "iu": return "IU"
        case "mg/kg": return "mg/kg"
        case "ug/kg", "µg/kg", "μg/kg": return "µg/kg"
        default: return u
        }
    }
}
