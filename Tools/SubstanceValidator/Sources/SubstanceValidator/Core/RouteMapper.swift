import Foundation

/// Maps API route name strings to the Piru RouteOfAdministration enum case names.
enum RouteMapper {
    private static let routeMap: [String: String] = [
        // TripSit / PsychonautWiki route names → enum case name
        "oral": "oral",
        "sublingual": "sublingual",
        "buccal": "sublingual",
        "insufflated": "insufflation",
        "insufflation": "insufflation",
        "intranasal": "insufflation",
        "nasal": "insufflation",
        "inhaled": "inhalation",
        "inhalation": "inhalation",
        "smoked": "inhalation",
        "smoking": "inhalation",
        "vapourized": "inhalation",
        "vaporized": "inhalation",
        "intravenous": "intravenous",
        "iv": "intravenous",
        "intramuscular": "intramuscular",
        "im": "intramuscular",
        "subcutaneous": "subcutaneous",
        "transdermal": "transdermal",
        "topical": "transdermal",
        "rectal": "rectal",
        "plugged": "rectal",
    ]

    /// Map an API route string to the local RouteOfAdministration enum case name.
    /// Returns the lowercased enum case (e.g., "oral", "insufflation", "inhalation").
    static func mapRoute(_ apiRoute: String) -> String {
        let key = apiRoute.lowercased().trimmingCharacters(in: .whitespaces)
        return routeMap[key] ?? "other"
    }
}
