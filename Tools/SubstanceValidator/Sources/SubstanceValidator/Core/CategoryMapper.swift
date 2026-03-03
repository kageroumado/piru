import Foundation

/// Maps API category strings to Piru's SubstanceCategory enum case names.
enum CategoryMapper {
    /// Categories that are modifiers/flags, not substantive classifications.
    private static let modifierCategories: Set<String> = [
        "tentative", "research-chemical", "habit-forming", "common",
        "inactive", "supplement", "nootropic",
    ]

    /// Map from API category string to local enum case name.
    private static let categoryMap: [String: String] = [
        "stimulant": "stimulant",
        "stimulants": "stimulant",
        "psychedelic": "psychedelic",
        "psychedelics": "psychedelic",
        "hallucinogen": "psychedelic",
        "dissociative": "dissociative",
        "dissociatives": "dissociative",
        "opioid": "opioid",
        "opioids": "opioid",
        "opiate": "opioid",
        "opiates": "opioid",
        "depressant": "depressant",
        "depressants": "depressant",
        "sedative": "depressant",
        "sedatives": "depressant",
        "benzodiazepine": "benzodiazepine",
        "benzodiazepines": "benzodiazepine",
        "barbiturate": "gabapentinoid",
        "barbiturates": "gabapentinoid",
        "gabapentinoid": "gabapentinoid",
        "gabapentinoids": "gabapentinoid",
        "gabaergic": "gabapentinoid",
        "empathogen": "empathogen",
        "empathogens": "empathogen",
        "entactogen": "empathogen",
        "entactogens": "empathogen",
        "cannabinoid": "cannabinoid",
        "cannabinoids": "cannabinoid",
        "nootropic": "nootropic",
        "nootropics": "nootropic",
        "supplement": "supplement",
        "supplements": "supplement",
        "antidepressant": "antidepressant",
        "antidepressants": "antidepressant",
        "ssri": "antidepressant",
        "snri": "antidepressant",
        "maoi": "antidepressant",
        "antipsychotic": "antipsychotic",
        "antipsychotics": "antipsychotic",
        "deliriant": "antihistamine",
        "deliriants": "antihistamine",
        "antihistamine": "antihistamine",
        "analgesic": "analgesic",
        "cardiovascular": "cardiovascular",
        "antimicrobial": "antimicrobial",
        "gastrointestinal": "gastrointestinal",
        "respiratory": "respiratory",
        "endocrine": "endocrine",
        "immunological": "immunological",
    ]

    /// Priority order: when multiple substantive categories exist, pick the highest-priority one.
    private static let priorityOrder: [String] = [
        "opioid", "benzodiazepine", "dissociative", "empathogen",
        "psychedelic", "stimulant", "cannabinoid", "depressant",
        "antidepressant", "antipsychotic", "gabapentinoid",
        "nootropic", "supplement", "antihistamine", "analgesic",
        "cardiovascular", "antimicrobial", "gastrointestinal",
        "respiratory", "endocrine", "immunological",
    ]

    /// Map an array of API categories to a single local SubstanceCategory enum case name.
    static func mapCategories(_ apiCategories: [String]) -> String {
        let substantive = apiCategories
            .map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            .filter { !modifierCategories.contains($0) }

        for priority in priorityOrder {
            for cat in substantive {
                if let mapped = categoryMap[cat], mapped == priority {
                    return mapped
                }
            }
        }

        // Try direct mapping for any remaining category
        for cat in substantive {
            if let mapped = categoryMap[cat] {
                return mapped
            }
        }

        return "other"
    }
}
