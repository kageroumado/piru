import Testing
@testable import Piru

@Suite("RegionalSubstanceName")
struct RegionalSubstanceNameTests {
    @Test
    func `US region shows the US adopted name`() {
        #expect(RegionalSubstanceName.resolve(canonicalName: "Acetaminophen", region: "US") == "Acetaminophen")
        #expect(RegionalSubstanceName.resolve(canonicalName: "Salbutamol", region: "US") == "Albuterol")
        #expect(RegionalSubstanceName.resolve(canonicalName: "Epinephrine", region: "US") == "Epinephrine")
    }

    @Test
    func `Non-US region shows the international name`() {
        #expect(RegionalSubstanceName.resolve(canonicalName: "Acetaminophen", region: "GB") == "Paracetamol")
        #expect(RegionalSubstanceName.resolve(canonicalName: "Salbutamol", region: "GB") == "Salbutamol")
        #expect(RegionalSubstanceName.resolve(canonicalName: "Epinephrine", region: "AU") == "Adrenaline")
        #expect(RegionalSubstanceName.resolve(canonicalName: "Norepinephrine", region: "DE") == "Noradrenaline")
    }

    @Test
    func `Resolution is independent of which spelling the DB uses as canonical`() {
        // canonical is the US spelling here (Acetaminophen) …
        #expect(RegionalSubstanceName.resolve(canonicalName: "Acetaminophen", region: "FR") == "Paracetamol")
        // … and the INN spelling here (Salbutamol) — both resolve correctly.
        #expect(RegionalSubstanceName.resolve(canonicalName: "Salbutamol", region: "FR") == "Salbutamol")
    }

    @Test
    func `Lookup is case-insensitive on the canonical name`() {
        #expect(RegionalSubstanceName.resolve(canonicalName: "acetaminophen", region: "GB") == "Paracetamol")
        #expect(RegionalSubstanceName.resolve(canonicalName: "ACETAMINOPHEN", region: "US") == "Acetaminophen")
    }

    @Test
    func `nil region falls back to the US default`() {
        #expect(RegionalSubstanceName.resolve(canonicalName: "Acetaminophen", region: nil) == "Acetaminophen")
    }

    @Test
    func `Substances without a regional variant return nil`() {
        #expect(RegionalSubstanceName.resolve(canonicalName: "Ketamine", region: "GB") == nil)
        #expect(RegionalSubstanceName.resolve(canonicalName: "MDMA", region: "US") == nil)
    }
}
