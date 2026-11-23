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
            .map { LaunchCacheInputs.ColorPair(substance: $0.substance, tint: $0.tint) }
        return DoseLogIdentity(entryCount: count, newestTimestamp: newestTimestamp, colors: colors)
    }
}
