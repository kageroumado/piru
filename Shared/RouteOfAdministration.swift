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

    var id: String {
        rawValue
    }

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

    var localizedName: LocalizedStringResource {
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
        case "oral", "oral_ir", "oral_er", "oral(benzedrex)", "oral(pure)": .oral
        case "sublingual": .sublingual
        case "insufflated", "insufflation", "insufflated(pure)", "intranasal", "nasal": .insufflation
        case "inhaled", "inhalation", "smoked", "vapourized", "vaporized": .inhalation
        case "intravenous", "iv": .intravenous
        case "intramuscular", "im": .intramuscular
        case "subcutaneous": .subcutaneous
        case "transdermal", "topical": .transdermal
        case "rectal", "plugged": .rectal
        default: .other
        }
    }
}
