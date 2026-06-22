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
}
