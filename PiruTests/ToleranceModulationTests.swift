import Foundation
import Testing
@testable import Piru

/// Stage 4b — the tolerance-modulation graph `μ(t)`. An edge says that one receptor class, while
/// onboard, scales how fast another builds tolerance; it is concentration/overlap-gated by the
/// modulator's presence curve and threaded into the **adaptive** right-shift layer as its `drive`
/// (``PDModel/stepShift``). (`Specs/pharmacology-axis-meta-plan.md`, Stage 4b.)
///
/// **The graph ships empty.** Its one edge — NMDA antagonism attenuating opioid tolerance — was
/// withdrawn in 2026-08 when sourcing found no human magnitude behind the 0.5, and the strongest
/// positive human trial reported plasma memantine an order of magnitude below the NMDA IC₅₀ and
/// credited an anti-inflammatory mechanism instead. `tolerance-modulation.json`'s `withdrawn` carries
/// the full record.
///
/// So these tests exercise the machinery against a **synthetic** edge rather than a shipped one. That
/// is deliberate: the mechanism is model code and must keep working, and pinning it to whichever row
/// the curated file happens to hold is what let an unsourced number sit here looking validated.
@Suite("ToleranceModulation")
@MainActor
struct ToleranceModulationTests {
    init() async {
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

    /// Runs `body` with one synthetic edge installed, then restores what the store loaded.
    static func withEdge(
        _ modulator: ReceptorClasses.ReceptorClass,
        _ affected: ReceptorClasses.ReceptorClass,
        muFactor: Double,
        _ body: () -> Void,
    ) {
        let installed = Dictionary(
            uniqueKeysWithValues: ReceptorClasses.ReceptorClass.allCases
                .map { ($0, ToleranceModulation.edges(forModulatorClass: $0)) }
                .filter { !$0.1.isEmpty },
        )
        ToleranceModulation.load([modulator: [.init(affectedClass: affected, muFactor: muFactor)]])
        body()
        ToleranceModulation.load(installed)
    }

    // MARK: - What ships

    @Test
    func `Every shipped edge is a real modulation`() {
        // A factor of 1 reads on every later inspection as a real edge whose magnitude someone
        // forgot to fill in.
        for modulator in ReceptorClasses.ReceptorClass.allCases {
            for edge in ToleranceModulation.edges(forModulatorClass: modulator) {
                #expect(edge.muFactor > 0, "\(modulator) → \(edge.affectedClass) has a non-positive factor")
                #expect(edge.muFactor != 1, "\(modulator) → \(edge.affectedClass) modulates by nothing")
            }
        }
    }

    // MARK: - The mechanism

    @Test
    func `An edge attenuates the class it names`() {
        Self.withEdge(.nmdaAntagonist, .muOpioid, muFactor: 0.5) {
            var opioidOnly: [DoseEntry] = []
            var withMemantine: [DoseEntry] = []
            for day in stride(from: 7.0, through: 1.0, by: -1.0) {
                opioidOnly.append(Self.dose("Morphine", mg: 30, daysAgo: day))
                withMemantine.append(Self.dose("Morphine", mg: 30, daysAgo: day))
                withMemantine.append(Self.dose("Memantine", mg: 20, daysAgo: day))
            }
            let alone = Self.opioidAdaptiveShift(Self.simulate(opioidOnly))
            let modulated = Self.opioidAdaptiveShift(Self.simulate(withMemantine))
            #expect(alone != nil && modulated != nil)
            // μ < 1 attenuates development → a smaller adaptive right-shift.
            #expect((modulated ?? 0) < (alone ?? 0))
        }
    }

    @Test
    func `A modulator with none of the affected class present changes nothing`() {
        Self.withEdge(.nmdaAntagonist, .muOpioid, muFactor: 0.5) {
            // Memantine alone produces its own NMDA/nicotinic states but no opioid state to modulate.
            let states = Self.simulate([
                Self.dose("Memantine", mg: 20, daysAgo: 2),
                Self.dose("Memantine", mg: 20, daysAgo: 1),
            ])
            #expect(Self.opioidAdaptiveShift(states) == nil)
        }
    }

    @Test
    func `With the graph as shipped, the opioid shift is the unmodulated one`() throws {
        var entries: [DoseEntry] = []
        for day in stride(from: 7.0, through: 1.0, by: -1.0) {
            entries.append(Self.dose("Morphine", mg: 30, daysAgo: day))
            entries.append(Self.dose("Memantine", mg: 20, daysAgo: day))
        }
        let withNMDA = try #require(Self.opioidAdaptiveShift(Self.simulate(entries)))
        let opioidOnly = try #require(
            Self.opioidAdaptiveShift(Self.simulate(entries.filter { $0.substance == "Morphine" })),
        )
        #expect(withNMDA == opioidOnly)
    }
}
