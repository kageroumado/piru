import Testing
import Foundation
@testable import Piru

@Suite("DoseIntensity")
struct DoseIntensityTests {

    // MARK: - Helpers

    /// DXM-shaped reference: threshold 75, light 100-200, common 200-400,
    /// strong 400-700, heavy 700.
    private let dxmLike = DoseRange(
        threshold: 75,
        light: 100...200,
        common: 200...400,
        strong: 400...700,
        heavy: 700
    )

    /// Alcohol-shaped reference (PsychonautWiki): threshold 10, heavy 40.
    /// Used for the canonical "17g vs 34g" differentiation case from user feedback.
    private let alcoholLike = DoseRange(
        threshold: 10,
        light: 10...20,
        common: 20...30,
        strong: 30...40,
        heavy: 40
    )

    private func intensity(_ amount: Double, _ range: DoseRange) -> Double {
        ActiveSubstanceState.computeDoseIntensity(amount: amount, doseRange: range)
    }

    // MARK: - The user-requested behaviors (PsychonautWiki visual style)

    @Test("Within substance: intensity scales proportionally with amount")
    func withinSubstanceProportional() {
        // The canonical case from user feedback: 17g alcohol should render at
        // ~half the height of 34g alcohol. Without this the graph looks like
        // every dose is the same size.
        let small = intensity(17, alcoholLike)
        let big   = intensity(34, alcoholLike)
        // 17/40 = 0.425, 34/40 = 0.85. Ratio small/big ≈ 0.5.
        let ratio = small / big
        #expect(ratio >= 0.45 && ratio <= 0.55,
                "17g/34g alcohol height ratio should be ≈0.5, got \(ratio)")
    }

    @Test("Plat-1 DXM (light) renders much shorter than 75g alcohol (overshoot heavy)")
    func crossSubstanceMagnitudeSpread() {
        // twten's example: "plat 1 or 2 DXM is represented as much less than
        // the 75 grams of alcohol, as they provided different amounts of
        // intensity."
        let plat1DXM    = intensity(150, dxmLike)      // 150/700 ≈ 0.21
        let heavyAlcohol = intensity(75, alcoholLike)  // 75/40 clamped to 1.0
        #expect(heavyAlcohol >= 0.95)
        #expect(plat1DXM <= 0.35)
        #expect(heavyAlcohol - plat1DXM >= 0.60)  // 60%+ of graph height apart
    }

    @Test("Heavy-overdose saturates at 1.0")
    func saturation() {
        #expect(intensity(10_000, dxmLike) == 1.0)
        #expect(intensity(200, alcoholLike) == 1.0)  // 5× heavy
    }

    @Test("Monotonic with amount — always")
    func monotonic() {
        let values = [50, 100, 150, 250, 400, 550, 700, 1000].map { intensity(Double($0), dxmLike) }
        for i in 1..<values.count {
            #expect(values[i] >= values[i - 1],
                    "Non-monotonic at index \(i): \(values[i-1]) → \(values[i])")
        }
    }

    // MARK: - Boundaries

    @Test("Floor at 0.05 so tiny doses still show a visible nub")
    func floorAtMinimum() {
        #expect(intensity(0, dxmLike) >= 0.05 - 0.0001)
        #expect(intensity(0, dxmLike) <= 0.05 + 0.0001)
    }

    @Test("Nil dose range returns neutral mid-common, not full height")
    func nilRangeNeutral() {
        let result = ActiveSubstanceState.computeDoseIntensity(amount: 100, doseRange: nil)
        #expect(result >= 0.50)
        #expect(result <= 0.70)
    }

    // MARK: - Partial-data fallbacks

    @Test("Falls back to strong upper when heavy is missing")
    func fallbackToStrong() {
        let noHeavy = DoseRange(common: 200...400, strong: 400...700)  // no heavy
        let mid = intensity(550, noHeavy)
        #expect(mid >= 0.70)  // 550/700 ≈ 0.785
        #expect(mid <= 0.90)
    }

    @Test("Falls back to common × 1.5 when only common is defined")
    func fallbackToCommon() {
        let onlyCommon = DoseRange(common: 10...20)  // reference becomes 30
        let mid = intensity(15, onlyCommon)  // 15/30 = 0.5
        #expect(mid >= 0.45)
        #expect(mid <= 0.55)
    }
}
