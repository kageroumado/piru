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

    /// Whether the user smokes tobacco regularly — a chronic CYP1A2-inducer profile flag (Stage 4c).
    /// While set, the metabolic-modulation readout notes that 1A2-cleared drugs run lower. Defaulted so
    /// the migration stays additive/lightweight (`false` is correct for every pre-existing row).
    var smokesTobacco: Bool = false

    /// Whether the per-dose "had grapefruit" toggle is shown in the dose logger (off by default — it is
    /// niche, surfaced only on CYP3A4-heavy substrates when enabled). A presentation preference, not a
    /// physiological fact. Defaulted for lightweight migration.
    var grapefruitLoggingEnabled: Bool = false

    /// Whether the user carries an ALDH2 loss-of-function variant ("Asian flush") — self-reported via
    /// the alcohol-flush question. While set, the alcohol vertical surfaces an acetaldehyde-accumulation
    /// readout (the real toxic intermediate that ALDH2 clears slowly in carriers). Off by default;
    /// defaulted so the migration stays additive/lightweight. A genuine physiological flag, not a
    /// presentation preference.
    var aldh2Deficient: Bool = false

    init(
        disclosureTierRaw: String = "harm-reduction",
        bodyWeightKg: Double? = nil,
        weightSourceRaw: String = "estimated",
        smokesTobacco: Bool = false,
        grapefruitLoggingEnabled: Bool = false,
        aldh2Deficient: Bool = false,
    ) {
        self.disclosureTierRaw = disclosureTierRaw
        self.bodyWeightKg = bodyWeightKg
        self.weightSourceRaw = weightSourceRaw
        self.smokesTobacco = smokesTobacco
        self.grapefruitLoggingEnabled = grapefruitLoggingEnabled
        self.aldh2Deficient = aldh2Deficient
    }
}
