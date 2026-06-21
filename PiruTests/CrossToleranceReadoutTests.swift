import Foundation
import Testing
@testable import Piru

/// Stage 4a — the cross-tolerance readout at dose entry. Exercises ``ToleranceStore/crossTolerance``
/// against the real substance data: recent use of a substance lowers the predicted response of a
/// *different* substance sharing the same receptor target, surfaced only for classes whose
/// availability axis is a valid effect multiplier (stimulants are excluded).
/// (`Specs/pharmacology-axis-meta-plan.md`, Stage 4a.)
@Suite("CrossTolerance readout")
@MainActor
struct CrossToleranceReadoutTests {
    static let now = Date(timeIntervalSince1970: 1_700_000_000)

    static func dose(_ substance: String, mg: Double, daysAgo: Double) -> DoseEntry {
        DoseEntry(
            substance: substance, amount: mg, unit: "mg", route: .oral,
            timestamp: now.addingTimeInterval(-daysAgo * 86_400),
        )
    }

    static func compute(_ name: String, _ entries: [DoseEntry], minReduction: Double = 0.1) -> [CrossToleranceReadout] {
        ToleranceStore.crossTolerance(
            forSubstance: name, entries: entries, now: now, weightKg: 70, minReduction: minReduction,
        ) { SubstanceStore.shared.pharmacologyParameters(forSubstanceName: $0) }
    }

    // MARK: - The flagship cross-tolerance case

    @Test
    func `Recent daily LSD lowers predicted psilocybin response`() throws {
        // Three consecutive days of LSD just before "now" suppress 5-HT2A availability.
        let entries = [
            Self.dose("Lysergic Acid Diethylamide", mg: 0.15, daysAgo: 1),
            Self.dose("Lysergic Acid Diethylamide", mg: 0.15, daysAgo: 2),
            Self.dose("Lysergic Acid Diethylamide", mg: 0.15, daysAgo: 3),
        ]
        let readout = try #require(Self.compute("Psilocybin", entries).first)
        #expect(readout.receptorClass == .psychedelic5HT2A)
        #expect(readout.availability < 0.9)
        #expect(readout.contributors.contains("Lysergic Acid Diethylamide"))
    }

    // MARK: - No false positives

    @Test
    func `No history yields no cross-tolerance`() {
        #expect(Self.compute("Psilocybin", []).isEmpty)
    }

    @Test
    func `A long-ago single dose has recovered`() {
        // One micro-dose of LSD ~90 days ago — 5-HT2A (τ ≈ 3.5 d) has long since recovered.
        let entries = [Self.dose("Lysergic Acid Diethylamide", mg: 0.15, daysAgo: 90)]
        #expect(Self.compute("Psilocybin", entries).isEmpty)
    }

    @Test
    func `Stimulants are excluded — their slow axis is load, not a multiplier`() {
        // Daily amphetamine builds allostatic LOAD, but the engine refuses an availability multiplier
        // for stimulants, so no "% of rested" cross-tolerance readout is produced.
        let entries = [
            Self.dose("Amphetamine", mg: 30, daysAgo: 1),
            Self.dose("Amphetamine", mg: 30, daysAgo: 2),
            Self.dose("Amphetamine", mg: 30, daysAgo: 3),
        ]
        #expect(Self.compute("Amphetamine", entries).isEmpty)
    }

    @Test
    func `An unknown substance yields no readout`() {
        #expect(Self.compute("Nonexistent Substance XYZ", [
            Self.dose("Lysergic Acid Diethylamide", mg: 0.15, daysAgo: 1),
        ]).isEmpty)
    }
}
