import Foundation
import os
import SwiftData

private let logger = Logger(subsystem: "dev.yumeji.piru", category: "EsterIdentityBackfill")

/// The once-only backfill that reclassifies rows logged under an **ester name**
/// ("Estradiol Valerate", "Estradiol Enanthate", …) onto the base substance plus
/// its ester facet — so "Estradiol Valerate" becomes *Estradiol* with
/// ``DoseEntry/saltForm`` `"Valerate"`, exactly as a dose logged through the ester
/// picker records today.
///
/// Before the ester axis existed, the only way to record which ester you injected
/// was to type it into the substance name. Those rows carry the ester in a string
/// the model can't read: they don't feed the Injection Levels tool (which matches
/// on the Estradiol FAMILY uid), and they title as raw text rather than folding to
/// "Estradiol Valerate". Moving the ester onto `saltForm` fixes all three at once —
/// title, tool, and recents identity.
///
/// Same safety protocol as ``PSIDBackfillMigration``:
/// 1. **Backup first** — snapshot the SQLite store once, lazily, right before the
///    first `DoseEntry` mutation (health data), guarded by ``snapshotDoneKey``.
/// 2. **Exact resolution only** — a row is a candidate iff its stored name resolves
///    to a known ester alias (via ``SubstanceStore/saltForm(forNameOrAlias:)``); a
///    plain "Estradiol" or a typo is never touched.
/// 3. **Idempotent, data-driven** — the gate is `saltForm == nil`, so once a row is
///    reclassified it is skipped, and a re-run (or a restore) finds only true
///    candidates. No decoupled "completed" flag.
/// 4. **Kill-switch** (``disabledKey``) skips the run entirely.
///
/// Unlike the other backfills this **rewrites** the `substance` string (from the
/// ester name to the canonical parent), which is why `DoseEntry` gets the store
/// snapshot: the original is otherwise unrecoverable. The derived rows (recents,
/// favorites, daily items) are rebuildable, so they are rewritten without one.
@MainActor
enum EsterIdentityBackfillMigration {
    /// Field kill-switch: when `true`, the backfill is skipped entirely.
    static let disabledKey = "ester.identityBackfill.v1.disabled"
    /// Set once the pre-migration store snapshot has been taken, so we snapshot at
    /// most once per install.
    static let snapshotDoneKey = "ester.identityBackfill.v1.snapshotTaken"

    /// Run unless disabled. Cheap and safe every launch — a store with no
    /// ester-named rows finds nothing pending and returns after a few counts.
    static func runIfNeeded(container: ModelContainer, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: disabledKey) else {
            logger.notice("Ester identity backfill skipped (kill-switch set); will re-evaluate next launch.")
            return
        }
        run(context: container.mainContext, defaults: defaults)
    }

    /// The migration body. `snapshotsStore` is disabled by tests (in-memory store,
    /// no file to snapshot); production always snapshots before the first dose write.
    static func run(context: ModelContext, defaults: UserDefaults = .standard, snapshotsStore: Bool = true) {
        var snapshotted = defaults.bool(forKey: snapshotDoneKey)
        var resolved = 0

        // Dose history first — the only rows worth a snapshot. The snapshot fires
        // lazily inside the loop, right before the first mutation, so a store with
        // no ester-named doses is never snapshotted.
        for entry in fetch(context, #Predicate<DoseEntry> { $0.saltForm == nil }) {
            guard let rewrite = esterRewrite(for: entry.substance) else { continue }
            if snapshotsStore, !snapshotted {
                try? context.save() // flush pending writes into the files first
                StoreRecovery.snapshotStore(reason: "preester")
                defaults.set(true, forKey: snapshotDoneKey)
                snapshotted = true
            }
            entry.saltForm = rewrite.ester
            entry.substanceUID = rewrite.uid
            entry.substance = rewrite.base
            // Snapshot the canonical parent (no ester) — the same anchor a freshly
            // logged ester dose stores; the ester fold is an in-app render concern.
            entry.displayNameSnapshot = DoseTitle.snapshot(canonicalName: rewrite.base, isomer: nil, releaseForm: nil) ?? rewrite.base
            resolved += 1
        }

        // Derived rows: recents, favorites, daily meds. Rebuildable, so no snapshot.
        for row in fetch(context, #Predicate<QuickLogDose> { $0.saltForm == nil }) {
            if let r = esterRewrite(for: row.substance) {
                row.saltForm = r.ester; row.substanceUID = r.uid; row.substance = r.base; resolved += 1
            }
        }
        for row in fetch(context, #Predicate<FavoriteSubstance> { $0.saltForm == nil }) {
            if let r = esterRewrite(for: row.substance) {
                row.saltForm = r.ester; row.substanceUID = r.uid; row.substance = r.base; resolved += 1
            }
        }
        for row in fetch(context, #Predicate<DailyDoseItem> { $0.saltForm == nil }) {
            if let r = esterRewrite(for: row.substance) {
                row.saltForm = r.ester; row.substanceUID = r.uid; row.substance = r.base; resolved += 1
            }
        }

        guard resolved > 0 else { return }
        do {
            try context.save()
            DoseLogService.shared.changed()
            logger.notice("Ester identity backfill: reclassified \(resolved, privacy: .public) row(s).")
        } catch {
            // The snapshot already protects dose history; unsaved changes roll back
            // and the next launch retries (rows still saltForm == nil → still pending).
            logger.error("Ester identity backfill: save failed (\(error.localizedDescription, privacy: .public)); will retry next launch.")
        }
    }

    /// Resolve an ester-named string to `(canonical parent, FAMILY uid, ester label)`,
    /// or `nil` when the name doesn't name a known ester. Exact resolution only — the
    /// name must resolve through the ester alias index, so a plain "Estradiol" or a
    /// typo returns `nil` and stays untouched.
    private static func esterRewrite(for substance: String) -> (base: String, uid: String, ester: String)? {
        let store = SubstanceStore.shared
        guard let ester = store.saltForm(forNameOrAlias: substance),
              let uid = store.substanceUID(forNameOrAlias: substance),
              let base = store.esters(forParentUID: uid).first(where: { $0.label == ester })?.parent
        else { return nil }
        return (base, uid, ester)
    }

    private static func fetch<Model: PersistentModel>(_ context: ModelContext, _ predicate: Predicate<Model>) -> [Model] {
        (try? context.fetch(FetchDescriptor<Model>(predicate: predicate))) ?? []
    }
}
