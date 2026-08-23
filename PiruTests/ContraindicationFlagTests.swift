import Foundation
import Testing
@testable import Piru

/// The contraindication vocabulary is authored twice — as patterns and labels
/// in `pipeline/build/contraindication_flags.py`, and as cases here. A flag the
/// database carries but Swift does not know renders as an empty row, which is
/// worse than the prose it replaced.
@Suite("Contraindication flags")
@MainActor
struct ContraindicationFlagTests {
    /// Every substance that has any contraindication at all, so the assertions
    /// below run against the whole shipped corpus rather than a sample.
    private var allContraindications: [Contraindication] {
        SubstanceLibrary.all
            .flatMap { SubstanceLibrary.lookup($0.name)?.contraindications ?? [] }
    }

    @Test
    func `Every flag in the database decodes to a case`() {
        let rows = allContraindications
        #expect(!rows.isEmpty, "no contraindications in the bundled database")
        // A row with neither is the pipeline's CHECK constraint having failed.
        let empty = rows.filter { $0.flag == nil && ($0.text?.isEmpty ?? true) }
        #expect(empty.isEmpty, "\(empty.count) contraindication rows carry neither a flag nor text")
    }

    @Test
    func `Every case has a label, and none of them is an instruction`() {
        // The label register: a noun phrase naming the contraindication. An
        // imperative would be the prescribing label's voice, which is the one
        // this vocabulary exists to replace.
        let imperatives = ["avoid", "do not", "consult", "ask your", "should not", "must not"]
        for flag in ContraindicationFlag.allCases {
            let text = String(localized: flag.label)
            #expect(!text.isEmpty, "\(flag.rawValue) has no label")
            for word in imperatives {
                #expect(
                    !text.lowercased().contains(word),
                    "\(flag.rawValue) reads as advice: \(text)",
                )
            }
        }
    }

    @Test
    func `The prose that survives is a name, not a paragraph`() {
        // Label prose either matched a flag or was dropped. What is left with
        // `text` is a condition name or a boxed-warning title, and neither runs
        // long — a paragraph here means the matcher let one through.
        let long = allContraindications.compactMap(\.text).filter { $0.count > 130 }
        #expect(long.isEmpty, "prose survived normalization: \(long.prefix(3))")
    }

    @Test
    func `A flagged row keeps no source sentence`() {
        // The whole point: where a flag matched, the label's wording is gone.
        let both = allContraindications.filter { $0.flag != nil && $0.text != nil }
        #expect(both.isEmpty, "\(both.count) rows carry a flag AND the original prose")
    }
}
