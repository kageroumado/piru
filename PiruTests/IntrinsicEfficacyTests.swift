import Foundation
import Testing
@testable import Piru

/// The tolerance engine's partial-agonist discount (Stage 5c), now `intrinsic_efficacy` in the
/// bundled DB rather than a Swift literal.
///
/// The values are not restated here — the DB row is the cited one, and a test repeating it is a
/// second copy of the data wearing a test's clothes. What is gated is the shape the table has to
/// keep for the discount to mean anything, and the two withdrawals that must not quietly return.
@Suite("IntrinsicEfficacy")
@MainActor
struct IntrinsicEfficacyTests {
    private func efficacy(_ name: String) async -> Double {
        await SubstanceStore.shared.ensureAllLoaded()
        return SubstanceStore.shared.pharmacologyParameters(forSubstanceName: name).intrinsicEfficacy
    }

    @Test
    func `A partial agonist resolves below a full one`() async {
        let buprenorphine = await efficacy("Buprenorphine")
        #expect(buprenorphine > 0 && buprenorphine < 1, "buprenorphine reads \(buprenorphine)")
        // Morphine has no row, so it takes the full-agonist default. That default is the thing the
        // discount is measured against, so if it ever stops being 1.0 every row here changes meaning.
        #expect(await efficacy("Morphine") == 1)
    }

    @Test
    func `7-hydroxymitragynine does not outrank buprenorphine`() async {
        // The Swift table this replaced had 7-OH at 0.6 above buprenorphine at 0.5. The only assay
        // built to read intrinsic efficacy puts them level — Bhowmik 2021 calls 7-OH's efficacy
        // "comparable to that of buprenorphine" — so the old ordering was an artifact of mixing
        // amplified and unamplified assays. Gate the correction, not the number.
        let sevenOH = await efficacy("7-Hydroxymitragynine")
        let buprenorphine = await efficacy("Buprenorphine")
        #expect(sevenOH > 0 && sevenOH <= buprenorphine, "7-OH \(sevenOH) vs buprenorphine \(buprenorphine)")
    }

    @Test
    func `The withdrawn substances take the full-agonist default`() async {
        // Both were withdrawn on sourcing, for different reasons, and both must stay withdrawn.
        //
        // Tianeptine's old 0.5 was wrong in DIRECTION: every source that measures it under standard
        // conditions calls it a full or supra-efficacious mu agonist, so 1.0 is closer to what is
        // measured than any partial value would be.
        //
        // Mitragynine has a real number (Kruegel 2016, 34%) but from a different assay than the rows
        // that ship, and a large share of its in vivo opioid action is its metabolites' — a
        // parent-compound scalar is the wrong shape. Re-adding either from a mixed assay is the
        // failure this suite exists to catch.
        #expect(await efficacy("Tianeptine") == 1)
        #expect(await efficacy("Mitragynine") == 1)
    }
}
