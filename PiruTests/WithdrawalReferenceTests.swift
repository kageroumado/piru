import Foundation
import Testing
@testable import Piru

/// Pins the population-level withdrawal-onset classifier (§I.ref). The bands themselves are pure
/// reference content; what needs locking is that each user drug lands in the clinically-correct band —
/// especially the curated overrides where a drug's *effective* duration (via active metabolites)
/// outruns its parent half-life.
@Suite("Withdrawal reference classifier")
struct WithdrawalReferenceTests {
    @Test
    func `Classic short-acting benzos → short band`() {
        #expect(WithdrawalActingClass.classify(name: "triazolam", effectiveHalfLifeMinutes: nil) == .short)
        #expect(WithdrawalActingClass.classify(name: "alprazolam", effectiveHalfLifeMinutes: nil) == .short)
        #expect(WithdrawalActingClass.classify(name: "lorazepam", effectiveHalfLifeMinutes: nil) == .short)
    }

    @Test
    func `Intermediate benzos → intermediate band`() {
        #expect(WithdrawalActingClass.classify(name: "temazepam", effectiveHalfLifeMinutes: nil) == .intermediate)
        #expect(WithdrawalActingClass.classify(name: "oxazepam", effectiveHalfLifeMinutes: nil) == .intermediate)
        #expect(WithdrawalActingClass.classify(name: "bromazepam", effectiveHalfLifeMinutes: nil) == .intermediate)
    }

    @Test
    func `Long-acting benzos → long band`() {
        #expect(WithdrawalActingClass.classify(name: "diazepam", effectiveHalfLifeMinutes: nil) == .long)
        // Chlordiazepoxide's ~10 h parent half-life would fall in the short band by the raw threshold;
        // the NAV26 curated floor lifts it to long.
        #expect(WithdrawalActingClass.classify(name: "chlordiazepoxide", effectiveHalfLifeMinutes: nil) == .long)
        #expect(WithdrawalActingClass.classify(name: "clonazepam", effectiveHalfLifeMinutes: nil) == .long)
    }

    @Test
    func `Metabolite-extended half-life drives classification for un-curated drugs (I.full)`() {
        // A benzo not in the NAV26 table: classified purely by its metabolite-extended half-life. A
        // short effective t½ reads short; a long one (a nordazepam-type tail, ~70 h) reads long.
        let name = "__synthetic_prodrug_benzo__"
        #expect(WithdrawalActingClass.classify(name: name, effectiveHalfLifeMinutes: 300) == .short)
        #expect(WithdrawalActingClass.classify(name: name, effectiveHalfLifeMinutes: 4_200) == .long)
        // Metabolite data only lengthens: a short effective half-life never downgrades a curated-long drug.
        #expect(WithdrawalActingClass.classify(name: "diazepam", effectiveHalfLifeMinutes: 60) == .long)
    }

    @Test
    func `Case and whitespace insensitive`() {
        #expect(WithdrawalActingClass.classify(name: "  Diazepam ", effectiveHalfLifeMinutes: nil) == .long)
        #expect(WithdrawalActingClass.classify(name: "ALPRAZOLAM", effectiveHalfLifeMinutes: nil) == .short)
    }

    @Test
    func `Longer-acting drug governs the timing band ordering`() {
        #expect(WithdrawalActingClass.long.rank > WithdrawalActingClass.intermediate.rank)
        #expect(WithdrawalActingClass.intermediate.rank > WithdrawalActingClass.short.rank)
    }
}
