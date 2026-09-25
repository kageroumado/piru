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
    /// Whether the SQLite store at `url` is safe to hand to SwiftData.
    ///
    /// `false` only on *evidence of corruption*: the file is not a database, its
    /// pages are malformed, or `PRAGMA quick_check` reports a problem. A
    /// **missing** file counts as readable (`true`): a fresh install has no store
    /// yet and SwiftData creating one is the normal path. So does a probe that
    /// could not run to a verdict — a permission error on a locked device
    /// (Data Protection, background launch), an interrupted statement, a busy
    /// file — because the recovery this gate feeds replaces the canonical store
    /// with an older candidate, and a transient error must never trigger that.
    nonisolated static func isReadable(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        switch probe(at: url) {
        case .healthy:
            return true
        case let .corrupt(detail):
            Logger.storeHealth.error("Store corrupt at \(url.path, privacy: .public): \(detail, privacy: .public)")
            return false
        case let .inconclusive(detail):
            Logger.storeHealth.error("Store integrity probe inconclusive at \(url.path, privacy: .public): \(detail, privacy: .public)")
            return true
        }
    }

    private enum Verdict {
        case healthy
        case corrupt(String)
        case inconclusive(String)
    }

    /// Open a throwaway connection, run `quick_check`, and drop the connection.
    ///
    /// Read-only first: a read-only connection takes no write lock and skips the
    /// WAL checkpoint SQLite otherwise runs when the last connection closes —
    /// that checkpoint, an fsync on the App Group store during launch, is where
    /// iOS suspended and killed the process (`SerializedDatabase.deinit`
    /// crashes). SQLite opens a WAL-mode store read-only whenever it can create
    /// the `-shm` beside it, which a sandbox directory always allows; the
    /// read-write open remains as the fallback for the case where it cannot.
    /// Both connections observe suspension so an in-flight `quick_check` is
    /// interrupted rather than holding its lock into suspension.
    ///
    /// The busy timeout waits out a lock another connection is still letting go
    /// of — the widget finishing a read of the App Group store, or a container
    /// released a moment ago — so the header is actually read and judged. Without
    /// it a busy store returns `SQLITE_BUSY` before the header is examined,
    /// which reads as inconclusive and lets a corrupt file through the gate.
    private nonisolated static func probe(at url: URL) -> Verdict {
        var config = Configuration()
        config.label = "piru-storehealth"
        config.observesSuspensionNotifications = true
        config.busyMode = .timeout(1)
        var readOnly = config
        readOnly.readonly = true
        let queue: DatabaseQueue
        do {
            queue = try DatabaseQueue(path: url.path, configuration: readOnly)
        } catch let error as DatabaseError where error.indicatesCorruption {
            return .corrupt(error.description)
        } catch {
            do {
                queue = try DatabaseQueue(path: url.path, configuration: config)
            } catch let error as DatabaseError where error.indicatesCorruption {
                return .corrupt(error.description)
            } catch {
                return .inconclusive(error.localizedDescription)
            }
        }
        do {
            let result = try queue.read { db in
                try String.fetchOne(db, sql: "PRAGMA quick_check")
            }
            return result == "ok" ? .healthy : .corrupt("quick_check: \(result ?? "nil")")
        } catch let error as DatabaseError where error.indicatesCorruption {
            return .corrupt(error.description)
        } catch {
            return .inconclusive(error.localizedDescription)
        }
    }
}

extension DatabaseError {
    /// Whether SQLite is saying the file itself is bad — not a database, or a
    /// malformed one — as opposed to a condition of the moment (permissions,
    /// a lock, an interrupt, I/O) that a later open would not see.
    nonisolated var indicatesCorruption: Bool {
        resultCode == .SQLITE_CORRUPT || resultCode == .SQLITE_NOTADB
    }
}
