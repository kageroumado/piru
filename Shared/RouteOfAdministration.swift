import Foundation
import SwiftUI

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
    /// A fixed tint per route — so a route reads the same everywhere (every "oral"
    /// badge is the same colour), independent of the substance's own colour. Used
    /// by the dose-row / detail ROA pills.
    var tintColor: Color {
        switch self {
        case .oral: Color(hex: "0A84FF") // blue
        case .sublingual: Color(hex: "30B0C7") // teal
        case .insufflation: Color(hex: "AF52DE") // purple
        case .inhalation: Color(hex: "FF9500") // orange
        case .intravenous: Color(hex: "FF3B30") // red
        case .intramuscular: Color(hex: "FF2D55") // pink
        case .subcutaneous: Color(hex: "5E5CE6") // indigo
        case .transdermal: Color(hex: "34C759") // green
        case .rectal: Color(hex: "A2845E") // brown
        case .other: Color(hex: "8E8E93") // gray
        }
    }

    /// Parse a route string from TripSit/OpenFDA into our enum
    nonisolated static func from(string: String) -> RouteOfAdministration {
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
