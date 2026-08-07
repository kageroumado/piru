import Foundation
import Testing
@testable import Piru

/// Pins the §F.3 CYP2D6 metabolizer-status half-life multiplier. The factors are coarse and
/// low-confidence, so what matters is the direction and rough magnitude: a poor metabolizer's
/// CYP2D6-major clearance substrate lingers longer, an ultra-rapid metabolizer's clears faster, and
/// an unset/extensive status changes nothing.
@Suite("CYP2D6 half-life multiplier")
struct CYP2D6MultiplierTests {
    @Test
    func `Poor and intermediate metabolizers lengthen exposure`() {
        #expect(SubstanceStore.cyp2d6HalfLifeMultiplier(.poor) == 1.5)
        #expect(SubstanceStore.cyp2d6HalfLifeMultiplier(.intermediate) == 1.2)
    }

    @Test
    func `Ultra-rapid metabolizers shorten exposure`() {
        #expect(SubstanceStore.cyp2d6HalfLifeMultiplier(.ultraRapid) < 1)
        #expect(SubstanceStore.cyp2d6HalfLifeMultiplier(.ultraRapid) == 0.65)
    }

    @Test
    func `Unset or extensive status is a no-op`() {
        #expect(SubstanceStore.cyp2d6HalfLifeMultiplier(.unknown) == 1)
        #expect(SubstanceStore.cyp2d6HalfLifeMultiplier(.extensive) == 1)
    }
}
