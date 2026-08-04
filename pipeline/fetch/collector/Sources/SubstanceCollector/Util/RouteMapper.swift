import Foundation

/// Maps API route strings to the iOS `RouteOfAdministration` raw value.
enum RouteMapper {
    private static let table: [String: String] = [
        "oral": "oral", "oral_ir": "oral", "oral_er": "oral",
        "po": "oral", "swallowed": "oral", "ingested": "oral",
        "sublingual": "sublingual", "buccal": "sublingual",
        "sl": "sublingual",
        "insufflated": "insufflation", "insufflation": "insufflation",
        "intranasal": "insufflation", "nasal": "insufflation",
        "snorted": "insufflation", "in": "insufflation",
        "inhaled": "inhalation", "inhalation": "inhalation",
        "smoked": "inhalation", "smoking": "inhalation",
        "vapourized": "inhalation", "vaporized": "inhalation",
        "vape": "inhalation", "vaped": "inhalation",
        "intravenous": "intravenous", "iv": "intravenous",
        "intramuscular": "intramuscular", "im": "intramuscular",
        "subcutaneous": "subcutaneous", "sc": "subcutaneous", "sq": "subcutaneous",
        "transdermal": "transdermal", "topical": "transdermal", "td": "transdermal",
        "rectal": "rectal", "plugged": "rectal", "pr": "rectal",
    ]

    static func map(_ raw: String) -> String {
        table[raw.lowercased().trimmingCharacters(in: .whitespaces)] ?? "other"
    }
}
