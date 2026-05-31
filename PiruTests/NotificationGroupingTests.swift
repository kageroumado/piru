import Foundation
import Testing
@testable import Piru

@Suite("Notification Grouping")
struct NotificationGroupingTests {
    // MARK: - sessionIdentifier

    @Test
    func `Same time produces same session ID`() {
        let time = Date.now
        let id1 = RampDownScheduler.sessionIdentifier(for: time)
        let id2 = RampDownScheduler.sessionIdentifier(for: time)
        #expect(id1 == id2)
    }

    @Test
    func `Doses 1 hour apart produce same session ID`() throws {
        let noon = try #require(Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now))
        let oneHourLater = noon.addingTimeInterval(3_600)
        let id1 = RampDownScheduler.sessionIdentifier(for: noon)
        let id2 = RampDownScheduler.sessionIdentifier(for: oneHourLater)
        #expect(id1 == id2)
    }

    @Test
    func `Doses in different 6-hour windows produce different IDs`() throws {
        let earlyMorning = try #require(Calendar.current.date(bySettingHour: 2, minute: 0, second: 0, of: .now))
        let evening = try #require(Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: .now))
        let id1 = RampDownScheduler.sessionIdentifier(for: earlyMorning)
        let id2 = RampDownScheduler.sessionIdentifier(for: evening)
        #expect(id1 != id2)
    }

    @Test
    func `Session ID format is deterministic`() {
        let id = RampDownScheduler.sessionIdentifier(for: .now)
        #expect(id.hasPrefix("session_"))
    }

    @Test
    func `Different days produce different session IDs`() throws {
        let today = try #require(Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now))
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: today))
        let id1 = RampDownScheduler.sessionIdentifier(for: today)
        let id2 = RampDownScheduler.sessionIdentifier(for: tomorrow)
        #expect(id1 != id2)
    }
}
