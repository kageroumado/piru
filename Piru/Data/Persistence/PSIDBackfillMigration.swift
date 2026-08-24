import Foundation
import os
import SwiftData

private let logger = Logger(subsystem: "dev.yumeji.piru", category: "PSIDBackfill")

/// The once-only backfill that remaps every logged ``DoseEntry`` onto its PSID
/// identity — Stage 0.3 of `Specs/stereoisomer-and-release-form-axes.md`.
///
/// `DoseEntry` has always stored its substance **by name**. This resolves each
/// row's name — via the app's **exact** canonical/alias resolver, *not* the
/// fuzzy search cascade — to the stable, collision-proof
/// ``DoseEntry/substanceUID`` (the PSID FAMILY) and captures a locale-stable
/// ``DoseEntry/displayNameSnapshot``, so the app can key recents/favorites/
/// colors on identity rather than a string. Exact-only resolution is the load-
/// bearing safety property: a typo (`"Adderol"`) or an unknown name never
/// silently maps to the *wrong* drug — it stays name-only.
///
/// **Health data — belt and suspenders** (the migration's safety protocol):
/// 1. **Backup first** — snapshot the SQLite store to a `prepsid` sidecar via
///    ``StoreRecovery`` exactly once, *lazily* right before the first real
///    mutation (and after flushing pending writes), so a store that never needs
///    a change is never snapshotted and the copy reflects the true pre-migration
///    state.
/// 2. **Additive, never destructive** — write `substanceUID` +
///    `displayNameSnapshot`; the original ``DoseEntry/substance`` string is kept
///    on the row. Nothing is deleted, so a bad resolve is recoverable.
/// 3. **Never drop the unresolvable** — a name that doesn't resolve (typo,
///    deleted, exotic custom) stays name-only and fully functional via the
///    retained string; it simply gains no `substanceUID`.
/// 4. **Idempotent, data-driven** — a row is a candidate *iff* its
///    `substanceUID` is still nil. There is **no** "completed" flag decoupled
///    from the store: a re-run just finds nothing pending. This is restore-safe
///    (restoring an older store re-arms the backfill without a flag reset) and
///    **self-healing** — a name that was unresolvable at first run resolves on a
///    later launch once the catalog updates or the user adds the custom.
/// 5. **Kill-switch** (``disabledKey``) skips the run entirely, so it can be
///    turned off in the field and re-enabled later.
///
/// The snapshot happens at most once per install, guarded by ``snapshotDoneKey``
/// — the *snapshot* is the one thing worth a flag (repeating it every launch
/// while stragglers persist would be wasteful); resolution itself needs none.
///
/// **Form facets (Stage A + B):** a form-bearing string resolves to its form too,
/// via ``SubstanceLibrary/isomer(for:)`` / ``SubstanceLibrary/releaseForm(for:)`` —
/// "Focalin" → `isomer = "D"`, "Concerta" → `releaseForm = "XR"`, "Focalin XR" →
/// both — titled from the build's composed form title ("Dexmethylphenidate XR") via
/// ``SubstanceLibrary/formTitle(for:)``. A plain string still resolves to the FAMILY
/// uid with both facets nil. Release is **identity/label only**: no source carries a
/// distinct extended-release dose or duration, so recovering it names the form
/// logged without implying a different ladder or curve.
///
/// Because the candidate gate is `substanceUID == nil`, a row already given a uid by
/// an earlier build keeps its (canonical) title and gains no facets — harmless while
/// Stage 0.3 is unreleased (no store in the field has run this), and new stores
/// resolve uid + both facets in one pass. If any of this ever ships before a further
/// facet lands, that facet needs its own gate rather than reusing this one.
@MainActor
enum PSIDBackfillMigration {
    /// Field kill-switch: when `true`, the backfill is skipped entirely. Clearing
    /// it lets the (data-driven) backfill run on a later launch.
    static let disabledKey = "psid.doseBackfill.v1.disabled"
    /// Set once the pre-migration store snapshot has been taken, so we snapshot at
    /// most once per install even while unresolvable stragglers keep the backfill
    /// nominally "pending".
    static let snapshotDoneKey = "psid.doseBackfill.v1.snapshotTaken"

    /// Run the backfill unless disabled. Cheap and safe to call on every launch —
    /// a fully-migrated store finds nothing pending and returns after one count.
    static func runIfNeeded(container: ModelContainer, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: disabledKey) else {
            logger.notice("PSID backfill skipped (kill-switch set); will re-evaluate next launch.")
            return
        }
        run(context: container.mainContext, defaults: defaults)
    }

    /// The migration body. `snapshotsStore` is disabled by tests (which run on an
    /// in-memory store with no file to snapshot); production always snapshots.
    static func run(context: ModelContext, defaults: UserDefaults = .standard, snapshotsStore: Bool = true) {
        // Cheap gate: only rows without an identity are candidates. Once fully
        // migrated, this count is 0 (or just the true stragglers) and we return
        // without a full fetch — no "completed" flag needed, and restore-safe.
        let pendingPredicate = #Predicate<DoseEntry> { $0.substanceUID == nil }
        let pending: [DoseEntry]
        do {
            guard try context.fetchCount(FetchDescriptor<DoseEntry>(predicate: pendingPredicate)) > 0 else { return }
            pending = try context.fetch(FetchDescriptor<DoseEntry>(predicate: pendingPredicate))
        } catch {
            // Nothing was touched; the next launch retries.
            logger.error("PSID backfill: fetch failed (\(error.localizedDescription, privacy: .public)); will retry next launch.")
            return
        }

        // Additive remap. `lookup` is the overlay-aware, EXACT (batch-
        // cache canonical/alias) resolver — never fuzzy — so a user relabel maps
        // to the underlying library identity and a typo stays name-only.
        var snapshotted = defaults.bool(forKey: snapshotDoneKey)
        var resolved = 0
        for entry in pending {
            guard let match = SubstanceLibrary.lookup(entry.substance),
                  let uid = match.substanceUID
            else { continue } // never drop — stays name-only via `substance`

            // Backup first — lazily, once ever, right before the first mutation.
            if snapshotsStore, !snapshotted {
                try? context.save() // flush other subsystems' pending writes into the files
                StoreRecovery.snapshotStore(reason: "prepsid")
                defaults.set(true, forKey: snapshotDoneKey)
                snapshotted = true
            }

            entry.substanceUID = uid
            // Recover the form facets the logged string named — isomer ("Focalin" →
            // D) and release form ("Concerta" → XR; "Focalin XR" → both) — from the
            // facet-annotated alias table, so a legacy enantiomer/brand log keeps
            // its identity + title instead of collapsing to the plain parent.
            entry.isomer = SubstanceLibrary.isomer(for: entry.substance)
            entry.releaseForm = SubstanceLibrary.releaseForm(for: entry.substance)
            // The build composes every form's title ("Dexmethylphenidate XR"), so we
            // snapshot it rather than re-assembling facets here. Falls back to the
            // **canonical** name — never the region-resolved display title
            // (Acetaminophen vs Paracetamol) — because the snapshot must be a
            // locale-stable anchor; the render layer regionalizes/localizes it.
            entry.displayNameSnapshot = SubstanceLibrary.formTitle(for: entry.substance) ?? match.name
            resolved += 1
        }

        guard resolved > 0 else { return } // pure-straggler pass — nothing to save
        do {
            try context.save()
            DoseLogService.shared.changed()
            logger.notice("PSID backfill: resolved \(resolved, privacy: .public)/\(pending.count, privacy: .public) dose(s); \(pending.count - resolved, privacy: .public) kept name-only.")
        } catch {
            // The snapshot already protects the data; the unsaved changes roll
            // back and the next launch retries (rows are still nil → still pending).
            logger.error("PSID backfill: save failed (\(error.localizedDescription, privacy: .public)); will retry next launch.")
        }
    }
}
