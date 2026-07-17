import Foundation
import SwiftData

@Model
final class FavoriteSubstance {
    // The quick-log + reorder views sort by `sortOrder` then `createdAt` (reverse), so a compound
    // index matches that exact ordering. `substance` is already `@Attribute(.unique)` (implicit index).
    #Index<FavoriteSubstance>([\.sortOrder, \.createdAt])

    @Attribute(.unique) var substance: String
    var createdAt: Date
    /// User-defined position in the Favorites section (lower = first). New
    /// favorites append at the end; reorder via the quick-log Edit sheet.
    var sortOrder: Int = 0

    /// The PSID identity this favorite pins, so it matches the recents card of
    /// the same form — a Concerta favorite (Methylphenidate·XR) highlights the
    /// Concerta card, not a plain Methylphenidate one. All `nil` for a favorite
    /// added before PSID (keyed by lowercased name) until the backfill resolves
    /// it. `productName` keeps the user's word for the favorited product.
    /// Additive optionals — a free lightweight migration.
    var substanceUID: String?
    var isomer: String?
    var releaseForm: String?
    var saltForm: String?
    var productName: String?

    init(
        substance: String,
        sortOrder: Int = 0,
        substanceUID: String? = nil,
        isomer: String? = nil,
        releaseForm: String? = nil,
        saltForm: String? = nil,
        productName: String? = nil,
    ) {
        self.substance = substance
        self.createdAt = .now
        self.sortOrder = sortOrder
        self.substanceUID = substanceUID
        self.isomer = isomer
        self.releaseForm = releaseForm
        self.saltForm = saltForm
        self.productName = productName
    }

    /// This favorite's substance-identity key — compared against a recents card's
    /// ``SubstanceCard/id`` to decide membership. See ``QuickLogDose/identityKey``.
    var identityKey: String {
        QuickLogDose.identityKey(
            substanceUID: substanceUID, substance: substance,
            isomer: isomer, releaseForm: releaseForm, saltForm: saltForm,
        )
    }
}

extension [FavoriteSubstance] {
    /// Set of lowercased favorite substance names for O(1) lookup.
    var favoriteSet: Set<String> {
        Set(map { $0.substance.lowercased() })
    }

    func isFavorite(_ name: String) -> Bool {
        contains { $0.substance.lowercased() == name.lowercased() }
    }
}
