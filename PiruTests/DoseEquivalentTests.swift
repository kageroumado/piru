import Foundation
import Testing
@testable import Piru

/// Turning a plasma concentration into the dose that reaches it.
///
/// The expected values below are checked against what the drug is actually
/// given at, because the point of the number is that it lands somewhere a
/// reader recognizes. Where it does not, the conversion is refused instead.
@Suite("Dose equivalent")
@MainActor
struct DoseEquivalentTests {
    // MARK: - Units

    @Test
    func `Concentration units convert to milligrams per litre`() throws {
        #expect(DoseEquivalent.milligramsPerLitre(640, unit: "ng/mL") == 0.64)
        #expect(DoseEquivalent.milligramsPerLitre(12, unit: "µg/mL") == 12)
        let pico = try #require(DoseEquivalent.milligramsPerLitre(50, unit: "pg/mL"))
        #expect(abs(pico - 50e-6) < 1e-12)
    }

    @Test
    func `Either micro sign works`() {
        // U+00B5 and U+03BC are indistinguishable on screen and the research
        // pass used both.
        #expect(DoseEquivalent.milligramsPerLitre(2, unit: "\u{00b5}g/mL") == 2)
        #expect(DoseEquivalent.milligramsPerLitre(2, unit: "\u{03bc}g/mL") == 2)
    }

    @Test
    func `A unit suffix does not defeat the match`() {
        #expect(DoseEquivalent.milligramsPerLitre(4, unit: "ng/mL psilocin") == 4e-3)
    }

    @Test
    func `A molar concentration is refused`() {
        // Lithium's 0.6 mM needs a molar mass, and needs to know whether the
        // dose is quoted as the element or the carbonate.
        #expect(DoseEquivalent.milligramsPerLitre(0.6, unit: "mM (serum)") == nil)
    }

    // MARK: - Refusals

    @Test
    func `A fatal or post-mortem concentration is never turned into a dose`() {
        #expect(!DoseEquivalent.isConvertible(effect: "fatal blood concentration"))
        #expect(!DoseEquivalent.isConvertible(
            effect: "antemortem whole blood at fatal status epilepticus",
        ))
        #expect(!DoseEquivalent.isConvertible(effect: "post-mortem femoral blood"))
        #expect(DoseEquivalent.isConvertible(effect: "general anesthesia (loss of consciousness)"))
    }

    // MARK: - The relation

    @Test
    func `The estimate lands where the drug is actually dosed`() throws {
        // Ketamine: 640 ng/mL is anesthesia; Vd 2.5 L/kg; 60 kg; IV.
        // Induction is 1-2 mg/kg = 60-120 mg.
        let ketamine = try #require(DoseEquivalent.milligrams(
            concentrationMgPerL: 0.64, vdLitresPerKg: 2.5, bioavailabilityPct: 100, weightKg: 60,
        ))
        #expect(ketamine > 60 && ketamine < 130)

        // Citalopram: 50 ng/mL; Vd 12 L/kg; F 80%; 60 kg. Dosed 20-40 mg.
        let citalopram = try #require(DoseEquivalent.milligrams(
            concentrationMgPerL: 0.05, vdLitresPerKg: 12, bioavailabilityPct: 80, weightKg: 60,
        ))
        #expect(citalopram > 20 && citalopram < 70)

        // Morphine: 16 ng/mL analgesia; Vd 3.5 L/kg; IV. Given 2-10 mg.
        let morphine = try #require(DoseEquivalent.milligrams(
            concentrationMgPerL: 0.016, vdLitresPerKg: 3.5, bioavailabilityPct: 100, weightKg: 60,
        ))
        #expect(morphine > 2 && morphine < 10)
    }

    @Test
    func `Nonsense inputs yield nothing rather than a number`() {
        #expect(DoseEquivalent.milligrams(
            concentrationMgPerL: 0, vdLitresPerKg: 2.5, bioavailabilityPct: 100, weightKg: 60,
        ) == nil)
        #expect(DoseEquivalent.milligrams(
            concentrationMgPerL: 1, vdLitresPerKg: 2.5, bioavailabilityPct: 0, weightKg: 60,
        ) == nil)
        #expect(DoseEquivalent.milligrams(
            concentrationMgPerL: 1, vdLitresPerKg: 0, bioavailabilityPct: 100, weightKg: 60,
        ) == nil)
    }

    @Test
    func `The result is rounded to the precision it carries`() {
        // A Vd quoted to two figures cannot support "483.84 mg".
        #expect(DoseEquivalent.rounded(483.84) == 480)
        #expect(DoseEquivalent.rounded(96.4) == 96)
        #expect(abs(DoseEquivalent.rounded(3.36) - 3.4) < 1e-9)
        #expect(abs(DoseEquivalent.rounded(0.4837) - 0.48) < 1e-9)
    }

    // MARK: - Through the store

    @Test
    func `An intravenous-only drug gets no dose anchor`() {
        // Propofol is IV-only, and the relation understates an induction dose
        // three- to fivefold because the effect precedes distribution.
        let rows = SubstanceStore.shared.concentrationThresholds(forSubstanceName: "Propofol")
        #expect(!rows.isEmpty)
        #expect(rows.allSatisfy { $0.doseEquivalent == nil })
    }

    @Test
    func `A drug with an absorbed route gets one`() throws {
        let rows = SubstanceStore.shared.concentrationThresholds(forSubstanceName: "Citalopram")
        let anchored = try #require(rows.first { $0.doseEquivalent != nil })
        let anchor = try #require(anchored.doseEquivalent)
        #expect(anchor.route != .intravenous)
        #expect(anchor.milligrams > 0)
    }

    @Test
    func `One threshold the model gets wrong disqualifies the whole substance`() {
        // Fentanyl's Vd puts respiratory depression at roughly six times the
        // dose that causes it, so that row is dropped. Leaving its analgesia
        // anchor standing would show a benefit dose while hiding the harm dose
        // beside it, which reads as the safer claim and is the more dangerous
        // one.
        let rows = SubstanceStore.shared.concentrationThresholds(forSubstanceName: "Fentanyl")
        #expect(rows.count >= 2)
        #expect(rows.allSatisfy { $0.doseEquivalent == nil })
    }

    @Test
    func `A sub-milligram anchor reads in micrograms`() throws {
        // LSD's anchor is 0.023 mg, which nobody says.
        let rows = SubstanceStore.shared.concentrationThresholds(forSubstanceName: "LSD")
        let anchor = try #require(rows.compactMap(\.doseEquivalent).first)
        let amount = anchor.displayAmount
        #expect(amount.unit == "µg")
        #expect(amount.value > 15 && amount.value < 40, "LSD's threshold is about 20 µg")
    }

    @Test
    func `Lithium's molar rows get no anchor`() {
        let rows = SubstanceStore.shared.concentrationThresholds(forSubstanceName: "Lithium")
        #expect(!rows.isEmpty)
        #expect(rows.allSatisfy { $0.doseEquivalent == nil })
    }
}
