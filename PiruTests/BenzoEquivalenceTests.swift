import Testing
@testable import Piru

/// Pure conversion math for the benzo-equivalence converter. The DB loader is
/// exercised by the bundled-database tests; here we pin the arithmetic that turns
/// cited `dose_to_diazepam` rows into diazepam-equivalents and cross-taper doses.
@Suite("BenzoEquivalence")
struct BenzoEquivalenceTests {
    private func benzo(_ name: String, dose: Double?, diazepam: Double?) -> BenzoEquivalence {
        BenzoEquivalence(
            name: name,
            displayName: name,
            equivalent: DiazepamEquivalent(doseMg: dose, equivalentDiazepamMg: diazepam, displayText: nil),
        )
    }

    /// Real bundled values: alprazolam 0.5 ≈ 10, diazepam 10 ≈ 10, lorazepam 1 ≈ 10.
    private var alprazolam: BenzoEquivalence {
        benzo("Alprazolam", dose: 0.5, diazepam: 10)
    }
    private var diazepam: BenzoEquivalence {
        benzo("Diazepam", dose: 10, diazepam: 10)
    }
    private var lorazepam: BenzoEquivalence {
        benzo("Lorazepam", dose: 1, diazepam: 10)
    }

    @Test
    func `diazepamPerMg is diazepam mg per 1 mg of the benzo`() {
        #expect(alprazolam.diazepamPerMg == 20) // 10 / 0.5
        #expect(diazepam.diazepamPerMg == 1) // 10 / 10
        #expect(lorazepam.diazepamPerMg == 10) // 10 / 1
    }

    @Test
    func `Diazepam-equivalent scales linearly with dose`() {
        #expect(alprazolam.diazepamEquivalent(forDoseMg: 1) == 20)
        #expect(alprazolam.diazepamEquivalent(forDoseMg: 2) == 40)
        #expect(diazepam.diazepamEquivalent(forDoseMg: 5) == 5)
    }

    @Test
    func `Cross-taper routes A → diazepam → B`() {
        // 1 mg alprazolam ≈ 20 mg diazepam ≈ 2 mg lorazepam.
        #expect(alprazolam.equivalentDose(forDoseMg: 1, in: lorazepam) == 2)
        // Converting a benzo into itself is identity.
        #expect(lorazepam.equivalentDose(forDoseMg: 3, in: lorazepam) == 3)
        // Into diazepam equals the diazepam-equivalent directly.
        #expect(alprazolam.equivalentDose(forDoseMg: 0.5, in: diazepam) == 10)
    }

    @Test
    func `Non-positive and unparsed inputs yield nil, never a bogus number`() {
        #expect(alprazolam.diazepamEquivalent(forDoseMg: 0) == nil)
        #expect(alprazolam.diazepamEquivalent(forDoseMg: -1) == nil)
        let unparsed = benzo("Mystery", dose: nil, diazepam: nil)
        #expect(unparsed.diazepamPerMg == nil)
        #expect(unparsed.diazepamEquivalent(forDoseMg: 5) == nil)
        #expect(alprazolam.equivalentDose(forDoseMg: 1, in: unparsed) == nil)
        #expect(unparsed.equivalentDose(forDoseMg: 1, in: alprazolam) == nil)
        // A zero diazepam-mg row must not divide-by-zero into ±inf.
        let zero = benzo("Zero", dose: 0, diazepam: 10)
        #expect(zero.diazepamPerMg == nil)
    }
}
