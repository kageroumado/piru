import Foundation
import Testing
@testable import Piru

/// Sertraline is an SSRI, not a stimulant. Its DAT engagement is a weak off-target of its real
/// mechanism (SERT), and tolerance to a transporter is tolerance to its *functional* effect: the
/// bundled DB now drives DAT occupancy from sertraline's functional DA-uptake IC₅₀ (315 nM, Owens
/// 2001) rather than its binding Kᵢ (~25 nM), which is ~13× tighter. At an antidepressant dose that
/// drops modeled DAT occupancy below the meaningfulness gate, so no stimulant-tolerance card appears —
/// while the drugs that genuinely occupy DAT (cocaine, methylphenidate) still read as stimulants.
@MainActor
@Suite("Tolerance — sertraline is not a stimulant")
struct ToleranceSertralineStimulantTests {
    static let now = Date(timeIntervalSince1970: 1_700_000_000)
    static let weightKg = 70.0

    /// The tolerance classes a single typical dose of `name` drives, via the real bundled pharmacology.
    private func classes(_ name: String, mg: Double) async -> Set<ReceptorClasses.ReceptorClass> {
        await SubstanceStore.shared.ensureAllLoaded()
        let params = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: name)
        let dose = ToleranceStore.SimDose(substance: name, amountMg: mg, timestamp: Self.now.addingTimeInterval(-2 * 3_600))
        return Set(ToleranceStore.simulate(doses: [dose], params: [name: params], now: Self.now, weightKg: Self.weightKg).keys)
    }

    @Test
    func `A usual sertraline dose drives no stimulant class`() async {
        let classes = await classes("Sertraline", mg: 100)
        #expect(!classes.contains(.catecholamineStimulant))
    }

    @Test
    func `Methylphenidate still reads as a stimulant`() async {
        // The nearest analog to the sertraline case — a DAT/NET reuptake inhibitor — must keep its
        // stimulant card: its functional DAT potency (IC₅₀ ~80 nM) genuinely occupies the transporter.
        #expect(await classes("Methylphenidate", mg: 40).contains(.catecholamineStimulant))
    }

    @Test
    func `Cocaine's DAT reuptake is still a stimulant mechanism`() async {
        // Cocaine ships no measured Vd, so it is modeled through the class fallback rather than a direct
        // occupancy card — a pre-existing state the sertraline data fix does not touch. What must hold is
        // that its transporter engagement is still recognized as a stimulant mechanism.
        await SubstanceStore.shared.ensureAllLoaded()
        let params = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: "Cocaine")
        let stimulant = params.targets.filter { ReceptorClasses.classify(target: $0.target, action: $0.action) == .catecholamineStimulant }
        #expect(!stimulant.isEmpty)
    }
}
