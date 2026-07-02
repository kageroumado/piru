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
/// Tolerance is represented as a **dose-response right-shift**
/// `S = exp(sAcute + sAdaptive + sDeep + sSynthesis)`, each `s` an ln-shift contribution from one
/// timescale (see `PDModel`). A naïve/rested state is all layers at `0` (`S = 1`).
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
    ///
    /// All four `s` layers carry a property-level `= 0` default (a naïve state), not just an init
    /// default: SwiftData's automatic lightweight migration backfills *existing* rows from the
    /// property default, and CoreData rejects an in-place migration that adds a mandatory attribute
    /// with no default ("missing attribute values on mandatory destination attribute"). The init
    /// default alone only covers rows created in code, not the migration of a pre-change store.
    var sAcute: Double = 0

    /// Adaptive ln-shift `sAdaptive ≥ 0` — the baseline shift people mean by "tolerance"
    /// (τ ≈ days–weeks).
    var sAdaptive: Double = 0

    /// Deep ln-shift `sDeep ≥ 0` — entrenched neuroadaptation (τ ≈ months), gated off below an
    /// escalation threshold so therapeutic users never accrue it.
    var sDeep: Double = 0

    /// Synthesis ln-shift `sSynthesis ≥ 0` — the slow serotonin-synthesis pool (τ ≈ weeks) that only
    /// the synthesis-suppressing SERT releasers (MDMA-type entactogens) drive, so they recover on a
    /// weeks clock while the cathinone releasers reset in days (`Specs/tolerance-faithful-model.md`
    /// §3.4). `0` for every class without an active synthesis layer.
    var sSynthesis: Double = 0

    /// Chronicity duty-cycle accumulator `∈ [0, 1]` — the leaky time-averaged occupancy (τ ≈ 21 d) that,
    /// with dose-relative escalation, gates the deep layer (`Specs/tolerance-faithful-model-improvements.md`
    /// §2). Persisted as part of the **slow-layer checkpoint** (§1): together with `sDeep`/`sSynthesis`
    /// and `lastUpdated` (the checkpoint time), it lets the next replay seed the months-scale state the
    /// 90-day window can't hold, instead of re-integrating it from zero each time. Additive defaulted
    /// double ⇒ automatic lightweight migration, no plan.
    var chronicExposure: Double = 0

    /// When this snapshot was last recomputed (the replay's "now") — doubles as the **checkpoint
    /// timestamp** for the slow-layer carry-forward (§1): the slow accumulators above are decayed forward
    /// from here to the next replay's window start before seeding.
    var lastUpdated: Date = Date.distantPast

    init(
        target: String,
        sAcute: Double = 0,
        sAdaptive: Double = 0,
        sDeep: Double = 0,
        sSynthesis: Double = 0,
        chronicExposure: Double = 0,
        lastUpdated: Date = .now,
    ) {
        self.target = target
        self.sAcute = sAcute
        self.sAdaptive = sAdaptive
        self.sDeep = sDeep
        self.sSynthesis = sSynthesis
        self.chronicExposure = chronicExposure
        self.lastUpdated = lastUpdated
    }
}
