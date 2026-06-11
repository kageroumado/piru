import Foundation
import SwiftData

/// The one place that owns the ``FavoriteSubstance`` insert/delete rules —
/// previously duplicated across the Library browse, category lists, substance
/// detail, and quick-log dock, each with its own copy of the toggle.
///
/// Matching is case-insensitive on the substance name (the `@Attribute(.unique)`
/// key is case-sensitive, so a lowercased comparison is required to avoid
/// near-duplicate rows). New favorites always append at the end of the
/// user-arranged order — see ``FavoriteSubstance/sortOrder`` — so favoriting
/// from *any* surface never displaces the order set in the quick-log Edit
/// sheet. Presentation concerns (haptics, animations, view-local caches) stay
/// with the callers.
@MainActor
enum FavoriteService {
    /// Toggle `name`'s membership in Favorites. Returns `true` when the
    /// substance is now a favorite, `false` when it was just removed.
    @discardableResult
    static func toggle(_ name: String, in context: ModelContext) -> Bool {
        let favorites = fetchAll(in: context)
        let lowered = name.lowercased()
        if let existing = favorites.first(where: { $0.substance.lowercased() == lowered }) {
            context.delete(existing)
            return false
        }
        let nextOrder = (favorites.map(\.sortOrder).max() ?? -1) + 1
        context.insert(FavoriteSubstance(substance: name, sortOrder: nextOrder))
        return true
    }

    private static func fetchAll(in context: ModelContext) -> [FavoriteSubstance] {
        (try? context.fetch(FetchDescriptor<FavoriteSubstance>())) ?? []
    }
}
