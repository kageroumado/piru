import Foundation
import GRDB
import os

/// Carries an install from the legacy app identity to its successor on the same device.
///
/// A new bundle ID is a separate app with its own sandbox and app group, so a successor
/// install would otherwise open empty. Both identities are on one team, and the successor
/// is also entitled to the legacy app group (``AppIdentity/legacyAppGroup``), which makes
/// that group the meeting point:
///
/// - The **legacy** build publishes what only its own sandbox can see — its standard
///   defaults and the source-priority database in `Documents/` — into `handoff/` in its
///   group container, at launch and again on backgrounding (``Publisher``).
/// - The **successor**, before it opens its store for the first time, copies the legacy
///   SwiftData store, the legacy group defaults and that published state into its own
///   containers (``Importer``). It runs once, never overwrites anything the successor
///   already has, and leaves an empty but working app when a step fails.
nonisolated enum LegacyHandoff {
    /// The folder in the legacy group container the legacy build publishes into.
    static let handoffFolder = "handoff"
    /// The legacy build's standard-defaults domain, as a binary property list.
    static let standardDefaultsFile = "standard-defaults.plist"
    /// The source-priority database, relative to `Documents/` and to ``handoffFolder``.
    static let userPrefsFile = "piru-user-prefs.sqlite"

    /// Prefix of every key this type writes, which a domain copy never carries across.
    static let keyPrefix = "legacyHandoff."
    /// Standard defaults: when this install finished importing.
    static let completedAtKey = "legacyHandoff.completedAt"
    /// Standard defaults: how many journal entries came over (0 when none did).
    static let importedJournalEntriesKey = "legacyHandoff.importedJournalEntries"
    /// Legacy group defaults: when a successor imported this install's data, read by the
    /// legacy build to tell people their journal already lives in the new app.
    static let successorImportedAtKey = "legacyHandoff.successorImportedAt"

    /// Keys in a standard-defaults domain that belong to the system or the frameworks
    /// rather than to Piru, and describe the legacy install rather than the person
    /// (`SK…` is StoreKit's own transaction bookkeeping, which is per app).
    static let systemKeyPrefixes = ["com.apple.", "NSWindow", "WebKit", "AK", "INNext", "SK"]

    // MARK: - Entry points

    /// Legacy side: publish the sandbox-only state for a successor. No-op in the successor.
    static func publishIfLegacy() {
        guard AppIdentity.isLegacy,
              let publisher = Publisher.live() else { return }
        do {
            try publisher.publish()
        } catch {
            Logger.legacyHandoff.error("Publishing the handoff failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Successor side: import the legacy install when this one has nothing yet. Call before
    /// the `ModelContainer` opens. No-op in the legacy build.
    @discardableResult
    static func importIfSuccessor() -> Importer.Outcome? {
        guard !AppIdentity.isLegacy,
              let importer = Importer.live() else { return nil }
        let outcome = importer.run()
        Logger.legacyHandoff.notice("Legacy handoff: \(String(describing: outcome), privacy: .public)")
        return outcome
    }

    /// Journal entries the successor imported from the legacy app, or 0 when it imported
    /// none (or this is the legacy build).
    static var importedJournalEntries: Int {
        UserDefaults.standard.integer(forKey: importedJournalEntriesKey)
    }

    /// When a successor imported this legacy install, or `nil` if none has. Legacy build only.
    static var successorImportedAt: Date? {
        UserDefaults(suiteName: AppIdentity.legacyAppGroup)?.object(forKey: successorImportedAtKey) as? Date
    }

    private static func groupContainer(_ identifier: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    private static var documentsDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    // MARK: - Publisher

    /// Writes the legacy build's sandbox-only state into its group container.
    struct Publisher {
        /// The legacy app group container.
        let groupContainer: URL
        /// The legacy app's `Documents/`.
        let documents: URL
        /// Scratch space inside the sandbox, where the database copy is assembled so no
        /// SQLite lock is ever held on a file in the shared container.
        let scratch: URL
        /// The app's standard-defaults domain.
        let standardDomain: () -> [String: Any]?

        static func live() -> Publisher? {
            guard let container = LegacyHandoff.groupContainer(AppIdentity.legacyAppGroup),
                  let documents = LegacyHandoff.documentsDirectory,
                  let bundleID = Bundle.main.bundleIdentifier else { return nil }
            return Publisher(
                groupContainer: container,
                documents: documents,
                scratch: FileManager.default.temporaryDirectory,
                standardDomain: { UserDefaults.standard.persistentDomain(forName: bundleID) },
            )
        }

        var folder: URL {
            groupContainer.appendingPathComponent(LegacyHandoff.handoffFolder, isDirectory: true)
        }

        /// Publish both pieces. Rewrites only what changed; safe to call at any time.
        func publish() throws {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try publishStandardDefaults()
            try publishUserPrefs()
        }

        private func publishStandardDefaults() throws {
            let domain = (standardDomain() ?? [:]).filter { !LegacyHandoff.isExcludedStandardKey($0.key) }
            let data = try PropertyListSerialization.data(fromPropertyList: domain, format: .binary, options: 0)
            let target = folder.appendingPathComponent(LegacyHandoff.standardDefaultsFile)
            // The dictionary serializes in hash order, so equal domains can differ in bytes:
            // compare decoded contents before rewriting.
            if let existing = try? Data(contentsOf: target),
               let decoded = try? PropertyListSerialization.propertyList(from: existing, format: nil) as? NSDictionary,
               decoded.isEqual(to: domain) { return }
            try data.write(to: target, options: .atomic)
        }

        /// A consistent copy through SQLite's backup API, safe while the live store has a
        /// connection open, folded into one self-contained file and then moved into place.
        private func publishUserPrefs() throws {
            let source = documents.appendingPathComponent(LegacyHandoff.userPrefsFile)
            guard FileManager.default.fileExists(atPath: source.path) else { return }
            let staged = scratch.appendingPathComponent("handoff-\(UUID().uuidString)-\(LegacyHandoff.userPrefsFile)")
            defer { LegacyHandoff.removeDatabaseFiles(at: staged) }
            _ = try LegacyHandoff.backUpDatabase(from: source, to: staged)
            let target = folder.appendingPathComponent(LegacyHandoff.userPrefsFile)
            if FileManager.default.fileExists(atPath: target.path) {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: staged)
            } else {
                try FileManager.default.moveItem(at: staged, to: target)
            }
        }
    }

    // MARK: - Importer

    /// Copies a legacy install into the successor's containers, once.
    struct Importer {
        enum Outcome: Equatable {
            /// A previous launch finished the import.
            case alreadyDone
            /// There is no legacy store to import.
            case noLegacyStore
            /// The successor already holds data of its own; nothing was touched.
            case successorHasData
            /// The successor's store exists but cannot be read; left to `StoreRecovery`.
            case successorUnreadable
            /// The legacy install came over, with this many journal entries.
            case imported(journalEntries: Int)
            /// Copying the store failed; the successor opens empty and the next launch retries.
            case failed
        }

        /// The legacy app group container.
        let legacyContainer: URL
        /// The successor's app group container.
        let successorContainer: URL
        /// The successor's `Documents/`.
        let successorDocuments: URL
        /// The legacy app group's defaults domain.
        let legacyGroupDomain: () -> [String: Any]?
        /// The successor's app group defaults.
        let successorGroupDefaults: UserDefaults
        /// The successor's standard defaults, which also hold the done-marker.
        let standardDefaults: UserDefaults
        /// Tells the legacy install its data has been imported.
        let markLegacyImported: (Date) -> Void
        /// User rows in a store: 0 for none or absent, -1 for unreadable.
        var userDataCount: (URL) -> Int = StoreRecovery.userDataCount(at:)

        static func live() -> Importer? {
            guard let legacy = LegacyHandoff.groupContainer(AppIdentity.legacyAppGroup),
                  let successor = LegacyHandoff.groupContainer(AppIdentity.appGroup),
                  let documents = LegacyHandoff.documentsDirectory,
                  let groupDefaults = UserDefaults(suiteName: AppIdentity.appGroup) else { return nil }
            let legacyGroup = AppIdentity.legacyAppGroup
            return Importer(
                legacyContainer: legacy,
                successorContainer: successor,
                successorDocuments: documents,
                legacyGroupDomain: { UserDefaults(suiteName: legacyGroup)?.persistentDomain(forName: legacyGroup) },
                successorGroupDefaults: groupDefaults,
                standardDefaults: .standard,
                markLegacyImported: { UserDefaults(suiteName: legacyGroup)?.set($0, forKey: successorImportedAtKey) },
            )
        }

        var legacyStore: URL {
            legacyContainer.appendingPathComponent(StoreRecovery.storeName)
        }

        var successorStore: URL {
            successorContainer.appendingPathComponent(StoreRecovery.storeName)
        }

        var handoffFolder: URL {
            legacyContainer.appendingPathComponent(LegacyHandoff.handoffFolder, isDirectory: true)
        }

        func run() -> Outcome {
            let fileManager = FileManager.default
            if standardDefaults.object(forKey: LegacyHandoff.completedAtKey) != nil { return .alreadyDone }
            guard fileManager.fileExists(atPath: legacyStore.path) else { return .noLegacyStore }

            // "Fresh" is the store holding no user rows, not the file being absent: the
            // successor's widget can create an empty store before the app's first launch.
            switch userDataCount(successorStore) {
            case 0:
                break
            case ..<0:
                return .successorUnreadable
            default:
                markCompleted(journalEntries: 0)
                return .successorHasData
            }

            let journalEntries: Int
            do {
                journalEntries = try importStore()
            } catch {
                Logger.legacyHandoff.error("Importing the legacy store failed: \(error.localizedDescription, privacy: .public)")
                return .failed
            }
            copyExternalData()
            importGroupDefaults()
            importStandardDefaults()
            importUserPrefs()
            markCompleted(journalEntries: journalEntries)
            markLegacyImported(Date())
            return .imported(journalEntries: journalEntries)
        }

        private func markCompleted(journalEntries: Int) {
            standardDefaults.set(Date(), forKey: LegacyHandoff.completedAtKey)
            standardDefaults.set(journalEntries, forKey: LegacyHandoff.importedJournalEntriesKey)
        }

        /// Backs the legacy store up into a staging file beside the successor store, then
        /// moves it into place — the move is the commit point, so an interrupted copy
        /// never leaves a half-written store where the app opens it. Returns the number of
        /// journal entries it carries.
        private func importStore() throws -> Int {
            let fileManager = FileManager.default
            let staging = successorContainer
                .appendingPathComponent(".legacy-handoff-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: staging) }

            let staged = staging.appendingPathComponent(StoreRecovery.storeName)
            let journalEntries = try LegacyHandoff.backUpDatabase(from: legacyStore, to: staged) { db in
                guard try db.tableExists("ZDOSEENTRY") else { return 0 }
                return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ZDOSEENTRY") ?? 0
            }

            // An empty store in the way (the widget made it) is set aside, never deleted.
            if StoreRecovery.storeSuffixes.contains(where: {
                fileManager.fileExists(atPath: successorStore.path + $0)
            }) {
                StoreRecovery.backUpStore(at: successorStore, reason: "empty-before-handoff")
            }
            try fileManager.moveItem(at: staged, to: successorStore)
            return journalEntries
        }

        /// Attribute values SwiftData keeps outside the SQLite file (`.externalStorage`).
        /// Each file is named by a UUID the store refers to, so copying the missing ones
        /// never collides.
        private func copyExternalData() {
            let relative = ".\(StoreRecovery.storeName.replacingOccurrences(of: ".store", with: ""))_SUPPORT/_EXTERNAL_DATA"
            let source = legacyContainer.appendingPathComponent(relative, isDirectory: true)
            let target = successorContainer.appendingPathComponent(relative, isDirectory: true)
            let fileManager = FileManager.default
            guard let names = try? fileManager.contentsOfDirectory(atPath: source.path), !names.isEmpty else { return }
            do {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                for name in names where !fileManager.fileExists(atPath: target.appendingPathComponent(name).path) {
                    try fileManager.copyItem(at: source.appendingPathComponent(name), to: target.appendingPathComponent(name))
                }
            } catch {
                Logger.legacyHandoff.error("Copying external attribute data failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        private func importGroupDefaults() {
            let domain = (legacyGroupDomain() ?? [:]).filter { !$0.key.hasPrefix(LegacyHandoff.keyPrefix) }
            let added = LegacyHandoff.merge(domain, into: successorGroupDefaults)
            Logger.legacyHandoff.info("Group defaults: \(added, privacy: .public) of \(domain.count, privacy: .public) keys imported")
        }

        private func importStandardDefaults() {
            let file = handoffFolder.appendingPathComponent(LegacyHandoff.standardDefaultsFile)
            guard let data = try? Data(contentsOf: file) else {
                Logger.legacyHandoff.notice("No published standard defaults to import")
                return
            }
            guard let domain = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                Logger.legacyHandoff.error("The published standard defaults are unreadable")
                return
            }
            let added = LegacyHandoff.merge(
                domain.filter { !LegacyHandoff.isExcludedStandardKey($0.key) }, into: standardDefaults,
            )
            Logger.legacyHandoff.info("Standard defaults: \(added, privacy: .public) of \(domain.count, privacy: .public) keys imported")
        }

        /// The published copy is one self-contained file, so a plain copy to a temporary
        /// name and a move is enough; an existing prefs database is kept.
        private func importUserPrefs() {
            let fileManager = FileManager.default
            let source = handoffFolder.appendingPathComponent(LegacyHandoff.userPrefsFile)
            let target = successorDocuments.appendingPathComponent(LegacyHandoff.userPrefsFile)
            guard fileManager.fileExists(atPath: source.path),
                  !fileManager.fileExists(atPath: target.path) else { return }
            let partial = successorDocuments.appendingPathComponent(".\(LegacyHandoff.userPrefsFile)-\(UUID().uuidString)")
            do {
                try fileManager.createDirectory(at: successorDocuments, withIntermediateDirectories: true)
                try fileManager.copyItem(at: source, to: partial)
                try fileManager.moveItem(at: partial, to: target)
            } catch {
                try? fileManager.removeItem(at: partial)
                Logger.legacyHandoff.error("Importing source priorities failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Shared helpers

    static func isExcludedStandardKey(_ key: String) -> Bool {
        key.hasPrefix(keyPrefix) || systemKeyPrefixes.contains { key.hasPrefix($0) }
    }

    /// Writes each key `defaults` does not already have. Returns how many it wrote.
    @discardableResult
    static func merge(_ domain: [String: Any], into defaults: UserDefaults) -> Int {
        var added = 0
        for (key, value) in domain where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
            added += 1
        }
        return added
    }

    /// Copies the database at `source` into a new file at `destination` with SQLite's
    /// online backup API — a consistent snapshot even while another process writes, WAL
    /// included — and leaves `destination` as a single rollback-journal file with no
    /// `-wal`/`-shm` beside it. `inspect` reads the copy before it closes.
    @discardableResult
    static func backUpDatabase<T>(
        from source: URL, to destination: URL, inspect: (Database) throws -> T = { _ in () },
    ) throws -> T {
        var sourceConfiguration = Configuration()
        sourceConfiguration.label = "legacy-handoff-source"
        sourceConfiguration.busyMode = .timeout(5)
        let sourceQueue = try DatabaseQueue(path: source.path, configuration: sourceConfiguration)
        defer { try? sourceQueue.close() }

        var destinationConfiguration = Configuration()
        destinationConfiguration.label = "legacy-handoff-destination"
        let destinationQueue = try DatabaseQueue(path: destination.path, configuration: destinationConfiguration)
        do {
            try sourceQueue.backup(to: destinationQueue)
            let result = try destinationQueue.writeWithoutTransaction { db in
                // The backup copies the source's WAL flag into the header; fold the copy
                // back to a rollback journal so it is one file that can be moved alone.
                try db.execute(sql: "PRAGMA journal_mode = DELETE")
                guard try String.fetchOne(db, sql: "PRAGMA quick_check") == "ok" else {
                    throw DatabaseError(resultCode: .SQLITE_CORRUPT, message: "backup failed quick_check")
                }
                return try inspect(db)
            }
            try destinationQueue.close()
            return result
        } catch {
            try? destinationQueue.close()
            removeDatabaseFiles(at: destination)
            throw error
        }
    }

    static func removeDatabaseFiles(at url: URL) {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
}
