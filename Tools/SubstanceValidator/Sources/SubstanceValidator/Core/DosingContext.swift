import Foundation

/// Identifies substances where therapeutic and recreational dosing contexts differ
/// significantly, to prevent false-positive critical discrepancies.
enum DosingContext {
    /// Context in which a dose range applies.
    enum Context: String {
        case therapeutic = "Therapeutic"
        case recreational = "Recreational"
        case both = "Both"
    }

    /// Substances known to have large gaps between therapeutic and recreational doses.
    /// The API typically reports therapeutic doses; local data may report recreational.
    /// When this is the case, a large discrepancy is expected and should be downgraded.
    private static let dualContextSubstances: [String: DualContextInfo] = [
        // Antidepressants used recreationally at much higher doses
        "tianeptine": DualContextInfo(
            therapeuticRange: 12.5...37.5,
            recreationalRange: 50...200,
            note: "Therapeutic antidepressant at 12.5mg TID; recreational/abuse at 50-200mg+"
        ),
        // Gabapentinoids
        "gabapentin": DualContextInfo(
            therapeuticRange: 300...3600,
            recreationalRange: 900...5000,
            note: "Therapeutic for neuropathic pain; recreational doses often higher"
        ),
        "pregabalin": DualContextInfo(
            therapeuticRange: 75...600,
            recreationalRange: 300...900,
            note: "Lyrica therapeutic vs recreational use"
        ),
        // Benzodiazepines (therapeutic very low, recreational much higher)
        "clonazolam": DualContextInfo(
            therapeuticRange: 0.125...0.5,
            recreationalRange: 0.25...1.5,
            note: "Ultra-potent benzo; therapeutic sub-mg, recreational higher"
        ),
        "alprazolam": DualContextInfo(
            therapeuticRange: 0.25...4,
            recreationalRange: 1...6,
            note: "Xanax therapeutic vs recreational"
        ),
        // Dissociatives
        "dxm": DualContextInfo(
            therapeuticRange: 10...30,
            recreationalRange: 100...1500,
            note: "Cough suppressant dose vs dissociative 'plateau' doses"
        ),
        "dextromethorphan": DualContextInfo(
            therapeuticRange: 10...30,
            recreationalRange: 100...1500,
            note: "Cough suppressant dose vs dissociative 'plateau' doses"
        ),
        // Opioids with mixed contexts
        "kratom": DualContextInfo(
            therapeuticRange: 1...4,
            recreationalRange: 3...12,
            note: "Low-dose stimulant vs high-dose sedative/opioid effects"
        ),
        "tramadol": DualContextInfo(
            therapeuticRange: 50...400,
            recreationalRange: 150...500,
            note: "Analgesic dose vs recreational; seizure risk above 400mg"
        ),
        // Stimulants with medical use
        "modafinil": DualContextInfo(
            therapeuticRange: 100...200,
            recreationalRange: 100...400,
            note: "Prescription dose vs cognitive enhancement dose"
        ),
        // Antihistamines used recreationally
        "diphenhydramine": DualContextInfo(
            therapeuticRange: 25...50,
            recreationalRange: 200...700,
            note: "Allergy/sleep dose vs deliriant dose"
        ),
        "dph": DualContextInfo(
            therapeuticRange: 25...50,
            recreationalRange: 200...700,
            note: "Allergy/sleep dose vs deliriant dose"
        ),
        // Muscle relaxants
        "baclofen": DualContextInfo(
            therapeuticRange: 5...80,
            recreationalRange: 50...200,
            note: "Muscle relaxant dose vs recreational dose"
        ),
        // GHB/GBL
        "ghb": DualContextInfo(
            therapeuticRange: 2.25...4.5,
            recreationalRange: 1...4,
            note: "Xyrem narcolepsy dose vs recreational; narrow safety margin"
        ),
        // Kanna (different preparations have wildly different potencies)
        "kanna": DualContextInfo(
            therapeuticRange: 25...100,
            recreationalRange: 200...2000,
            note: "Extract strength varies enormously; raw plant vs standardized extract"
        ),
    ]

    struct DualContextInfo {
        let therapeuticRange: ClosedRange<Double>
        let recreationalRange: ClosedRange<Double>
        let note: String
    }

    /// Check if a substance has known dual dosing contexts.
    static func info(for substanceName: String) -> DualContextInfo? {
        let normalized = substanceName.lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return dualContextSubstances[normalized]
    }

    /// Determine if a dose discrepancy is likely due to context differences
    /// rather than genuinely incorrect data.
    static func isContextualDiscrepancy(
        substanceName: String,
        localValue: Double,
        apiValue: Double
    ) -> (isContextual: Bool, note: String?) {
        guard let ctx = info(for: substanceName) else {
            return (false, nil)
        }

        // If one value falls in therapeutic range and the other in recreational,
        // the discrepancy is contextual, not a data error.
        let localInTherapeutic = ctx.therapeuticRange.contains(localValue)
            || localValue <= ctx.therapeuticRange.upperBound * 1.2
        let apiInTherapeutic = ctx.therapeuticRange.contains(apiValue)
            || apiValue <= ctx.therapeuticRange.upperBound * 1.2

        let localInRecreational = ctx.recreationalRange.contains(localValue)
            || localValue >= ctx.recreationalRange.lowerBound * 0.8
        let apiInRecreational = ctx.recreationalRange.contains(apiValue)
            || apiValue >= ctx.recreationalRange.lowerBound * 0.8

        if (localInRecreational && apiInTherapeutic) || (localInTherapeutic && apiInRecreational) {
            return (true, ctx.note)
        }

        return (false, nil)
    }
}
