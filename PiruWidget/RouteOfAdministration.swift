import Foundation

enum RouteOfAdministration: String, Codable, CaseIterable, Identifiable {
    case oral
    case sublingual
    case insufflation
    case inhalation
    case intravenous
    case intramuscular
    case subcutaneous
    case transdermal
    case rectal
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .oral: "Oral"
        case .sublingual: "Sublingual"
        case .insufflation: "Insufflation"
        case .inhalation: "Inhalation"
        case .intravenous: "Intravenous"
        case .intramuscular: "Intramuscular"
        case .subcutaneous: "Subcutaneous"
        case .transdermal: "Transdermal"
        case .rectal: "Rectal"
        case .other: "Other"
        }
    }
}

extension RouteOfAdministration {
    /// Parse a route string from TripSit/OpenFDA into our enum
    static func from(string: String) -> RouteOfAdministration {
        switch string.lowercased().trimmingCharacters(in: .whitespaces) {
        case "oral", "oral_ir", "oral_er", "oral(benzedrex)", "oral(pure)": return .oral
        case "sublingual": return .sublingual
        case "insufflated", "insufflation", "insufflated(pure)", "intranasal", "nasal": return .insufflation
        case "inhaled", "inhalation", "smoked", "vapourized", "vaporized": return .inhalation
        case "intravenous", "iv": return .intravenous
        case "intramuscular", "im": return .intramuscular
        case "subcutaneous": return .subcutaneous
        case "transdermal", "topical": return .transdermal
        case "rectal", "plugged": return .rectal
        default: return .other
        }
    }
}
