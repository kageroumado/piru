import Foundation
import SwiftData

/// The one owner of the past-year adherence streak.
///
/// The streak is a year-scale fetch plus a 366-day calendar walk on
/// ``DatabaseActor``. Three surfaces show it (the My Meds card, the Insights
/// overview, the Adherence screen) and every one of them used to run the whole
/// thing on each appearance — a card recycled by a scrolling list re-fetched the
/// year mid-scroll. This holds the result per (dose-log revision, med schedule)
/// and shares one in-flight computation, so the year is walked once per change.
@MainActor
@Observable
final class AdherenceStreakStore {
    static let shared = AdherenceStreakStore()

    /// The streak for the current key, or `nil` before the first computation.
    private(set) var streak: Int?

    @ObservationIgnored private var computedKey: Key?
    @ObservationIgnored private var inFlight: (key: Key, task: Task<Int, Never>)?

    private init() {}

    /// What the streak depends on: every committed dose-log change bumps the
    /// revision; the schedule half covers a med being added, retired, or
    /// rescheduled without a dose being logged.
    private struct Key: Equatable {
        let revision: Int
        let schedule: Int
    }

    /// The streak for the store as of now — a cache hit when neither the dose
    /// log nor the schedule changed since the last computation, otherwise one
    /// shared computation. An empty schedule is a streak of 0 without a fetch.
    func currentStreak(items: [DailyDoseItem], container: ModelContainer) async -> Int {
        guard !items.isEmpty else {
            streak = 0
            return 0
        }
        let key = Key(revision: DoseLogService.shared.revision, schedule: Self.scheduleSignature(items))
        if let streak, computedKey == key { return streak }
        if let inFlight, inFlight.key == key { return await inFlight.task.value }

        let task = Task { await AdherenceStreakFetcher.currentStreak(container: container) }
        inFlight = (key, task)
        let value = await task.value
        // A newer key may have superseded this run while it was awaited; only
        // the run that is still current publishes.
        if inFlight?.key == key {
            inFlight = nil
            streak = value
            computedKey = key
        }
        return value
    }

    private static func scheduleSignature(_ items: [DailyDoseItem]) -> Int {
        var hasher = Hasher()
        for item in items {
            hasher.combine(item.persistentModelID)
            hasher.combine(item.substance)
            hasher.combine(item.route)
            hasher.combine(item.isAsNeeded)
            hasher.combine(item.startDate)
            hasher.combine(item.frequency)
            hasher.combine(item.frequencyDays)
            hasher.combine(item.reminderTimesMinutes.count)
        }
        return hasher.finalize()
    }
}
