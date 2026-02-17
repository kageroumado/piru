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

    static func search(_ query: String) -> [Substance] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()

        // Exact name match first, then alias match, then prefix, then contains
        var exact: [Substance] = []
        var aliasExact: [Substance] = []
        var prefix: [Substance] = []
        var contains: [Substance] = []

        for substance in all {
            let nameLower = substance.name.lowercased()
            if nameLower == q {
                exact.append(substance)
            } else if substance.aliases.contains(where: { $0.lowercased() == q }) {
                aliasExact.append(substance)
            } else if nameLower.hasPrefix(q) || substance.aliases.contains(where: { $0.lowercased().hasPrefix(q) }) {
                prefix.append(substance)
            } else if substance.matches(q) {
                contains.append(substance)
            }
        }

        return exact + aliasExact + prefix + contains
    }
}
