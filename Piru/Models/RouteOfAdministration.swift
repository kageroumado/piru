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
