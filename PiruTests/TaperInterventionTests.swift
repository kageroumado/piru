import Foundation
import Testing
@testable import Piru

/// Gates `taper_interventions`. The verdicts and trial arithmetic are not restated here — the
/// pipeline's `test_taper_interventions_*` checks each row against the review it cites. What these
/// gate is the seam: sixteen rows in the database and sixteen sentences in Swift, joined by a slug,
/// where a mismatch drops a row off the screen silently rather than failing.
@Suite("Taper interventions")
@MainActor
struct TaperInterventionTests {
    let interventions: [TaperIntervention]

    init() {
        interventions = SubstanceStore.shared.taperInterventions()
    }

    /// Every row must resolve to a ``TaperIntervention/Kind``, and every kind must have a row. A row
    /// whose slug names no kind is dropped by the resolver; a kind with no row simply never appears.
    /// Both failures are invisible on screen, which is why they are asserted here.
    @Test
    func `Rows and copy cover exactly the same interventions`() {
        #expect(!interventions.isEmpty, "no taper_interventions rows in the bundled DB")
        #expect(Set(interventions.map(\.kind)) == Set(TaperIntervention.Kind.allCases))
        #expect(interventions.count == TaperIntervention.Kind.allCases.count, "duplicate rows")
    }

    /// Both halves of the screen must be populated. The ledger's point is that the interventions
    /// that did nothing are listed as prominently as the ones that worked, so an empty half would be
    /// a different screen making a different claim.
    @Test
    func `Both verdicts have rows`() {
        for verdict in [TaperIntervention.Verdict.supported, .notSupported] {
            #expect(
                interventions.contains { $0.verdict == verdict },
                "no rows with verdict \(verdict.rawValue)",
            )
        }
    }

    /// The evidence line is composed from the row's own columns, so a row that carries a count must
    /// render one and a row that carries none must render no number. This is what stops the line and
    /// the columns drifting apart the way two hand-written literals would.
    @Test
    func `Evidence lines carry the row's own numbers`() {
        for intervention in interventions {
            let detail = intervention.detail.map { String(localized: $0) }
            if let sampleSize = intervention.sampleSize {
                #expect(
                    detail?.contains("\(sampleSize)") == true,
                    "\(intervention.id): n = \(sampleSize) is not in \(detail ?? "no detail")",
                )
            }
            guard let detail, let trialCount = intervention.trialCount else { continue }
            // Pregabalin's line states its trial's n, not a count of trials.
            if intervention.sampleSize == nil {
                #expect(
                    detail.contains("\(trialCount)"),
                    "\(intervention.id): \(trialCount) trials is not in \(detail)",
                )
            }
        }
    }

    /// A count stated in the prose must be the count in the column. These two rows spell their trial
    /// count inside the finding itself, so the sentence and the row are a genuine fork; the others
    /// render the number straight out of the column and cannot disagree.
    @Test
    func `Findings that count their own trials agree with the column`() {
        let counted: [TaperIntervention.Kind: Int] = [.buspirone: 4, .melatonin: 3]
        for (kind, spelled) in counted {
            let row = interventions.first { $0.kind == kind }
            #expect(
                row?.trialCount == spelled,
                "\(kind.rawValue) finding says \(spelled) trials, row says \(row?.trialCount.map(String.init) ?? "none")",
            )
        }
        // Melatonin's finding names each trial's n; the count must match how many it names.
        let melatonin = String(localized: TaperIntervention.Kind.melatonin.finding)
        #expect(melatonin.components(separatedBy: "n = ").count - 1 == 3)
    }

    /// A row that rests on one controlled trial cannot also claim to summarize several, except where
    /// the count names the controlled trial itself. Pregabalin is the one such row (1 RCT plus an
    /// open study) and propranolol the other (one study, one n).
    @Test
    func `A sample size and a trial count together mean one trial`() {
        for intervention in interventions where intervention.sampleSize != nil {
            guard let trialCount = intervention.trialCount else { continue }
            #expect(trialCount == 1, "\(intervention.id) states n = \(intervention.sampleSize ?? 0) for \(trialCount) trials")
        }
    }
}
