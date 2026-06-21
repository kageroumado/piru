import Foundation
import Testing
@testable import Piru

/// Pure-core tests for the combined-depression reducer — synthetic contributors, no DB. Mirrors the
/// `PDModel` unit style: the math is exercised in isolation from the resolution layer.
@Suite("CombinedDepression reducer")
struct CombinedDepressionReducerTests {
    static let start = Date(timeIntervalSince1970: 1_700_000_000)

    static func contributor(
        _ mechanism: DepressantMechanism,
        engagement: [Double],
        doseWeight: Double = 1,
        confidence: ConfidenceTier = .high,
        modeled: Bool = true,
    ) -> DepressantContributor {
        DepressantContributor(
            substance: mechanism.rawValue, mechanism: mechanism, doseWeight: doseWeight,
            confidence: confidence, isModeled: modeled, engagement: engagement,
        )
    }

    @Test
    func `Combined load is the weighted sum of contributors`() throws {
        // muOpioid weight 1.0, gabaergic weight 0.8; both flat at 0.5 engagement.
        let result = try #require(CombinedDepression.reduce(
            curves: [
                Self.contributor(.muOpioid, engagement: [0.5, 0.5]),
                Self.contributor(.gabaergic, engagement: [0.5, 0.5]),
            ],
            dtMinutes: 15, gridStart: Self.start,
        ))
        // 1.0·0.5 + 0.8·0.5 = 0.9
        #expect(abs(result.peakLoad - 0.9) < 1e-9)
        #expect(result.totalCount == 2)
    }

    @Test
    func `Stacking exceeds either contributor alone`() throws {
        let opioidOnly = try #require(CombinedDepression.reduce(
            curves: [Self.contributor(.muOpioid, engagement: [0.6])], dtMinutes: 15, gridStart: Self.start,
        ))
        let stacked = try #require(CombinedDepression.reduce(
            curves: [
                Self.contributor(.muOpioid, engagement: [0.6]),
                Self.contributor(.gabaergic, engagement: [0.8]),
            ], dtMinutes: 15, gridStart: Self.start,
        ))
        #expect(stacked.peakLoad > opioidOnly.peakLoad)
    }

    @Test
    func `Peak is located at the right sample and time`() throws {
        let result = try #require(CombinedDepression.reduce(
            curves: [Self.contributor(.muOpioid, engagement: [0.1, 0.9, 0.3])],
            dtMinutes: 15, gridStart: Self.start,
        ))
        #expect(abs(result.peakLoad - 0.9) < 1e-9)
        #expect(result.peakMinute == 15) // index 1 · 15 min
        #expect(result.peakDate == Self.start.addingTimeInterval(15 * 60))
    }

    @Test
    func `Confidence is the weakest link across contributors`() throws {
        let result = try #require(CombinedDepression.reduce(
            curves: [
                Self.contributor(.muOpioid, engagement: [0.6], confidence: .high, modeled: true),
                Self.contributor(.gabaergic, engagement: [0.8], confidence: .low, modeled: false),
            ], dtMinutes: 15, gridStart: Self.start,
        ))
        #expect(result.confidence == .low)
        #expect(result.modeledCount == 1)
        #expect(result.totalCount == 2)
        #expect(!result.isFullyModeled)
    }

    @Test
    func `Bands follow the calibrated thresholds`() {
        #expect(CombinedDepression.band(forLoad: 0.2) == nil)
        #expect(CombinedDepression.band(forLoad: 0.5) == .caution)
        #expect(CombinedDepression.band(forLoad: 0.9) == .unsafe)
        #expect(CombinedDepression.band(forLoad: 1.3) == .dangerous)
    }

    @Test
    func `No contributors yields no result`() {
        #expect(CombinedDepression.reduce(curves: [], dtMinutes: 15, gridStart: Self.start) == nil)
    }
}

/// End-to-end calibration gate — the reducer wired to the *real* substance data through
/// ``CombinedDepression/analyze(entries:now:weightKg:timestepMinutes:)``. Proves the index ranks the
/// already-encoded dangerous pairs (opioid+benzo, opioid+alcohol) into the dangerous band, degrades
/// gracefully to the effect-shape surrogate for substances without occupancy data, and never fires on
/// a non-depressant pair. (`Specs/pharmacology-axis-meta-plan.md`, Stage 3b.)
@Suite("CombinedDepression end-to-end")
@MainActor
struct CombinedDepressionEndToEndTests {
    static let now = Date(timeIntervalSince1970: 1_700_000_000)

    static func dose(_ substance: String, mg: Double, hoursAgo: Double = 0) -> DoseEntry {
        DoseEntry(
            substance: substance, amount: mg, unit: "mg", route: .oral,
            timestamp: now.addingTimeInterval(-hoursAgo * 3_600),
        )
    }

    static func analyze(_ entries: [DoseEntry]) -> CombinedDepressionResult? {
        CombinedDepression.analyze(entries: entries, weightKg: 70)
    }

    // MARK: - Calibration anchors

    @Test
    func `Opioid + benzodiazepine lands in the dangerous band`() throws {
        let result = try #require(Self.analyze([
            Self.dose("Morphine", mg: 30), Self.dose("Diazepam", mg: 10),
        ]))
        #expect(result.band == .dangerous)
        #expect(result.totalCount == 2)
    }

    @Test
    func `Opioid + alcohol lands in the dangerous band`() throws {
        let result = try #require(Self.analyze([
            Self.dose("Morphine", mg: 30), Self.dose("Alcohol", mg: 20_000),
        ]))
        #expect(result.band == .dangerous)
    }

    @Test
    func `A single moderate opioid stays below the dangerous band`() throws {
        let result = try #require(Self.analyze([Self.dose("Morphine", mg: 20)]))
        #expect(result.band != .dangerous)
        #expect(result.totalCount == 1)
    }

    @Test
    func `Stacking a benzo onto an opioid raises the peak load`() throws {
        let opioidOnly = try #require(Self.analyze([Self.dose("Morphine", mg: 30)]))
        let stacked = try #require(Self.analyze([
            Self.dose("Morphine", mg: 30), Self.dose("Diazepam", mg: 10),
        ]))
        #expect(stacked.peakLoad > opioidOnly.peakLoad)
    }

    // MARK: - Graceful degradation

    @Test
    func `A mixed stack uses occupancy for the opioid and the surrogate for the benzo`() throws {
        let result = try #require(Self.analyze([
            Self.dose("Morphine", mg: 30), Self.dose("Diazepam", mg: 10),
        ]))
        // Morphine resolves real MOR occupancy; diazepam ships without a molar mass → surrogate.
        #expect(result.modeledCount == 1)
        #expect(result.totalCount == 2)
        #expect(!result.isFullyModeled)
        #expect(result.confidence <= .low) // weakest link = the surrogate contributor
    }

    @Test
    func `A surrogate-only depressant pair still produces a readout, not a drop`() throws {
        let result = try #require(Self.analyze([
            Self.dose("Diazepam", mg: 10), Self.dose("Alcohol", mg: 20_000),
        ]))
        #expect(result.totalCount == 2)
        #expect(result.modeledCount == 0)
        #expect(result.hasMeaningfulLoad)
    }

    // MARK: - No false positives

    @Test
    func `A non-depressant pair produces no depression index`() {
        // Caffeine (stimulant) + LSD (psychedelic) — neither is an additive CNS/respiratory depressant.
        let result = Self.analyze([
            Self.dose("Caffeine", mg: 100), Self.dose("Lysergic Acid Diethylamide", mg: 0.0001),
        ])
        #expect(result == nil)
    }

    // MARK: - Peak timing

    @Test
    func `Co-administered depressants peak within the first hours`() throws {
        let result = try #require(Self.analyze([
            Self.dose("Morphine", mg: 30), Self.dose("Diazepam", mg: 10),
        ]))
        #expect(result.peakMinute >= 0)
        #expect(result.peakMinute <= 240) // both peak early when taken together
    }
}
