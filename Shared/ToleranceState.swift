import Foundation
import SwiftData

/// Persisted snapshot of the user's **tolerance state at one receptor target**, shared across every
/// substance that engages that target (the pharmacology axis's per-target availability — Stage 1 of
/// `Specs/pharmacology-axis-meta-plan.md`).
///
/// The authoritative value is *derived*: `ToleranceStore` recomputes availability/acute/load by
/// replaying the dose log through `PDModel` (deterministic, like `ActiveSubstanceCalculator`). This
/// row is the cached result of that replay, so the UI and the widget can read a current tolerance
/// number without re-integrating the whole history on every view.
///
/// Fields are deliberately primitive so the model carries no dependency on Piru-only types and
/// compiles into every target that opens the store — including the widget, whose container schema
/// must know every entity present on disk or the open fails. Adding this entity is purely additive,
/// so it migrates via automatic lightweight migration with no migration plan (see the schema-
/// migration policy in `StoreRecovery`); it is also intentionally excluded from the never-delete
/// recovery row count (a cache row must not make an otherwise-empty store look data-bearing —
/// `StoreRecovery.countUserRows` only tallies user-authored entities).
@Model
final class ToleranceState {
    /// Receptor/transporter identifier this state is for, e.g. `"5-HT2A"`, `"DAT"`, `"MOR"`. Unique
    /// per store (one row per target); the engine writes/updates by this key.
    @Attribute(.unique) var target: String

    /// Slow availability `A_R` ∈ [0, 1] — 1 = naïve/rested, 0 = fully tolerant.
    var availability: Double

    /// Acute (within-session) pool ∈ [0, 1] — the redose-loop / tachyphylaxis axis.
    var acute: Double

    /// Allostatic load — an ordinal cumulative recovery-state indicator, **never** an effect
    /// multiplier (this is what honestly replaces the "stimulant tolerance %").
    var load: Double

    /// When this snapshot was last recomputed (the replay's "now").
    var lastUpdated: Date

    init(
        target: String,
        availability: Double = 1,
        acute: Double = 1,
        load: Double = 0,
        lastUpdated: Date = .now,
    ) {
        self.target = target
        self.availability = availability
        self.acute = acute
        self.load = load
        self.lastUpdated = lastUpdated
    }
}
