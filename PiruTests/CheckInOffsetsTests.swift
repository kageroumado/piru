import Foundation
import Testing
@testable import Piru

/// The rules a custom check-in schedule obeys before it reaches the store.
@Suite("CheckInOffsets")
struct CheckInOffsetsTests {
    @Test
    func `Normalizing sorts, dedupes, and drops what is out of range`() {
        let normalized = CheckInOffsets.normalized([300, 30, 30, 0, -10, 2_000, 90])
        #expect(normalized == [30, 90, 300])
    }

    @Test
    func `A time too soon after the dose is not a time`() {
        #expect(CheckInOffsets.normalized([CheckInOffsets.minimumMinutes - 1]).isEmpty)
        #expect(CheckInOffsets.normalized([CheckInOffsets.minimumMinutes]) == [CheckInOffsets.minimumMinutes])
        #expect(CheckInOffsets.normalized([CheckInOffsets.maximumMinutes + 1]).isEmpty)
    }

    @Test
    func `A session carries no more than the cap, keeping the earliest`() {
        let many = Array(stride(from: 10, through: 10 * 30, by: 10))
        let normalized = CheckInOffsets.normalized(many)
        #expect(normalized.count == CheckInOffsets.maximumCount)
        #expect(normalized.first == 10)
    }

    @Test
    func `Adding is refused for a duplicate, an out-of-range time, or a full list`() {
        #expect(CheckInOffsets.canAdd(60, to: [30]))
        #expect(!CheckInOffsets.canAdd(30, to: [30]))
        #expect(!CheckInOffsets.canAdd(1, to: []))
        #expect(!CheckInOffsets.canAdd(60, to: Array(stride(from: 10, through: 10 * CheckInOffsets.maximumCount, by: 10))))
    }

    @Test
    func `An offset reads as a relative time`() {
        #expect(CheckInOffsets.label(45) == "+45m")
        #expect(CheckInOffsets.label(60) == "+1h")
        #expect(CheckInOffsets.label(150) == "+2h 30m")
    }
}
