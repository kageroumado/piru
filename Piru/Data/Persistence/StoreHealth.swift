import Foundation
import GRDB
import os

/// Cheap, *catchable* integrity gate for an on-disk SQLite store, run before the
/// file is handed to an ORM that would otherwise abort *natively* on corruption.
///
/// Why this exists: SwiftData's `ModelContainer` open probes the schema with
/// `-[NSSQLiteConnection _hasTableWithName:]`, which on a malformed store aborts
/// the process below the Swift error layer — a `do`/`catch` around the container
/// open cannot save it (the build-30 `StoreRecovery.countUserRows` launch crash).
/// GRDB's own SQLite open plus a raw `PRAGMA quick_check` fails *throwably*
/// instead, so a corrupt store becomes a branch we can handle (quarantine,
/// recover, or launch in-memory) rather than a hard crash at launch.
///
/// The invariant this enforces at its call sites: **no SQLite file reaches a
/// SwiftData open without first passing `isReadable`.** Both the recovery probe
/// (`StoreRecovery.userDataCount`) and the live container open
/// (`PiruApp.makeContainer`) funnel through here.
enum StoreHealth {
    private nonisolated static let logger = Logger(subsystem: "dev.yumeji.piru", category: "StoreHealth")

    /// Whether the SQLite store at `url` opens and passes `PRAGMA quick_check`.
    ///
    /// A **missing** file counts as readable (`true`): a fresh install has no
    /// store yet and SwiftData creating one is the normal path — only an
    /// existing-but-corrupt file is the hazard this gate exists for.
    ///
    /// The probe opens a throwaway GRDB connection and drops it before returning,
    /// so it never holds a lock when the caller then opens the same file. Any
    /// failure — the open throwing, `quick_check` throwing, or a result other
    /// than `"ok"` — is treated as unreadable.
    ///
    /// Opened read-write (not read-only): a read-only SQLite connection can fail
    /// to open a WAL-mode store even on a writable sandbox, which would false-flag
    /// a healthy store. A read-only *probe* would be tidier for the quarantined
    /// candidates the recovery scan inspects, but the only mutation a read-then-
    /// close incurs is a passive WAL checkpoint, which is data-preserving.
    nonisolated static func isReadable(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        var config = Configuration()
        config.label = "piru-storehealth"
        do {
            let queue = try DatabaseQueue(path: url.path, configuration: config)
            let result = try queue.read { db in
                try String.fetchOne(db, sql: "PRAGMA quick_check")
            }
            if result == "ok" { return true }
            logger.error("Store failed quick_check at \(url.path, privacy: .public): \(result ?? "nil", privacy: .public)")
            return false
        } catch {
            logger.error("Store unopenable for integrity check at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
