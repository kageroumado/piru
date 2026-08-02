import Foundation
import Testing
@testable import Piru

@Suite("CombinationMetabolite")
struct CombinationMetaboliteTests {
    @Test
    func `Cocaine + ethanol forms cocaethylene`() {
        let formed = CombinationMetabolite.formed(among: ["Cocaine", "Ethanol"])
        #expect(formed.count == 1)
        #expect(formed.first?.id == "cocaethylene")
    }

    @Test
    func `Common alcohol aliases also trigger formation`() {
        #expect(!CombinationMetabolite.formed(among: ["Cocaine", "Alcohol"]).isEmpty)
        #expect(!CombinationMetabolite.formed(among: ["crack", "alcohol"]).isEmpty)
    }

    @Test
    func `Matching is case- and whitespace-insensitive`() {
        #expect(!CombinationMetabolite.formed(among: ["  COCAINE ", "ETHANOL"]).isEmpty)
    }

    @Test
    func `A single precursor alone forms nothing`() {
        #expect(CombinationMetabolite.formed(among: ["Cocaine"]).isEmpty)
        #expect(CombinationMetabolite.formed(among: ["Ethanol"]).isEmpty)
    }

    @Test
    func `Unrelated co-present substances do not trigger a false positive`() {
        #expect(CombinationMetabolite.formed(among: ["Caffeine", "Alcohol"]).isEmpty)
        #expect(CombinationMetabolite.formed(among: ["Cocaine", "Caffeine", "Cannabis"]).isEmpty)
    }

    @Test
    func `Empty input forms nothing`() {
        #expect(CombinationMetabolite.formed(among: []).isEmpty)
    }

    // MARK: - The conditional gate (these two must never read as unconditional)

    @Test
    func `Cocaethylene and ethylphenidate are both flagged conditional`() {
        #expect(CombinationMetabolite.isConditional("cocaethylene"))
        #expect(CombinationMetabolite.isConditional("Ethylphenidate"))
        #expect(CombinationMetabolite.isConditional("  COCAETHYLENE "))
    }

    @Test
    func `Genuinely unconditional metabolites are not gated`() {
        for name in ["norcocaine", "ritalinic acid", "O-desmethyltramadol", "morphine", "psilocin"] {
            #expect(!CombinationMetabolite.isConditional(name), "\(name) must keep its own Also Active card")
        }
    }

    @Test
    func `The conditional set is exactly the two pair-formed species`() {
        // `SubstanceDetailModel.foldActiveMetabolites` — the "Also Active" fold
        // behind both the library card and the dose-entry section — drops every
        // name in this set, so its contents are the whole contract.
        #expect(CombinationMetabolite.conditionalMetaboliteNames == ["cocaethylene", "ethylphenidate"])
    }

    // MARK: - Temporal gate

    private static func onboard(_ name: String, at start: Double, hours: Double) -> CombinationMetabolite.Onboard {
        CombinationMetabolite.Onboard(
            name: name,
            interval: DateInterval(start: Date(timeIntervalSince1970: start * 3_600), duration: hours * 3_600),
        )
    }

    @Test
    func `Overlapping windows form the pair metabolite`() {
        let cocaine = Self.onboard("Cocaine", at: 0, hours: 2)
        let alcohol = Self.onboard("Alcohol", at: 1, hours: 4)
        let formed = CombinationMetabolite.formed(overlapping: cocaine, with: [alcohol])
        #expect(formed.map(\.id) == ["cocaethylene"])
    }

    @Test
    func `A peer that has already cleared forms nothing`() {
        let alcohol = Self.onboard("Alcohol", at: 0, hours: 3)
        let cocaine = Self.onboard("Cocaine", at: 9, hours: 2)
        #expect(CombinationMetabolite.formed(overlapping: cocaine, with: [alcohol]).isEmpty)
    }

    @Test
    func `Methylphenidate brands overlapping alcohol form ethylphenidate`() {
        let concerta = Self.onboard("Concerta", at: 0, hours: 12)
        let beer = Self.onboard("Ethanol", at: 6, hours: 3)
        #expect(CombinationMetabolite.formed(overlapping: concerta, with: [beer]).map(\.id) == ["ethylphenidate"])
    }

    @Test
    func `A bystander dose in the same session claims nothing`() {
        // Cocaine and alcohol overlap, but this screen is an ibuprofen dose —
        // the note belongs on the precursors' own entries, not on everything
        // logged nearby.
        let ibuprofen = Self.onboard("Ibuprofen", at: 0, hours: 6)
        let peers = [Self.onboard("Cocaine", at: 1, hours: 2), Self.onboard("Alcohol", at: 1, hours: 4)]
        #expect(CombinationMetabolite.formed(overlapping: ibuprofen, with: peers).isEmpty)
    }

    @Test
    func `A lone dose with no peers forms nothing`() {
        #expect(CombinationMetabolite.formed(overlapping: Self.onboard("Cocaine", at: 0, hours: 2), with: []).isEmpty)
    }

    @Test
    func `Touching windows count as co-present`() {
        // A dose taken exactly as the previous one clears still meets it; the
        // transesterification gate is presence, not a gap threshold.
        let alcohol = Self.onboard("Alcohol", at: 0, hours: 3)
        let cocaine = Self.onboard("Cocaine", at: 3, hours: 2)
        #expect(!CombinationMetabolite.formed(overlapping: cocaine, with: [alcohol]).isEmpty)
    }
}
