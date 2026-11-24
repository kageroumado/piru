#if DEBUG
    import Foundation
    import Testing
    @testable import Piru

    /// The synthetic heart rate the screenshot tour draws stays in a human range
    /// however many doses a session holds.
    @Suite("DebugVitals")
    struct DebugVitalsTests {
        private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

        @Test
        func `Twenty doses ten minutes apart keep the heart rate human`() throws {
            let doses = (0 ..< 20).map { start.addingTimeInterval(Double($0) * 600) }
            let vitals = DebugVitals.synthetic(doses: doses, start: start, end: start.addingTimeInterval(8 * 3600))
            let resting = vitals.heartRate.filter { !$0.isWorkout }.map(\.bpm)
            #expect(try #require(resting.max()) < 120)
            #expect(try #require(resting.min()) > 45)
            #expect(try #require(vitals.heartRate.map(\.bpm).max()) < 180)
        }

        @Test
        func `One dose raises the rate by a modest step`() {
            let rise = DebugVitals.bpm(drive: 1) - DebugVitals.bpm(drive: 0)
            #expect(rise > 8 && rise < 20)
            #expect(DebugVitals.bpm(drive: 40) <= DebugVitals.restingBpm + DebugVitals.maximumRiseBpm)
        }
    }
#endif
