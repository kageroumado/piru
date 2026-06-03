import Foundation
import os
import SwiftData

private let recoveryLogger = Logger(subsystem: "dev.yumeji.piru", category: "StoreRecovery")

/// Owns the on-disk SwiftData store: where it lives, recovering orphaned data
/// into it, and backing it up before anything destructive.
///
/// The data-loss this guards against: the App Group store and the widgets
/// shipped together. A widget timeline refresh can open (and thus CREATE an
/// empty) App Group store before the app's first launch — so a naive
/// "migrate only if the destination doesn't exist" check skips the copy and
/// strands the real data in the old app-sandbox store. This component instead
/// decides by *whether the destination actually has data*, and recovers from
/// any data-bearing legacy / backup / quarantined store it can find.
///
/// Invariant: this code NEVER deletes a store. It copies (recovery) and moves
/// aside to timestamped sidecars (backup). The only removals of user data in
/// the app are the explicit Settings → "Delete All" action (which backs up
/// first) and the DEBUG-only demo seeder.
/// Versioned schema baseline. The current models are V1; future schema changes
/// add `PiruSchemaV2` + a `MigrationStage` so SwiftData migrates the store
/// explicitly instead of relying on automatic lightweight migration (which
/// fails — and on failure strands or quarantines data — for any non-additive
/// change like a rename, type change, or new required property).
///
/// Adopting this for stores originally created with a plain `Schema(models)` is
/// seamless: the schema's structural identity is the same, so no migration runs.
/// (Verified by StoreRecoveryTests.)
/// The original five user-data models. Frozen — do not edit; later additions
/// get a new version (see ``PiruSchemaV2``) so the migration path is explicit.
enum PiruSchemaV1: VersionedSchema {
    nonisolated static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }
    nonisolated static var models: [any PersistentModel.Type] {
        [
            DoseEntry.self,
            SubstanceColor.self,
            UserColor.self,
            DailyDoseItem.self,
            FavoriteSubstance.self,
        ]
    }
}

/// Adds ``QuickLogDose`` (the curated quick-log list). Purely additive — a new
/// entity, no changes to existing ones — so the V1→V2 migration is lightweight
/// (automatic) and existing data is untouched.
enum PiruSchemaV2: VersionedSchema {
    nonisolated static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }
    nonisolated static var models: [any PersistentModel.Type] {
        StoreRecovery.models
    }
}

enum PiruMigrationPlan: SchemaMigrationPlan {
    nonisolated static var schemas: [any VersionedSchema.Type] {
        [PiruSchemaV1.self, PiruSchemaV2.self]
    }
    nonisolated static var stages: [MigrationStage] {
        [.lightweight(fromVersion: PiruSchemaV1.self, toVersion: PiruSchemaV2.self)]
    }
}

enum StoreRecovery {
    static let appGroupID = "group.dev.yumeji.piru"
    static let storeName = "default.store"
    /// Sibling files a SwiftData/SQLite store is made of.
    static let storeSuffixes = ["", "-shm", "-wal"]
    private static let migrationFlagKey = "storeRecoveryCompleted.v2"

    /// The user-data models, in one place so counting and recovery agree.
    nonisolated static var models: [any PersistentModel.Type] {
        [
            DoseEntry.self,
            SubstanceColor.self,
            UserColor.self,
            DailyDoseItem.self,
            FavoriteSubstance.self,
            QuickLogDose.self,
        ]
    }

    // MARK: - Locations

    /// Canonical store location (shared App Group container), with the same
    /// fallbacks the app uses so a misconfigured entitlement still launches.
    static func canonicalStoreURL() -> URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent(storeName)
    }

    /// The pre-App-Group location (app sandbox Application Support).
    static func legacyStoreURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent(storeName)
    }

    // MARK: - Recovery (run before opening the main container)

    /// Ensure the canonical store holds the user's data. If it's empty/absent
    /// but a data-bearing legacy / backup / quarantine store exists, recover it
    /// (backing up the empty canonical first). Returns the canonical URL to open.
    @discardableResult
    static func prepareCanonicalStore() -> URL {
        let canonical = canonicalStoreURL()
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard

        // If the canonical store already holds data, we're done — record it so
        // routine launches skip the scan entirely.
        let canonicalCount = userDataCount(at: canonical)
        if canonicalCount > 0 {
            defaults.set(true, forKey: migrationFlagKey)
            return canonical
        }

        // Canonical is empty (0), absent, or unreadable (-1). Only honour the
        // completion flag — i.e. skip the recovery scan — when the canonical
        // store still physically exists (a genuinely-empty store). NEVER skip
        // when it's missing: a prior "completed" run could have been blind
        // (e.g. every open failed) and moved real data aside to a sidecar, and
        // skipping here would strand that data behind the flag forever.
        if defaults.bool(forKey: migrationFlagKey), anyFileExists(at: canonical) {
            return canonical
        }

        // Find the data-bearing store with the most entries among every candidate.
        var best: URL?
        var bestCount = 0
        for candidate in recoveryCandidates(excluding: canonical) {
            let n = userDataCount(at: candidate)
            if n > bestCount {
                best = candidate
                bestCount = n
            }
        }

        if let source = best, bestCount > 0 {
            // Never overwrite: move the current (empty/unreadable) canonical aside.
            if anyFileExists(at: canonical) {
                backUpStore(at: canonical, reason: "empty-before-recovery")
            }
            do {
                try copyStore(from: source, to: canonical)
                recoveryLogger.notice(
                    "Recovered \(bestCount, privacy: .public) entries into the canonical store from \(source.lastPathComponent, privacy: .public)",
                )
            } catch {
                recoveryLogger.error("Store recovery copy failed: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            recoveryLogger.info("No data-bearing store found to recover; canonical stays as-is.")
        }

        defaults.set(true, forKey: migrationFlagKey)
        return canonical
    }

    /// Stores we might recover from: the legacy sandbox store, plus any
    /// timestamped sidecars (quarantined / backed-up / superseded) in either the
    /// canonical or the legacy directory.
    private static func recoveryCandidates(excluding canonical: URL) -> [URL] {
        var out: [URL] = []
        if let legacy = legacyStoreURL(), legacy.path != canonical.path {
            out.append(legacy)
        }
        let dirs = Set([
            canonical.deletingLastPathComponent(),
            legacyStoreURL()?.deletingLastPathComponent(),
        ].compactMap { $0?.path })
        let fm = FileManager.default
        for dirPath in dirs {
            let dir = URL(fileURLWithPath: dirPath)
            guard let entries = try? fm.contentsOfDirectory(atPath: dirPath) else { continue }
            for name in entries {
                // Sidecar main files only (skip their -shm/-wal): default.store.<tag>-<ts>
                guard name.hasPrefix(storeName + "."), !name.hasSuffix("-shm"), !name.hasSuffix("-wal")
                else { continue }
                out.append(dir.appendingPathComponent(name))
            }
        }
        return out
    }

    // MARK: - Backup

    /// Move a store and its siblings aside to `<name>.<reason>-<timestamp>`.
    /// A move (not copy) so the slot is freed for a fresh store, and a move
    /// (not delete) so the bytes are always preserved.
    static func backUpStore(at storeURL: URL, reason: String) {
        let fm = FileManager.default
        let dir = storeURL.deletingLastPathComponent()
        let base = storeURL.lastPathComponent
        let stamp = Int(Date().timeIntervalSince1970)
        for suffix in storeSuffixes {
            let src = dir.appendingPathComponent(base + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = dir.appendingPathComponent("\(base).\(reason)-\(stamp)\(suffix)")
            do {
                try fm.moveItem(at: src, to: dst)
                recoveryLogger.notice("Backed up store file → \(dst.lastPathComponent, privacy: .public)")
            } catch {
                recoveryLogger.error("Backup of \(src.lastPathComponent, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Copy (not move) the canonical store and its siblings to a timestamped
    /// sidecar, leaving the live store in place. Used before a destructive but
    /// intentional action (Settings → Delete All) so it's always recoverable.
    static func snapshotStore(reason: String) {
        let fm = FileManager.default
        let store = canonicalStoreURL()
        let dir = store.deletingLastPathComponent()
        let base = store.lastPathComponent
        let stamp = Int(Date().timeIntervalSince1970)
        for suffix in storeSuffixes {
            let src = dir.appendingPathComponent(base + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = dir.appendingPathComponent("\(base).\(reason)-\(stamp)\(suffix)")
            do {
                try fm.copyItem(at: src, to: dst)
            } catch {
                recoveryLogger.error("Snapshot of \(src.lastPathComponent, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        recoveryLogger.notice("Snapshot taken before \(reason, privacy: .public)")
    }

    // MARK: - Helpers

    /// Count user-data rows in the store at `url` WITHOUT mutating it
    /// (read-only). Returns 0 if the store is absent/empty, or -1 if it exists
    /// but can't be opened/read (incompatible schema, locked, encrypted).
    static func userDataCount(at url: URL) -> Int {
        guard anyFileExists(at: url) else { return 0 }
        // Probe read-only with the current schema first; for a store that
        // predates the latest additive migration (still V1 on disk, as it is
        // when this runs at launch *before* the main container migrates), a
        // read-only open under the current schema can't migrate-to-load, so fall
        // back to counting under the original V1 schema it was written with. The
        // five counted models exist in every version, so the count is exact
        // either way — and we never mutate the store with a -1 "unreadable" that
        // could mislead recovery on a perfectly good older store.
        if let count = countUserRows(at: url, schema: Schema(models)) { return count }
        if let count = countUserRows(at: url, schema: Schema(PiruSchemaV1.models)) { return count }
        return -1
    }

    private static func countUserRows(at url: URL, schema: Schema) -> Int? {
        do {
            // .none — never let the iCloud entitlement pull this read-only probe
            // into CloudKit setup (the schema is CloudKit-incompatible). See
            // PiruApp.makeContainer.
            let config = ModelConfiguration(url: url, allowsSave: false, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: config)
            let context = ModelContext(container)
            // DoseEntry is the journal — the data "No Entries" refers to — plus
            // the other user-authored models. Colors are cosmetic but counted too.
            let counts = [
                (try? context.fetchCount(FetchDescriptor<DoseEntry>())) ?? 0,
                (try? context.fetchCount(FetchDescriptor<DailyDoseItem>())) ?? 0,
                (try? context.fetchCount(FetchDescriptor<FavoriteSubstance>())) ?? 0,
                (try? context.fetchCount(FetchDescriptor<SubstanceColor>())) ?? 0,
                (try? context.fetchCount(FetchDescriptor<UserColor>())) ?? 0,
            ]
            return counts.reduce(0, +)
        } catch {
            return nil
        }
    }

    private static func anyFileExists(at storeURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: storeURL.path)
    }

    /// Copy a store and its siblings to `dest` (overwriting only after the
    /// caller has backed up any existing dest). Copies -shm/-wal too so an
    /// uncheckpointed WAL is preserved and replayed on open.
    static func copyStore(from source: URL, to dest: URL) throws {
        let fm = FileManager.default
        let srcDir = source.deletingLastPathComponent()
        let srcBase = source.lastPathComponent
        let dstDir = dest.deletingLastPathComponent()
        let dstBase = dest.lastPathComponent
        for suffix in storeSuffixes {
            let src = srcDir.appendingPathComponent(srcBase + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = dstDir.appendingPathComponent(dstBase + suffix)
            if fm.fileExists(atPath: dst.path) {
                try fm.removeItem(at: dst) // safe: caller backed it up first
            }
            try fm.copyItem(at: src, to: dst)
        }
    }
}
