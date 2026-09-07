import Foundation
import SwiftData

/// The app's background SwiftData isolation domain — THE home for reads and
/// writes that must not touch the main actor (year-scale snapshot fetches,
/// cache persists). Annotate a function `@DatabaseActor` and it runs here,
/// serialized with every other background database operation, structured and
/// cancellable — the properties the ad-hoc `Task.detached` + throwaway-context
/// pattern it replaces couldn't offer.
///
/// The actor holds no context of its own: each operation makes a fresh
/// `ModelContext` from the `Sendable` container its caller passes, so there is
/// no configure step to order against, no registered-object growth over a long
/// session, and every fetch reads the store's committed state. That last part
/// is the contract to keep in mind: work here sees *saved* data — run it after
/// the commit (the dose-log revision tick and the change streams both fire
/// post-save), never to observe in-flight main-context edits.
@globalActor
actor DatabaseActor {
    static let shared = DatabaseActor()
}

/// Streak computation over the store's committed dose log, entirely off the
/// main actor: the 365-day fetch (narrowed to the fields the snapshot reads),
/// the snapshot mapping, and the calendar walk all run on ``DatabaseActor`` —
/// the callers' old shape fetched and mapped a year of rows on the main actor
/// before detaching just the arithmetic.
enum AdherenceStreakFetcher {
    @DatabaseActor
    static func currentStreak(
        spanningDays: Int = 365,
        endingAt end: Date = .now,
        container: ModelContainer,
    ) -> Int {
        let context = ModelContext(container)

        let cutoff = Calendar.current.date(byAdding: .day, value: -(spanningDays + 1), to: end) ?? .distantPast
        // Whole rows, deliberately: `propertiesToFetch` leaves every object a
        // partial fault that fires on the first access of any property, which
        // cost one fault per dose (3,569 in a launch trace) — more than the
        // columns it saved.
        let entryDescriptor = FetchDescriptor<DoseEntry>(
            predicate: #Predicate { $0.timestamp >= cutoff },
            sortBy: [SortDescriptor(\.timestamp)],
        )
        let entries = (try? context.fetch(entryDescriptor)) ?? []
        let items = (try? context.fetch(FetchDescriptor<DailyDoseItem>())) ?? []

        let entrySnaps = entries.map {
            AdherenceCalculator.EntrySnapshot(
                substance: $0.substance, identityKey: $0.identityKey,
                route: $0.route, timestamp: $0.timestamp,
            )
        }
        let itemSnaps = items.map {
            AdherenceCalculator.DailyItemSnapshot(
                substance: $0.substance, identityKey: $0.identityKey, route: $0.route,
                expectedPerDay: max(1, $0.reminderTimesMinutes.count), isAsNeeded: $0.isAsNeeded,
                startDate: $0.startDate, frequency: $0.frequency, frequencyDays: $0.frequencyDays,
            )
        }
        return AdherenceCalculator.currentStreak(
            spanningDays: spanningDays, endingAt: end, entries: entrySnaps, items: itemSnaps,
        )
    }
}

/// The dose log's identity for a launch cache key — its row count, newest
/// timestamp, and the color assignments — read off the main actor, so a
/// cache lookup never has to materialize the log to know whether it hits.
nonisolated struct DoseLogIdentity: Sendable {
    let entryCount: Int
    let newestTimestamp: Date?
    let colors: [LaunchCacheInputs.ColorPair]

    @DatabaseActor
    static func fetch(container: ModelContainer) -> DoseLogIdentity {
        let context = ModelContext(container)
        let count = (try? context.fetchCount(FetchDescriptor<DoseEntry>())) ?? 0
        var newest = FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        newest.fetchLimit = 1
        let newestTimestamp = (try? context.fetch(newest))?.first?.timestamp
        let colors = ((try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? [])
            .map { LaunchCacheInputs.ColorPair(substance: $0.substance, hex: $0.hexColor) }
        return DoseLogIdentity(entryCount: count, newestTimestamp: newestTimestamp, colors: colors)
    }
}
