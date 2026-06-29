import Foundation
import SwiftData

/// Persisted snapshot of the user's **tolerance state for one mechanism class**, derived by replaying
/// the dose log through `PDModel` (the pharmacology axis — `Specs/pharmacology-axis-meta-plan.md`,
/// `Specs/tolerance-faithful-model.md`).
///
/// The authoritative value is *derived*: `ToleranceStore` recomputes the three right-shift layers by
/// replaying the dose log (deterministic, like `ActiveSubstanceCalculator`). This row is the cached
/// result of that replay, so the UI and the widget can read the current tolerance without
/// re-integrating the whole history on every view.
///
/// Tolerance is represented as a **dose-response right-shift** `S = exp(sAcute + sAdaptive + sDeep)`,
/// each `s` an ln-shift contribution from one timescale (see `PDModel`). A naïve/rested state is all
/// three at `0` (`S = 1`).
///
/// Fields are deliberately primitive so the model carries no dependency on Piru-only types and
/// compiles into every target that opens the store — including the widget, whose container schema
/// must know every entity present on disk or the open fails. Adding/altering these stored properties
/// is additive (new defaulted doubles), so it migrates via automatic lightweight migration with no
/// migration plan (see the schema-migration policy in `StoreRecovery`); it is also intentionally
/// excluded from the never-delete recovery row count (a cache row must not make an otherwise-empty
/// store look data-bearing — `StoreRecovery.countUserRows` only tallies user-authored entities).
@Model
final class ToleranceState {
    /// Mechanism-class identifier this state is for — a `ReceptorClasses.ReceptorClass` raw value
    /// (e.g. `"muOpioid"`, `"catecholamineStimulant"`). Unique per store (one row per class); the
    /// engine writes/updates by this key. The column name is kept from the per-target era to avoid a
    /// non-additive rename of a disposable cache.
    @Attribute(.unique) var target: String

    /// Acute ln-shift `sAcute ≥ 0` — within-session tachyphylaxis (τ ≈ hours), the redose loop.
    var sAcute: Double

    /// Adaptive ln-shift `sAdaptive ≥ 0` — the baseline shift people mean by "tolerance"
    /// (τ ≈ days–weeks).
    var sAdaptive: Double

    /// Deep ln-shift `sDeep ≥ 0` — entrenched neuroadaptation (τ ≈ months), gated off below an
    /// escalation threshold so therapeutic users never accrue it.
    var sDeep: Double

    /// When this snapshot was last recomputed (the replay's "now").
    var lastUpdated: Date

    init(
        target: String,
        sAcute: Double = 0,
        sAdaptive: Double = 0,
        sDeep: Double = 0,
        lastUpdated: Date = .now,
    ) {
        self.target = target
        self.sAcute = sAcute
        self.sAdaptive = sAdaptive
        self.sDeep = sDeep
        self.lastUpdated = lastUpdated
    }
}
