import Foundation

/// Compound-specific harm-reduction warnings appended to the `effects` array
/// (which the iOS detail view surfaces directly to users). These represent
/// non-obvious risks where the standard category banner is insufficient.
enum SafetyWarnings {
    private struct Rule {
        let predicate: (String, [String]) -> Bool
        let warning: String
    }

    /// Each rule's predicate receives the normalized name and the tag set.
    private static let rules: [Rule] = [
        // Chlorinated cathinones — neurotoxicity concern
        Rule(
            predicate: { name, _ in
                let n = name.lowercased()
                return [
                    "4-cmc",
                    "3-cmc",
                    "2-cmc",
                    "4cmc",
                    "3cmc",
                    "2cmc",
                    "clephedrone",
                ].contains(where: n.contains)
            },
            warning: "Emerging in-vitro evidence suggests neurotoxicity beyond other cathinones",
        ),
        // Nitazenes — extreme opioid potency
        Rule(
            predicate: { name, tags in
                tags.contains("nitazene") || name.lowercased().contains("nitazene")
            },
            warning: "Extreme potency, 10-100x fentanyl. Naloxone may require multiple doses",
        ),
        // PMA / PMMA / 4-MTA — delayed onset
        Rule(
            predicate: { name, _ in
                let n = name.lowercased()
                return [
                    "pmma",
                    "pma",
                    "4-mta",
                    "4mta",
                    "para-methoxyamphetamine",
                    "para-methoxymethamphetamine",
                ].contains(where: { n == $0 || n.contains($0) })
            },
            warning: "Delayed onset leads to redose overdose deaths — DO NOT redose",
        ),
        // Tianeptine
        Rule(
            predicate: { name, _ in name.lowercased().contains("tianeptine") },
            warning: "Mu-opioid agonist activity; addiction and overdose risk",
        ),
        // Phenibut / F-phenibut
        Rule(
            predicate: { name, _ in
                let n = name.lowercased()
                return n.contains("phenibut") || n.contains("fluorophenibut")
            },
            warning: "Severe protracted withdrawal; dependence in weeks of daily use",
        ),
    ]

    /// Returns warnings applicable to a substance. Multiple may apply.
    static func warnings(for name: String, tags: [String]) -> [String] {
        rules.compactMap { $0.predicate(name, tags) ? $0.warning : nil }
    }
}
