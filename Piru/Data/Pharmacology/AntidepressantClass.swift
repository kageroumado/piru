import Foundation

/// One `substances.drug_class` row: the normalized subclass, and whether the classifier that
/// assigned it called the assignment contestable.
///
/// Eleven of them are — bupropion's NDRI label rests on transporter affinities weak enough that the
/// mechanism is still argued over, NaSSA was coined for one drug, and venlafaxine at a low dose
/// behaves like the class it is not filed under. A card that asserts those the way it asserts
/// sertraline's SSRI is overstating what the field agrees on.
struct CuratedDrugClass: Hashable, Sendable {
    let value: String
    let isContested: Bool
}

/// The antidepressant classes, and what actually separates them.
///
/// The acronyms are the most-used and least-explained words in this corner of
/// pharmacology: a reader who has been handed one of these knows the letters and
/// not the difference, and the difference is where the whole side-effect profile
/// comes from. So each case carries one line of mechanism rather than a
/// dictionary expansion alone.
///
/// Resolved from `substances.drug_class`, the curated normalized axis, rather
/// than from the substance's tags. The tags are a union across sources and they
/// disagree with the curated column on exactly the compounds where precision
/// matters: they call atomoxetine an SNRI, maprotiline a TCA, and vortioxetine
/// and vilazodone SSRIs.
///
/// Four curated classes deliberately have no case here — `MELATONERGIC`
/// (agomelatine), `NEUROSTEROID` (brexanolone), `OPIOIDERGIC` (tianeptine) and
/// `ATYPICAL`. This card lists a class *against its family*, and that reads as
/// "these are the alternatives on one dimension". Those four are not points on
/// the monoamine axis, they are departures from it, so listing them beside SSRI
/// would state a comparison that isn't true. Their substances show no class card,
/// which is the state they were already in.
enum AntidepressantClass: String, CaseIterable, Hashable, Sendable {
    case ssri
    case snri
    case nri
    case ndri
    case tca
    case maoi
    case sari
    case nassa
    case sms

    /// The acronym, as everyone writes it.
    var acronym: String {
        switch self {
        case .ssri: "SSRI"
        case .snri: "SNRI"
        case .nri: "NRI"
        case .ndri: "NDRI"
        case .tca: "TCA"
        case .maoi: "MAOI"
        case .sari: "SARI"
        case .nassa: "NaSSA"
        case .sms: "SMS"
        }
    }

    /// What the letters stand for.
    var expansion: LocalizedStringResource {
        switch self {
        case .ssri: "Selective serotonin reuptake inhibitor"
        case .snri: "Serotonin–noradrenaline reuptake inhibitor"
        case .nri: "Noradrenaline reuptake inhibitor"
        case .ndri: "Noradrenaline–dopamine reuptake inhibitor"
        case .tca: "Tricyclic antidepressant"
        case .maoi: "Monoamine oxidase inhibitor"
        case .sari: "Serotonin antagonist and reuptake inhibitor"
        case .nassa: "Noradrenergic and specific serotonergic antidepressant"
        case .sms: "Serotonin modulator and stimulator"
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
        case .nri:
            "Blocks the noradrenaline transporter and leaves the other two. In the prefrontal cortex that same transporter is what clears dopamine, so the effect there is not as purely noradrenergic as the name reads."
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
        case .sms:
            "Blocks serotonin reuptake and acts on several serotonin receptors directly, agonist at some and antagonist at others. The receptor work is what separates it from an SSRI, not the transporter block they share."
        }
    }

    /// The class a curated `substances.drug_class` value names, or nil when the
    /// column holds one this card deliberately does not carry.
    static func resolve(drugClass: CuratedDrugClass?) -> AntidepressantClass? {
        guard let drugClass else { return nil }
        return AntidepressantClass(rawValue: drugClass.value.lowercased())
    }
}
