import Foundation
import Testing
@testable import Piru

@Suite("Date comparison")
struct DateComparisonTests {
    private let instant = Date(timeIntervalSinceReferenceDate: 815_000_000)

    @Test
    func `The same instant is both on-or-before and on-or-after itself`() {
        let same = Date(timeIntervalSinceReferenceDate: instant.timeIntervalSinceReferenceDate)
        #expect(instant.isOnOrBefore(same))
        #expect(instant.isOnOrAfter(same))
        #expect(instant <= same)
        #expect(instant >= same)
    }

    @Test
    func `Strict order: the earlier date is only on-or-before, the later only on-or-after`() {
        let later = instant.addingTimeInterval(0.001)
        #expect(instant.isOnOrBefore(later))
        #expect(!instant.isOnOrAfter(later))
        #expect(later.isOnOrAfter(instant))
        #expect(!later.isOnOrBefore(instant))
        #expect(instant <= later)
        #expect(!(instant >= later))
    }

    @Test
    func `A NaN interval compares false both ways, as Foundation's operators do`() {
        let nan = Date(timeIntervalSinceReferenceDate: .nan)
        #expect(!nan.isOnOrBefore(instant))
        #expect(!nan.isOnOrAfter(instant))
    }
}
