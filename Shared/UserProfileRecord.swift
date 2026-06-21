import Foundation
import SwiftData

/// Single-row SwiftData record holding user *profile / physiology* state.
///
/// Lives alongside the other user-data models so all user-authored state shares one store (and one
/// backup/recovery path) instead of a separate database. Fields are deliberately primitive (String
/// raw values, `Double?`) so this model carries no dependency on Piru-only types and compiles into
/// every target that opens the store — including the widget, whose container schema must know every
/// entity present on disk or the open fails. The typed enum mapping (disclosure tier, weight source)
/// lives in ``UserProfileStore``.
///
/// Adding this entity is purely additive, so it migrates via automatic lightweight migration with no
/// migration plan (see the schema-migration policy in `StoreRecovery`). It is intentionally excluded
/// from the never-delete recovery row count — a lone profile row must not make an otherwise-empty
/// store look data-bearing.
@Model
final class UserProfileRecord {
    /// Disclosure-tier wire value (mirrors `UserProfile.rawValue`; "harm-reduction" is the default).
    var disclosureTierRaw: String

    /// Body weight in kg, or `nil` when the user hasn't provided one (→ population default).
    var bodyWeightKg: Double?

    /// Weight-source wire value (mirrors `UserProfileStore.WeightSource.rawValue`).
    var weightSourceRaw: String

    init(
        disclosureTierRaw: String = "harm-reduction",
        bodyWeightKg: Double? = nil,
        weightSourceRaw: String = "estimated",
    ) {
        self.disclosureTierRaw = disclosureTierRaw
        self.bodyWeightKg = bodyWeightKg
        self.weightSourceRaw = weightSourceRaw
    }
}
