import Foundation
import Testing
@testable import Piru

/// Pins the §F.3 CYP2D6 metabolizer-status half-life multiplier. The factors are coarse and
/// low-confidence, so what matters is the direction and rough magnitude: a slow metabolizer's
/// CYP2D6-major clearance substrate lingers longer, a rapid metabolizer's clears faster, and an
/// unset status changes nothing.
@Suite("CYP2D6 half-life multiplier")
struct CYP2D6MultiplierTests {
    @Test
    func `Slow metabolizers lengthen exposure`() {
        #expect(SubstanceStore.cyp2d6HalfLifeMultiplier(.slow) == 1.5)
    }

    @Test
    func `Rapid metabolizers shorten exposure`() {
        #expect(SubstanceStore.cyp2d6HalfLifeMultiplier(.rapid) < 1)
        #expect(SubstanceStore.cyp2d6HalfLifeMultiplier(.rapid) == 0.65)
    }

    @Test
    func `Unset status is a no-op`() {
        #expect(SubstanceStore.cyp2d6HalfLifeMultiplier(.unknown) == 1)
    }

    @Test
    func `Wire values from earlier builds fold into the three statuses`() {
        #expect(CYP2D6Status(wire: "poor") == .slow)
        #expect(CYP2D6Status(wire: "intermediate") == .slow)
        #expect(CYP2D6Status(wire: "ultraRapid") == .rapid)
        #expect(CYP2D6Status(wire: "extensive") == .unknown)
        #expect(CYP2D6Status(wire: "slow") == .slow)
        #expect(CYP2D6Status(wire: "rapid") == .rapid)
    }
}
