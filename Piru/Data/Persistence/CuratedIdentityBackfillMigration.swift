import Foundation
import os
import SwiftData

private let logger = Logger(subsystem: "dev.yumeji.piru", category: "CuratedIdentityBackfill")

/// The once-only backfill that gives the **curated** rows — quick-log chips,
/// favorites, and daily-med items — the same PSID identity every logged
/// ``DoseEntry`` already carries (``PSIDBackfillMigration``), so recents/
/// favorites/daily key on substance identity rather than a bare name
/// (`Specs/psid-identity-consumption.md` D.2.3).
///
/// Without it, a pre-PSID `QuickLogDose` (`substanceUID == nil`, keyed by
/// `"methylphenidate"`) and a freshly logged one (keyed by the family uid) would
/// render as **two** cards for the same drug. Resolving the old row's stored name
/// to its uid makes them one. For a daily item saved under a brand ("Concerta"),
/// it also recovers the release form the string named, so the "logged today"
/// check starts matching a dose logged as Methylphenidate XR.
///
/// Same posture as the dose backfill: **exact** resolution only (a typo stays
/// name-only, never silently the wrong drug), **additive** (the retained
/// `substance` string is never rewritten), **never-drop** (an unresolvable name
/// keeps working via that string), and **idempotent/data-driven** — a row is a
/// candidate iff its `substanceUID` is still nil, so a re-run finds nothing and a
/// restore re-arms it. No store snapshot: unlike dose history these are derived
/// convenience rows, and every write is additive, so there is nothing to lose.
@MainActor
enum CuratedIdentityBackfillMigration {
    /// Field kill-switch: when `true`, the backfill is skipped entirely.
    static let disabledKey = "psid.curatedBackfill.v1.disabled"

    /// Run unless disabled. Cheap and safe every launch — a migrated store finds
    /// nothing pending and returns after three counts.
    static func runIfNeeded(container: ModelContainer, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: disabledKey) else {
            logger.notice("Curated identity backfill skipped (kill-switch set); will re-evaluate next launch.")
            return
        }
        run(context: container.mainContext)
    }

    static func run(context: ModelContext) {
        let resolved = backfillQuickLogDoses(context)
            + backfillFavorites(context)
            + backfillDailyItems(context)
        guard resolved > 0 else { return }
        do {
            try context.save()
            logger.notice("Curated identity backfill: resolved \(resolved, privacy: .public) row(s).")
        } catch {
            // Additive-only; the unsaved changes roll back and the next launch
            // retries (rows are still nil → still pending).
            logger.error("Curated identity backfill: save failed (\(error.localizedDescription, privacy: .public)); will retry next launch.")
        }
    }

    /// Resolve `row.substance` to its PSID identity and stamp it, additively.
    /// Returns whether anything was written. `applyProductName` captures the
    /// literal string as the user's product word when it named a form (a brand or
    /// enantiomer alias, i.e. the stored string differs from the canonical name) —
    /// used for daily items, whose `substance` may be "Concerta"; quick-log/
    /// favorite strings are already canonical, so nothing is captured there.
    private static func resolveIdentity(
        substance: String,
        applyProductName: Bool,
        setUID: (String) -> Void,
        setIsomer: (String?) -> Void,
        setRelease: (String?) -> Void,
        setProduct: (String) -> Void,
    ) -> Bool {
        guard let match = SubstanceLibrary.timelineLookup(substance),
              let uid = match.substanceUID
        else { return false } // never drop — stays name-only via the retained string
        setUID(uid)
        let isomer = SubstanceLibrary.isomer(for: substance)
        let release = SubstanceLibrary.releaseForm(for: substance)
        setIsomer(isomer)
        setRelease(release)
        if applyProductName, isomer != nil || release != nil,
           match.name.caseInsensitiveCompare(substance) != .orderedSame {
            setProduct(substance)
        }
        return true
    }

    private static func backfillQuickLogDoses(_ context: ModelContext) -> Int {
        let pending = fetchPending(context, predicate: #Predicate<QuickLogDose> { $0.substanceUID == nil })
        var resolved = 0
        for row in pending {
            if resolveIdentity(
                substance: row.substance, applyProductName: false,
                setUID: { row.substanceUID = $0 }, setIsomer: { row.isomer = $0 },
                setRelease: { row.releaseForm = $0 }, setProduct: { row.productName = $0 },
            ) { resolved += 1 }
        }
        return resolved
    }

    private static func backfillFavorites(_ context: ModelContext) -> Int {
        let pending = fetchPending(context, predicate: #Predicate<FavoriteSubstance> { $0.substanceUID == nil })
        var resolved = 0
        for row in pending {
            if resolveIdentity(
                substance: row.substance, applyProductName: false,
                setUID: { row.substanceUID = $0 }, setIsomer: { row.isomer = $0 },
                setRelease: { row.releaseForm = $0 }, setProduct: { row.productName = $0 },
            ) { resolved += 1 }
        }
        return resolved
    }

    private static func backfillDailyItems(_ context: ModelContext) -> Int {
        let pending = fetchPending(context, predicate: #Predicate<DailyDoseItem> { $0.substanceUID == nil })
        var resolved = 0
        for row in pending {
            // Daily items may be saved under a brand ("Concerta"), so capture that
            // as the product word when it named a form.
            if resolveIdentity(
                substance: row.substance, applyProductName: true,
                setUID: { row.substanceUID = $0 }, setIsomer: { row.isomer = $0 },
                setRelease: { row.releaseForm = $0 }, setProduct: { row.productName = $0 },
            ) { resolved += 1 }
        }
        return resolved
    }

    private static func fetchPending<Model: PersistentModel>(
        _ context: ModelContext,
        predicate: Predicate<Model>,
    ) -> [Model] {
        (try? context.fetch(FetchDescriptor<Model>(predicate: predicate))) ?? []
    }
}
