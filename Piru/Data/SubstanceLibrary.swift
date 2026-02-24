import Foundation

enum SubstanceLibrary {
    static let all: [Substance] =
        stimulants
        + psychedelicsTryptamines
        + psychedelicsLysergamides
        + psychedelicsPhenethylamines
        + dissociatives
        + opioids
        + benzodiazepines
        + gabaergics
        + empathogens
        + cannabinoids
        + nootropics
        + antidepressants
        + antipsychotics
        + commonMedications
        + researchChemicalsStimulants
        + researchChemicalsPsychedelics
        + researchChemicalsDissociatives
        + researchChemicalsOpioids
        + researchChemicalsBenzodiazepines
        + researchChemicalsEmpathogens
        + supplements
        + hormones
        + additionalMedications

    static var byCategory: [SubstanceCategory: [Substance]] {
        Dictionary(grouping: all, by: \.category)
    }

    static func substances(in category: SubstanceCategory) -> [Substance] {
        all.filter { $0.category == category }
    }

    private static let nameLookup: [String: Substance] = {
        Dictionary(all.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }()

    /// O(1) exact-name lookup, used by QuickLogView grouping.
    static func lookup(_ name: String) -> Substance? {
        nameLookup[name.lowercased()]
    }

    /// Precomputed lowercased names/aliases so `search()` never calls `.lowercased()` per item.
    private static let searchIndex: [(substance: Substance, nameLower: String, aliasesLower: [String])] = {
        all.map { ($0, $0.name.lowercased(), $0.aliases.map { $0.lowercased() }) }
    }()

    static func search(_ query: String) -> [Substance] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()

        // Exact name match first, then alias match, then prefix, then contains
        var exact: [Substance] = []
        var aliasExact: [Substance] = []
        var prefix: [Substance] = []
        var contains: [Substance] = []

        for item in searchIndex {
            if item.nameLower == q {
                exact.append(item.substance)
            } else if item.aliasesLower.contains(q) {
                aliasExact.append(item.substance)
            } else if item.nameLower.hasPrefix(q) || item.aliasesLower.contains(where: { $0.hasPrefix(q) }) {
                prefix.append(item.substance)
            } else if item.nameLower.contains(q) || item.aliasesLower.contains(where: { $0.contains(q) }) {
                contains.append(item.substance)
            }
        }

        return exact + aliasExact + prefix + contains
    }
}
