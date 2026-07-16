import Foundation
import SwiftData

/// The one place that owns the ``FavoriteSubstance`` insert/delete rules —
/// previously duplicated across the Library browse, category lists, substance
/// detail, and quick-log dock, each with its own copy of the toggle.
///
/// Matching is on substance **identity** (``FavoriteSubstance/identityKey`` — the
/// PSID family plus form facets, or the lowercased name when unresolved), so a
/// Concerta favorite (Methylphenidate·XR) is distinct from a plain Methylphenidate
/// one, and two casings of one name still collapse. New favorites always append at
/// the end of the user-arranged order — see ``FavoriteSubstance/sortOrder`` — so
/// favoriting from *any* surface never displaces the order set in the quick-log
/// Edit sheet. Presentation concerns (haptics, animations, view-local caches) stay
/// with the callers.
@MainActor
enum FavoriteService {
    /// Toggle a substance's membership in Favorites. Returns `true` when it is now
    /// a favorite, `false` when it was just removed. The Library favorites a plain
    /// family (no facets); a quick-log card passes its form facets + product so the
    /// favorite pins that exact form.
    @discardableResult
    static func toggle(
        substance: String,
        substanceUID: String? = nil,
        isomer: String? = nil,
        releaseForm: String? = nil,
        saltForm: String? = nil,
        productName: String? = nil,
        in context: ModelContext,
    ) -> Bool {
        let favorites = fetchAll(in: context)
        let identity = QuickLogDose.identityKey(
            substanceUID: substanceUID, substance: substance,
            isomer: isomer, releaseForm: releaseForm, saltForm: saltForm,
        )
        if let existing = favorites.first(where: { $0.identityKey == identity }) {
            context.delete(existing)
            return false
        }
        let nextOrder = (favorites.map(\.sortOrder).max() ?? -1) + 1
        context.insert(FavoriteSubstance(
            substance: substance, sortOrder: nextOrder,
            substanceUID: substanceUID, isomer: isomer,
            releaseForm: releaseForm, saltForm: saltForm, productName: productName,
        ))
        return true
    }

    private static func fetchAll(in context: ModelContext) -> [FavoriteSubstance] {
        (try? context.fetch(FetchDescriptor<FavoriteSubstance>())) ?? []
    }
}
