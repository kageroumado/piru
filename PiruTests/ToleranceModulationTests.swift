import Foundation
import Testing
@testable import Piru

/// Stage 4b — the tolerance-modulation graph `μ(t)`. An NMDA antagonist onboard attenuates opioid
/// tolerance *development*; the edge is concentration/overlap-gated by the modulator's presence curve,
/// threaded into the **adaptive** right-shift layer as its `drive` (``PDModel/stepShift``).
/// (`Specs/pharmacology-axis-meta-plan.md`, Stage 4b.)
@Suite("ToleranceModulation")
@MainActor
struct ToleranceModulationTests {
    init() async {
        // The edges are installed at index build, so nothing modulates until the
        // store is up — an empty graph would make every test here pass by
        // measuring an effect that is switched off.
        await SubstanceStore.shared.ensureAllLoaded()
    }

    static let now = Date(timeIntervalSince1970: 1_700_000_000)

    static func dose(_ substance: String, mg: Double, daysAgo: Double) -> DoseEntry {
        DoseEntry(
            substance: substance, amount: mg, unit: "mg", route: .oral,
            timestamp: now.addingTimeInterval(-daysAgo * 86_400),
        )
    }

    static func simulate(_ entries: [DoseEntry]) -> [ReceptorClasses.ReceptorClass: ClassTolerance] {
        ToleranceStore.simulate(entries: entries, now: now, weightKg: 70) {
            SubstanceStore.shared.pharmacologyParameters(forSubstanceName: $0)
        }
    }

    /// μ-opioid adaptive ln-shift in the computed states (the opioid class is aggregated now) — the
    /// layer the modulation `μ` drives, so it carries the attenuation effect.
    static func opioidAdaptiveShift(_ states: [ReceptorClasses.ReceptorClass: ClassTolerance]) -> Double? {
        states[.muOpioid]?.sAdaptive
    }

    // MARK: - The seed edge

    @Test
    func `NMDA antagonism attenuates opioid tolerance`() {
        // The cardinality is a row count and belongs to the curated file; what
        // must hold here is the direction — an edge that did not attenuate would
        // be a modulator accelerating tolerance, which nothing has claimed.
        let nmda = ToleranceModulation.edges(forModulatorClass: .nmdaAntagonist)
        let opioid = nmda.first { $0.affectedClass == .muOpioid }
        #expect(opioid != nil, "the NMDA → μ-opioid edge did not load")
        #expect(nmda.allSatisfy { $0.muFactor < 1 }, "an NMDA edge accelerates tolerance")
    }

    @Test
    func `Every modulation edge is a real modulation`() {
        // A factor of 1 reads on every later inspection as a real edge whose
        // magnitude someone forgot to fill in.
        for modulator in ReceptorClasses.ReceptorClass.allCases {
            for edge in ToleranceModulation.edges(forModulatorClass: modulator) {
                #expect(edge.muFactor > 0, "\(modulator) → \(edge.affectedClass) has a non-positive factor")
                #expect(edge.muFactor != 1, "\(modulator) → \(edge.affectedClass) modulates by nothing")
            }
        }
    }

    // MARK: - The modulation effect

    @Test
    func `Co-administered NMDA antagonist builds less opioid tolerance than opioid alone`() throws {
        var opioidOnly: [DoseEntry] = []
        var withMemantine: [DoseEntry] = []
        for day in stride(from: 7.0, through: 1.0, by: -1.0) {
            opioidOnly.append(Self.dose("Morphine", mg: 30, daysAgo: day))
            withMemantine.append(Self.dose("Morphine", mg: 30, daysAgo: day))
            withMemantine.append(Self.dose("Memantine", mg: 20, daysAgo: day))
        }
        let alone = try #require(Self.opioidAdaptiveShift(Self.simulate(opioidOnly)))
        let modulated = try #require(Self.opioidAdaptiveShift(Self.simulate(withMemantine)))
        // Memantine attenuates opioid tolerance development → a smaller adaptive right-shift.
        #expect(modulated < alone)
    }

    @Test
    func `An NMDA antagonist with no opioid present changes nothing`() {
        // Memantine alone produces its own NMDA/nicotinic states but no opioid state to modulate.
        let states = Self.simulate([
            Self.dose("Memantine", mg: 20, daysAgo: 2),
            Self.dose("Memantine", mg: 20, daysAgo: 1),
        ])
        #expect(Self.opioidAdaptiveShift(states) == nil)
    }
}
