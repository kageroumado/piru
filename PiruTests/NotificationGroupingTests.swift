import Testing
import Foundation
@testable import Piru

@Suite("Notification Grouping")
struct NotificationGroupingTests {

    // MARK: - sessionIdentifier

    @Test("Same time produces same session ID")
    func sameTimeSameSession() {
        let time = Date.now
        let id1 = RampDownScheduler.sessionIdentifier(for: time)
        let id2 = RampDownScheduler.sessionIdentifier(for: time)
        #expect(id1 == id2)
    }

    @Test("Doses 1 hour apart produce same session ID")
    func nearDosesSameSession() {
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        let oneHourLater = noon.addingTimeInterval(3600)
        let id1 = RampDownScheduler.sessionIdentifier(for: noon)
        let id2 = RampDownScheduler.sessionIdentifier(for: oneHourLater)
        #expect(id1 == id2)
    }

    @Test("Doses in different 6-hour windows produce different IDs")
    func differentWindowsDifferentSession() {
        let earlyMorning = Calendar.current.date(bySettingHour: 2, minute: 0, second: 0, of: .now)!
        let evening = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: .now)!
        let id1 = RampDownScheduler.sessionIdentifier(for: earlyMorning)
        let id2 = RampDownScheduler.sessionIdentifier(for: evening)
        #expect(id1 != id2)
    }

    @Test("Session ID format is deterministic")
    func sessionIdFormat() {
        let id = RampDownScheduler.sessionIdentifier(for: .now)
        #expect(id.hasPrefix("session_"))
    }

    @Test("Different days produce different session IDs")
    func differentDays() {
        let today = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let id1 = RampDownScheduler.sessionIdentifier(for: today)
        let id2 = RampDownScheduler.sessionIdentifier(for: tomorrow)
        #expect(id1 != id2)
    }
}
