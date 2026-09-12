import Foundation
import os
import SwiftData

private let logger = Logger(subsystem: "dev.yumeji.piru", category: "PSIDRepin")

/// The once-only correction that re-pins persisted PSID **families** whose
/// `substances.substance_uid` was changed on 2026-09-12 — 15 substances whose
/// family had been pinned to the wrong structure (see
/// `data/curated/substance-ids.json`).
///
/// A logged ``DoseEntry`` (and every curated row: ``QuickLogDose``,
/// ``FavoriteSubstance``, ``DailyDoseItem``, ``RoutineOccurrence``) stamps its
/// `substanceUID` at log time and by ``PSIDBackfillMigration`` /
/// ``CuratedIdentityBackfillMigration``, and that field is in shipped stores
/// (v2.2-b51 runs the backfill). A row stamped with the OLD family keeps it
/// forever — the name-gated backfills never revisit a resolved row — so without
/// this pass old rows keep the old family while new logs get the new one, and
/// recents/favorites/daily grouping split in two (daily-med credit in
/// ``DoseNotificationManager/itemIdentityMatches`` compares `substanceUID`
/// first, so it breaks too).
///
/// **Single-pass, computed from the original value.** Every row is rewritten
/// once from a snapshot of its current `substanceUID`: `new = map[old] ?? old`.
/// The map is deliberately applied only once and never chained —
/// `CIDMXLOVFPIHDS` is both an OLD key (4-AcO-MET) and a NEW value (4-AcO-MiPT),
/// which a single lookup against the original value resolves correctly but
/// iterative re-application would corrupt.
///
/// Flag-guarded (``didRunKey``) rather than data-driven: the correction is a
/// fixed one-shot over a known set of families, so once applied it must not
/// re-evaluate. Additive to the store's meaning (identity re-pin, not deletion)
/// and idempotent — a second launch sees the flag and returns.
@MainActor
enum PSIDRepinMigration {
    /// Set once the re-pin has been applied, so it runs at most once per install.
    static let didRunKey = "psid.repin.20260912.didRun"

    /// OLD family uid → corrected NEW family uid, from the 2026-09-12
    /// `data/curated/substance-ids.json` corrections. `CIDMXLOVFPIHDS` appears
    /// once as an OLD key (4-AcO-MET) and once as a NEW value (4-AcO-MiPT); a
    /// single-pass lookup against each row's original value handles that.
    static let repinMap: [String: String] = [
        "BYIVGHIYNFQIJX": "RAFUPYYDHPFASC", // 1Cp-LSD
        "CIDMXLOVFPIHDS": "OMDKHOOGGJRLLX", // 4-AcO-MET
        "UJOZERYNSXXQRD": "GFVJBFIXZYLVPO", // 4-HO-MCPT
        "AXOJRQLKMVSHHZ": "HJJPJSXJAXAIPN", // Arecoline
        "GYEHYVZVTYSXPS": "SPKSLAUXKHSASF", // Doip
        "NYISTOZKVCMVEL": "FZJVHWISUGFFQV", // Furanylfentanyl
        "GUTXTARXLVFHDK": "LNEPOXFFQSENCJ", // Haloperidol
        "RGPDIGOSVORSAK": "UZHSEJADLWPNLE", // Naloxone
        "HXFAZCCRNXARMH": "SJHUJFHOXYDSJY", // Protonitazene
        "JRPRINGETIYVSV": "SIIICDNNMDMWCI", // RTI-55
        "DEIYFTQMQPDXOT": "BNRNXUUZRGQAQC", // Sildenafil
        "MJRDCJBNRNAXIK": "NYVQQTOGYLBBDQ", // Thiopropamine
        "APNKSKXHMUCNSY": "JICJBGPOMZQUBB", // Tianeptine
        "TWYFGYXQSYOKLK": "JQSHBVHOMNKWFT", // Varenicline
        "7XKAILDRTAUYWE": "CIDMXLOVFPIHDS", // 4-AcO-MiPT
    ]

    /// Apply the re-pin unless it has already run. Cheap on a migrated store —
    /// one `UserDefaults` read and return.
    static func runIfNeeded(container: ModelContainer, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: didRunKey) else { return }
        run(context: container.mainContext, defaults: defaults)
    }

    /// The correction body. `setsFlag` is disabled by tests so a re-run against a
    /// fresh in-memory store isn't blocked by a flag the previous case set.
    static func run(context: ModelContext, defaults: UserDefaults = .standard, setsFlag: Bool = true) {
        let rewritten = remap(DoseEntry.self, \.substanceUID, in: context)
            + remap(QuickLogDose.self, \.substanceUID, in: context)
            + remap(FavoriteSubstance.self, \.substanceUID, in: context)
            + remap(DailyDoseItem.self, \.substanceUID, in: context)
            + remap(RoutineOccurrence.self, \.substanceUID, in: context)

        // Mark done even on a no-op run: there is nothing pending to retry, and
        // the correction targets a fixed, known set of families.
        if setsFlag { defaults.set(true, forKey: didRunKey) }
        guard rewritten > 0 else { return }
        do {
            try context.save()
            DoseLogService.shared.changed()
            logger.notice("PSID re-pin: rewrote \(rewritten, privacy: .public) substanceUID(s) onto corrected families.")
        } catch {
            // The flag is set, so this won't retry; the unsaved changes roll back.
            // Additive identity re-pin, so a failed save leaves the store on the
            // (stale-but-consistent) old families rather than a partial state.
            logger.error("PSID re-pin: save failed (\(error.localizedDescription, privacy: .public)).")
        }
    }

    /// Rewrite every row of `Model` whose `substanceUID` is an OLD family key onto
    /// its corrected value, in a single pass over a fetched snapshot. `new` is
    /// computed from each row's original value, so the map is applied exactly once
    /// per row and never chained. Returns how many rows were rewritten.
    private static func remap<Model: PersistentModel>(
        _: Model.Type,
        _ keyPath: ReferenceWritableKeyPath<Model, String?>,
        in context: ModelContext,
    ) -> Int {
        guard let rows = try? context.fetch(FetchDescriptor<Model>()) else { return 0 }
        var count = 0
        for row in rows {
            guard let old = row[keyPath: keyPath], let new = repinMap[old] else { continue }
            row[keyPath: keyPath] = new
            count += 1
        }
        return count
    }
}
