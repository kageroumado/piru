import Foundation

/// The antidepressant classes, and what actually separates them.
///
/// The acronyms are the most-used and least-explained words in this corner of
/// pharmacology: a reader who has been handed one of these knows the letters and
/// not the difference, and the difference is where the whole side-effect profile
/// comes from. So each case carries one line of mechanism rather than a
/// dictionary expansion alone.
///
/// Resolved from the substance's `tags`, **case-folded** — the table holds both
/// `SSRI` and `ssri`, `SNRI` and `snri`, because the tag arrives from more than
/// one source and `Substance.tags` is a case-sensitive union across them. Folding
/// happens here rather than in a DB rebuild: a casing difference is not worth
/// reshipping the bundle for.
enum AntidepressantClass: String, CaseIterable, Hashable, Sendable {
    case ssri
    case snri
    case ndri
    case tca
    case maoi
    case sari
    case nassa

    /// The acronym, as everyone writes it.
    var acronym: String {
        switch self {
        case .ssri: "SSRI"
        case .snri: "SNRI"
        case .ndri: "NDRI"
        case .tca: "TCA"
        case .maoi: "MAOI"
        case .sari: "SARI"
        case .nassa: "NaSSA"
        }
    }

    /// What the letters stand for.
    var expansion: LocalizedStringResource {
        switch self {
        case .ssri: "Selective serotonin reuptake inhibitor"
        case .snri: "Serotonin–noradrenaline reuptake inhibitor"
        case .ndri: "Noradrenaline–dopamine reuptake inhibitor"
        case .tca: "Tricyclic antidepressant"
        case .maoi: "Monoamine oxidase inhibitor"
        case .sari: "Serotonin antagonist and reuptake inhibitor"
        case .nassa: "Noradrenergic and specific serotonergic antidepressant"
        }
    }

    /// The one line that distinguishes this class from its neighbours —
    /// mechanism first, then the consequence that follows from it.
    var difference: LocalizedStringResource {
        switch self {
        case .ssri:
            "Blocks the serotonin transporter and little else, which is why its effects and its side effects are both mostly serotonergic."
        case .snri:
            "Blocks serotonin and noradrenaline reuptake together. The noradrenaline share grows with dose, so a low dose can behave much like an SSRI."
        case .ndri:
            "Blocks noradrenaline and dopamine reuptake, leaving serotonin alone — the activating end of the family."
        case .tca:
            "Blocks serotonin and noradrenaline reuptake like an SNRI, and also histamine, muscarinic and α₁ receptors. That extra binding is the sedation, the dry mouth, and the narrow margin in overdose."
        case .maoi:
            "Blocks the enzyme that breaks monoamines down, rather than the transporters that recycle them, so all three rise. The tyramine restriction and the long interaction list both follow from that."
        case .sari:
            "Blocks 5-HT₂A while weakly inhibiting serotonin reuptake. The receptor block dominates at low doses, which is why trazodone reached far more people as a sleep drug than as an antidepressant."
        case .nassa:
            "Raises noradrenaline and serotonin release by blocking the α₂ autoreceptors that normally brake it, instead of blocking reuptake. The H₁ block alongside it is the sedation and the appetite."
        }
    }

    /// The classes this substance belongs to, folded from its tags and returned
    /// in the enum's declaration order so two substances never disagree about
    /// the order of the same pair.
    static func resolve(tags: [String]) -> [AntidepressantClass] {
        let folded = Set(tags.map { $0.lowercased() })
        return allCases.filter { folded.contains($0.rawValue) }
    }
}
