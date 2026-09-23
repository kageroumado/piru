import Foundation
import Testing
@testable import Piru

/// The bindings table holds one row per measurement, so a substance measured at one receptor by
/// several assays reaches the engine as several engagements of that receptor. Each must count once:
/// the engine's Gaddum sum is for several ligands at one site, and the same ligand counted N times
/// is N× its real drive (ketamine's seven NMDA rows, pregabalin's two α2δ-1 rows).
@Suite("Tolerance — one contributor per receptor")
@MainActor
struct ToleranceReceptorCollapseTests {
    typealias Cal = ToleranceCalibrationTests

    private func benzo(targets: [PharmacologyParameters.TargetEngagement]) -> PharmacologyParameters {
        PharmacologyParameters(
            molarMassGramsPerMole: 309, vdLPerKg: 1.0, bioavailabilityFraction: 0.9, bioavailabilityConfidence: .high,
            doseScale: 1, doseScaleConfidence: .high, halfLifeMinutes: 690, vdConfidence: .high, referenceDoseMg: 4,
            suppressesSerotoninSynthesis: false, targets: targets,
        )
    }

    private func gaba(_ params: PharmacologyParameters) -> ClassTolerance? {
        let dose = ToleranceStore.SimDose(substance: "Bz", amountMg: 1, timestamp: Cal.now.addingTimeInterval(-6 * 3_600))
        return ToleranceStore.simulate(doses: [dose], params: ["Bz": params], now: Cal.now, weightKg: 70)[.gaba]
    }

    @Test
    func `Two assays of one receptor drive the class like the tighter one alone`() throws {
        let single = try #require(gaba(benzo(targets: [
            .init(target: "GABA-A", action: .positiveAllostericModulator, halfMaxNanomolar: 15, kind: .ki, confidence: .high),
        ])))
        let duplicated = try #require(gaba(benzo(targets: [
            .init(target: "GABA-A", action: .positiveAllostericModulator, halfMaxNanomolar: 15, kind: .ki, confidence: .high),
            .init(target: "GABA-A (rat cortex)", action: .positiveAllostericModulator, halfMaxNanomolar: 40, kind: .ki, confidence: .high),
            .init(target: "GABA-A receptor", action: .positiveAllostericModulator, halfMaxNanomolar: 22, kind: .ki, confidence: .medium),
        ])))
        #expect(abs(duplicated.occupancyNow - single.occupancyNow) < 1e-9)
        #expect(abs(duplicated.sAcute - single.sAcute) < 1e-9)
        #expect(abs(duplicated.representativeOccupancy - single.representativeOccupancy) < 1e-9)
    }

    @Test
    func `Two different receptors in one class still both count`() throws {
        // Distinct bases are distinct sites; the class drive is their competition sum, so it exceeds
        // either alone.
        let one = try #require(gaba(benzo(targets: [
            .init(target: "GABA-A α1", action: .positiveAllostericModulator, halfMaxNanomolar: 15, kind: .ki, confidence: .high, targetBase: "gaba-a-alpha1"),
        ])))
        let two = try #require(gaba(benzo(targets: [
            .init(target: "GABA-A α1", action: .positiveAllostericModulator, halfMaxNanomolar: 15, kind: .ki, confidence: .high, targetBase: "gaba-a-alpha1"),
            .init(target: "GABA-A α5", action: .positiveAllostericModulator, halfMaxNanomolar: 15, kind: .ki, confidence: .high, targetBase: "gaba-a-alpha5"),
        ])))
        #expect(two.occupancyNow > one.occupancyNow)
    }

    @Test
    func `Pregabalin's bundled rows fold to one α2δ-1 and one α2δ-2`() {
        let bases = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: "Pregabalin").targets.map(\.targetBase)
        #expect(Set(bases) == ["alpha-2-delta-1"] || Set(bases) == ["alpha-2-delta-1", "alpha-2-delta-2"])
        #expect(bases.count > Set(bases).count, "the bundled data no longer carries two rows for one receptor; retire this test or find another")
    }
}
