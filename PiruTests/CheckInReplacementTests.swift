import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import Piru

/// Replacing a session's pending check-ins: whatever order the system finishes
/// the adds in, and however the schedule changed, what is pending afterwards
/// is exactly the newest schedule.
@MainActor
@Suite("CheckInScheduler replaces a session's schedule")
struct CheckInReplacementTests {
    /// A notification center that records what is pending and can hold every
    /// add until released, the way a slow system add leaves a replacement
    /// suspended part-way through.
    @MainActor
    final class RecordingCenter: PendingNotificationCenter {
        var pending: [String: UNNotificationRequest] = [:]
        /// When each pending request's add arrived, which its trigger's
        /// interval counts from.
        private var arrivals: [String: Date] = [:]
        var holdsAdds = false
        private var held: [CheckedContinuation<Void, Never>] = []

        func removePendingRequests(withIdentifiers identifiers: [String]) {
            for identifier in identifiers {
                pending[identifier] = nil
            }
        }

        func add(_ request: UNNotificationRequest) async throws {
            let arrival = Date.now
            if holdsAdds {
                await withCheckedContinuation { held.append($0) }
            }
            pending[request.identifier] = request
            arrivals[request.identifier] = arrival
        }

        /// Lets every held add finish, and stops holding new ones.
        func release() {
            holdsAdds = false
            let waiting = held
            held = []
            for continuation in waiting {
                continuation.resume()
            }
        }

        /// The pending identifiers of one session's check-ins.
        func identifiers(of session: Session) -> Set<String> {
            Set(pending.keys.filter { $0.hasPrefix(NotificationType.checkIn.identifierPrefix + session.id.uuidString) })
        }

        /// When `identifier` fires: its add's arrival plus its trigger's
        /// interval. An absolute date, so a test that reaches its assertion
        /// late on a loaded main actor still compares like with like.
        func fireDate(_ identifier: String) -> Date? {
            guard let arrival = arrivals[identifier],
                  let trigger = pending[identifier]?.trigger as? UNTimeIntervalNotificationTrigger
            else { return nil }
            return arrival.addingTimeInterval(trigger.timeInterval)
        }
    }

    private let defaults: UserDefaults
    private let container: ModelContainer

    init() {
        // Quiet hours and the app-wide switch are read from here, never from
        // the standard defaults another test may be changing.
        defaults = UserDefaults(suiteName: "CheckInReplacementTests.\(UUID().uuidString)")!
        container = try! ModelContainer(
            for: Schema(PiruSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(PiruSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        return ModelContext(container)
    }

    /// A session that began ten minutes ago, so every hourly prompt is ahead.
    private func session(in context: ModelContext) -> Session {
        let session = Session(startDate: .now.addingTimeInterval(-10 * 60))
        context.insert(session)
        return session
    }

    private func runHourly(_ session: Session) {
        session.checkInIntervalMinutes = CheckInScheduler.Cadence.everyHour.storedMinutes
    }

    private func runCustom(_ session: Session, _ minutes: [Int]) {
        session.checkInOffsetMinutes = minutes
        session.checkInIntervalMinutes = CheckInScheduler.Cadence.custom.storedMinutes
    }

    private func identifiers(_ session: Session, _ ordinals: Range<Int>) -> Set<String> {
        Set(ordinals.map { CheckInScheduler.identifier(sessionID: session.id, ordinal: $0) })
    }

    /// `minutes` after the session's anchor.
    private func date(_ minutes: Int, after session: Session) -> Date {
        CheckInScheduler.anchor(for: session).addingTimeInterval(Double(minutes) * 60)
    }

    private func sync(_ session: Session, _ center: RecordingCenter) -> Task<Void, Never> {
        CheckInScheduler.sync(session: session, center: center, defaults: defaults)
    }

    // MARK: - Identifiers

    @Test
    func `Every identifier a session can use is in the check-in grammar, as many as the longest schedule`() {
        let id = UUID()
        let identifiers = CheckInScheduler.identifiers(sessionID: id)
        #expect(CheckInScheduler.maximumPending == CheckInOffsets.maximumCount)
        #expect(identifiers.count == CheckInScheduler.maximumPending)
        #expect(identifiers.first == "piru.notif.checkIn.\(id.uuidString).0")
        #expect(CheckInScheduler.maximumPending >= CheckInScheduler.Cadence.everyHour.fixedOffsetMinutes.count)
    }

    // MARK: - A replacement overtaking one still adding

    @Test
    func `A schedule replaced while its adds are in flight leaves only the new one`() async throws {
        let context = try makeContext()
        let session = session(in: context)
        let center = RecordingCenter()
        center.holdsAdds = true

        runHourly(session)
        let first = sync(session, center)
        runCustom(session, [30, 90])
        let second = sync(session, center)
        center.release()
        await first.value
        await second.value

        #expect(center.identifiers(of: session) == identifiers(session, 0 ..< 2))
        // Ordinal 0 is the new +30 m prompt, not the hourly one the first
        // replacement was adding when it was overtaken.
        let first0 = try #require(center.fireDate(CheckInScheduler.identifier(sessionID: session.id, ordinal: 0)))
        #expect(abs(first0.timeIntervalSince(date(30, after: session))) < 5)
        let first1 = try #require(center.fireDate(CheckInScheduler.identifier(sessionID: session.id, ordinal: 1)))
        #expect(abs(first1.timeIntervalSince(date(90, after: session))) < 5)
    }

    @Test
    func `Turning check-ins off while the schedule is still being added leaves nothing`() async throws {
        let context = try makeContext()
        let session = session(in: context)
        let center = RecordingCenter()
        center.holdsAdds = true

        runHourly(session)
        let first = sync(session, center)
        session.checkInIntervalMinutes = nil
        let second = sync(session, center)
        center.release()
        await first.value
        await second.value

        #expect(center.identifiers(of: session).isEmpty)
    }

    @Test
    func `Muting check-ins app-wide while the schedule is still being added leaves nothing`() async throws {
        let context = try makeContext()
        let session = session(in: context)
        let center = RecordingCenter()
        center.holdsAdds = true

        runHourly(session)
        let first = sync(session, center)
        defaults.set(false, forKey: "notificationTypeEnabled_\(NotificationType.checkIn.rawValue)")
        #expect(!NotificationPreferencesStore.allows(.checkIn, defaults: defaults))
        let second = sync(session, center)
        center.release()
        await first.value
        await second.value

        #expect(center.identifiers(of: session).isEmpty)
    }

    // MARK: - Routes that clear check-ins without a replacement

    /// A configured preferences store reading this suite's defaults, check-ins on.
    private func preferences() -> NotificationPreferencesStore {
        let store = NotificationPreferencesStore()
        store.configure(container: container, defaults: defaults)
        store.setEnabled(.checkIn, true)
        return store
    }

    /// Starts an hourly schedule whose first add is held, runs `clear` — a
    /// route that removes pending check-ins and starts no replacement — with
    /// the system's removal standing in on `center`, then lets the add finish.
    private func clearWhileAdding(_ clear: () -> Void) async throws -> Set<String> {
        let context = try makeContext()
        let session = session(in: context)
        let center = RecordingCenter()
        center.holdsAdds = true
        runHourly(session)
        let replacement = sync(session, center)

        clear()
        center.removePendingRequests(withIdentifiers: Array(center.pending.keys))
        center.release()
        await replacement.value
        return center.identifiers(of: session)
    }

    @Test
    func `Turning check-ins off in Settings stops a schedule still being added`() async throws {
        let store = preferences()
        let left = try await clearWhileAdding { store.setEnabled(.checkIn, false) }
        #expect(left.isEmpty)
    }

    @Test
    func `Pausing every notification stops a check-in schedule still being added`() async throws {
        let store = preferences()
        let left = try await clearWhileAdding { store.setMasterEnabled(false) }
        #expect(left.isEmpty)
    }

    @Test
    func `Cancelling every replacement, as deleting the journal does, leaves nothing behind`() async throws {
        let left = try await clearWhileAdding { CheckInScheduler.cancelAll(defaults: defaults) }
        #expect(left.isEmpty)
    }

    @Test
    func `A schedule asked for after a cancellation is added in full`() async throws {
        let context = try makeContext()
        let session = session(in: context)
        let center = RecordingCenter()
        runHourly(session)

        CheckInScheduler.cancelAll(defaults: defaults)
        await sync(session, center).value

        #expect(!center.identifiers(of: session).isEmpty)
    }

    // MARK: - Replacing a finished schedule

    @Test
    func `A shorter schedule removes the previous one's extra prompts`() async throws {
        let context = try makeContext()
        let session = session(in: context)
        let center = RecordingCenter()

        runHourly(session)
        await sync(session, center).value
        #expect(center.identifiers(of: session) == identifiers(session, 0 ..< 8))

        runCustom(session, [45])
        await sync(session, center).value

        #expect(center.identifiers(of: session) == identifiers(session, 0 ..< 1))
        let only = try #require(center.fireDate(CheckInScheduler.identifier(sessionID: session.id, ordinal: 0)))
        #expect(abs(only.timeIntervalSince(date(45, after: session))) < 5)
    }

    @Test
    func `Prompts a previous launch left pending are removed before anything is added`() async throws {
        let context = try makeContext()
        let session = session(in: context)
        let center = RecordingCenter()
        let stale = CheckInScheduler.identifiers(sessionID: session.id)
        for identifier in stale {
            let content = UNMutableNotificationContent()
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
            center.pending[identifier] = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        }
        center.holdsAdds = true

        runCustom(session, [30])
        let replacement = sync(session, center)

        // Nothing was ahead of it, so the removal happened before sync returned.
        #expect(center.identifiers(of: session).isEmpty)
        center.release()
        await replacement.value
        #expect(center.identifiers(of: session) == identifiers(session, 0 ..< 1))
    }

    @Test
    func `Back-to-back replacements end on the last schedule asked for`() async throws {
        let context = try makeContext()
        let session = session(in: context)
        let center = RecordingCenter()

        runHourly(session)
        let first = sync(session, center)
        runCustom(session, [20, 40, 60, 80])
        let second = sync(session, center)
        runCustom(session, [100, 200, 300])
        let third = sync(session, center)
        await first.value
        await second.value
        await third.value

        #expect(center.identifiers(of: session) == identifiers(session, 0 ..< 3))
        for (ordinal, minutes) in [100, 200, 300].enumerated() {
            let fires = try #require(center.fireDate(CheckInScheduler.identifier(sessionID: session.id, ordinal: ordinal)))
            #expect(abs(fires.timeIntervalSince(date(minutes, after: session))) < 5)
        }
    }

    // MARK: - Independent sessions

    @Test
    func `Replacing one session's schedule leaves another session's alone`() async throws {
        let context = try makeContext()
        let one = session(in: context)
        let other = session(in: context)
        let center = RecordingCenter()
        center.holdsAdds = true

        runHourly(one)
        let first = sync(one, center)
        runCustom(other, [30, 90])
        let second = sync(other, center)
        runCustom(one, [15])
        let third = sync(one, center)
        center.release()
        await first.value
        await second.value
        await third.value

        #expect(center.identifiers(of: one) == identifiers(one, 0 ..< 1))
        #expect(center.identifiers(of: other) == identifiers(other, 0 ..< 2))
    }
}
