import Foundation
import Testing
@testable import Piru

/// Stage 4b — the tolerance-modulation graph `μ_R(t)`. An NMDA antagonist onboard attenuates opioid
/// tolerance *development*; the edge is concentration/overlap-gated by the modulator's presence curve,
/// threaded into the availability ODE via ``PDModel/stepAvailability(modulation:)``.
/// (`Specs/pharmacology-axis-meta-plan.md`, Stage 4b.)
@Suite("ToleranceModulation")
@MainActor
struct ToleranceModulationTests {
    static let now = Date(timeIntervalSince1970: 1_700_000_000)

    static func dose(_ substance: String, mg: Double, daysAgo: Double) -> DoseEntry {
        DoseEntry(
            substance: substance, amount: mg, unit: "mg", route: .oral,
            timestamp: now.addingTimeInterval(-daysAgo * 86_400),
        )
    }

    static func simulate(_ entries: [DoseEntry]) -> [String: TargetTolerance] {
        ToleranceStore.simulate(entries: entries, now: now, weightKg: 70) {
            SubstanceStore.shared.pharmacologyParameters(forSubstanceName: $0)
        }
    }

    /// Lowest μ-opioid availability across the computed states (the most-tolerant opioid target).
    static func opioidAvailability(_ states: [String: TargetTolerance]) -> Double? {
        states.values.filter { $0.receptorClass == .muOpioid }.map(\.availability).min()
    }

    // MARK: - The seed edge

    @Test
    func `The seed edge is NMDA antagonism attenuating opioid tolerance, and nothing else`() {
        let nmda = ToleranceModulation.edges(forModulatorClass: .nmdaAntagonist)
        #expect(nmda.count == 1)
        #expect(nmda.first?.affectedClass == .muOpioid)
        #expect((nmda.first?.muFactor ?? 1) < 1)
        // No accidental edges on unrelated modulator classes.
        #expect(ToleranceModulation.edges(forModulatorClass: .gaba).isEmpty)
        #expect(ToleranceModulation.edges(forModulatorClass: .adenosine).isEmpty)
        #expect(ToleranceModulation.edges(forModulatorClass: .muOpioid).isEmpty)
    }

    // MARK: - The modulation effect

    @Test
    func `Co-administered NMDA antagonist leaves more opioid availability than opioid alone`() throws {
        var opioidOnly: [DoseEntry] = []
        var withMemantine: [DoseEntry] = []
        for day in stride(from: 7.0, through: 1.0, by: -1.0) {
            opioidOnly.append(Self.dose("Morphine", mg: 30, daysAgo: day))
            withMemantine.append(Self.dose("Morphine", mg: 30, daysAgo: day))
            withMemantine.append(Self.dose("Memantine", mg: 20, daysAgo: day))
        }
        let alone = try #require(Self.opioidAvailability(Self.simulate(opioidOnly)))
        let modulated = try #require(Self.opioidAvailability(Self.simulate(withMemantine)))
        // Memantine attenuates opioid tolerance development → availability stays higher.
        #expect(modulated > alone)
    }

    @Test
    func `An NMDA antagonist with no opioid present changes nothing`() {
        // Memantine alone produces its own NMDA/nicotinic states but no opioid state to modulate.
        let states = Self.simulate([
            Self.dose("Memantine", mg: 20, daysAgo: 2),
            Self.dose("Memantine", mg: 20, daysAgo: 1),
        ])
        #expect(Self.opioidAvailability(states) == nil)
    }
}
