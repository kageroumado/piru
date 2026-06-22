import Foundation
import Testing
@testable import Piru

/// Stage 5 opioid safety axis — the reset-after-break overdose detector. Fires *only* in the genuine
/// relapse window (real prior tolerance + a break + recovery toward naïve), and stays silent for a
/// naïve first-timer, a still-actively-using person, a non-opioid, and a too-short break.
/// (`Specs/pharmacology-axis-meta-plan.md`, Stage 5.)
@Suite("OpioidResetRisk")
@MainActor
struct OpioidResetRiskTests {
    static let now = Date(timeIntervalSince1970: 1_700_000_000)
    static let opioid = "Oxycodone"

    static func dose(_ substance: String, mg: Double, daysAgo: Double) -> DoseEntry {
        DoseEntry(
            substance: substance, amount: mg, unit: "mg", route: .oral,
            timestamp: now.addingTimeInterval(-daysAgo * 86_400),
        )
    }

    static func risk(_ name: String, _ entries: [DoseEntry]) -> OpioidResetRisk? {
        ToleranceStore.opioidResetRisk(
            forSubstance: name, entries: entries, now: now, weightKg: 70,
        ) { SubstanceStore.shared.pharmacologyParameters(forSubstanceName: $0) }
    }

    /// A using period: `days` consecutive daily doses ending `endDaysAgo` before now.
    static func dailyUse(mg: Double, days: Int, endingDaysAgo: Double) -> [DoseEntry] {
        (0 ..< days).map { dose(opioid, mg: mg, daysAgo: endingDaysAgo + Double($0)) }
    }

    // MARK: - The relapse window (fires)

    @Test
    func `Tolerant, then a break, then resuming fires the reset warning`() throws {
        // ~6 weeks of daily oxycodone ending 21 days ago, then a 3-week break, now logging it again.
        let history = Self.dailyUse(mg: 40, days: 42, endingDaysAgo: 21)
        let r = try #require(Self.risk(Self.opioid, history))
        #expect(r.peakAvailability <= ToleranceStore.opioidTolerantThreshold)
        #expect(r.currentAvailability >= ToleranceStore.opioidRecoveredThreshold)
        #expect(r.breakDays >= 20)
        #expect(r.contributors.contains(Self.opioid))
    }

    // MARK: - No false positives

    @Test
    func `A naive first opioid does not fire`() {
        // No prior opioid history — full availability is naïveté, not a reset.
        #expect(Self.risk(Self.opioid, []) == nil)
    }

    @Test
    func `Still actively using does not fire`() {
        // Daily use right up to yesterday — no break, the dose matches their tolerance.
        let history = Self.dailyUse(mg: 40, days: 42, endingDaysAgo: 1)
        #expect(Self.risk(Self.opioid, history) == nil)
    }

    @Test
    func `A non-opioid substance never fires`() {
        // Even with a heavy opioid history + break, logging caffeine is not an opioid reset.
        let history = Self.dailyUse(mg: 40, days: 42, endingDaysAgo: 21)
        #expect(Self.risk("Caffeine", history) == nil)
    }

    @Test
    func `A short break does not fire`() {
        // Tolerant, but only a 2-day gap — too short to count as a break / recover.
        let history = Self.dailyUse(mg: 40, days: 42, endingDaysAgo: 2)
        #expect(Self.risk(Self.opioid, history) == nil)
    }

    @Test
    func `A single light dose long ago does not fire`() {
        // One low dose months back never built tolerance — nothing to reset.
        let history = [Self.dose(Self.opioid, mg: 5, daysAgo: 120)]
        #expect(Self.risk(Self.opioid, history) == nil)
    }
}
