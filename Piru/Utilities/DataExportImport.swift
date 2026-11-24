import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

// MARK: - Millisecond Timestamps

extension Date {
    nonisolated var msSince1970: Int64 {
        Int64(timeIntervalSince1970 * 1_000)
    }
    nonisolated init(ms: Int64) {
        self.init(timeIntervalSince1970: Double(ms) / 1_000.0)
    }
}

// MARK: - Export / Import

/// The on-disk shapes Piru can write.
enum ExportFormat: Equatable {
    /// Piru-native, lossless (sessions, per-dose location, background flags, …).
    case piru
    /// The Piru-native format holding every profile: the owner's journal at
    /// the top level, every other profile's in ``PiruFile/profiles``.
    case piruEveryone
    /// PsychonautWiki's modern interchange format — importable by PW, but lossy
    /// for Piru-only fields.
    case psyLog
    /// The PsychonautWiki format holding every profile's journal: the active
    /// profile's doses unnamed, everyone else's under their name.
    case psyLogEveryone
    /// The journal as one CSV row per dose, in the layout
    /// ``DataExportImport/spreadsheetColumns`` names, which the spreadsheet
    /// importer reads back.
    case spreadsheet

    /// The file type the export is saved as.
    var contentType: UTType {
        self == .spreadsheet ? .commaSeparatedText : .json
    }
}

enum DataExportImport {
    // MARK: Export

    /// Build the export `Data` synchronously on the main actor. Used by the
    /// backup manager and tests; the UI uses
    /// ``exportJSONInBackground(format:context:customStore:)`` so the encode of a
    /// large library doesn't block the main thread behind no spinner.
    @MainActor
    static func exportJSON(
        format: ExportFormat = .piru,
        context: ModelContext,
        customStore: CustomSubstanceStore = .shared,
        settings: SettingsScope = .live,
    ) throws -> Data {
        switch format {
        case .piru: try encodeJSON(makePiruFile(context: context, customStore: customStore, settings: settings))
        case .piruEveryone: try exportBackupJSON(context: context)
        case .psyLog: try encodeJSON(makePsyLogFile(context: context))
        case .psyLogEveryone: try encodeJSON(makePsyLogFile(people: everyone(activeContext: context)))
        case .spreadsheet: try spreadsheetCSV(context: context)
        }
    }

    /// Gather on the main actor, then encode off it. Lets the caller show a
    /// spinner that actually animates while the heavy `JSONEncoder` work runs on
    /// a background task.
    @MainActor
    static func exportJSONInBackground(
        format: ExportFormat,
        context: ModelContext,
        customStore: CustomSubstanceStore = .shared,
    ) async throws -> Data {
        switch format {
        case .piru:
            let file = try makePiruFile(context: context, customStore: customStore, settings: .live)
            return try await Task.detached(priority: .userInitiated) { try encodeJSON(file) }.value
        case .piruEveryone:
            let file = try makeBackupFile(context: context)
            return try await Task.detached(priority: .userInitiated) { try encodeJSON(file) }.value
        case .psyLog:
            let file = try makePsyLogFile(context: context)
            return try await Task.detached(priority: .userInitiated) { try encodeJSON(file) }.value
        case .psyLogEveryone:
            let file = try makePsyLogFile(people: everyone(activeContext: context))
            return try await Task.detached(priority: .userInitiated) { try encodeJSON(file) }.value
        case .spreadsheet:
            return try spreadsheetCSV(context: context)
        }
    }

    nonisolated static func encodeJSON(_ value: some Encodable & Sendable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    /// The Piru-native format this build writes and the newest it reads. An
    /// additive change (a new optional field) keeps the number; only a file an
    /// older build would misread bumps it.
    nonisolated static let piruExportVersion = 2

    /// Which importer owns a file, decided from its top-level keys alone.
    nonisolated enum FileShape: Equatable {
        /// Piru-native (`piruExportVersion`), with the app that wrote it.
        case piruNative(appVersion: String?)
        /// PsychonautWiki (`experiences`), both the modern (`exportSource`
        /// present) and the old (`customSubstances` present, no `exportSource`)
        /// shapes; ``importPsyLog`` decodes both leniently.
        case psyLog
        /// A DrugsPRO journal export (`v`, `e`, `u`).
        case drugsPro
        /// Piru's own early `doseEntries` backup format.
        case legacy
    }

    /// Reads just enough of the file to name its importer, and throws an
    /// ``ImportFileError`` for anything no importer could make sense of, so
    /// the alert says what the file is rather than which field a decoder
    /// happened to trip on.
    nonisolated static func classify(_ data: Data) throws -> FileShape {
        guard !data.isEmpty else { throw ImportFileError.empty }
        guard let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else {
            throw ImportFileError.notJSON
        }
        guard let object = json as? [String: Any] else { throw ImportFileError.unrecognized }
        if object["piruExportVersion"] != nil {
            guard let version = object["piruExportVersion"] as? Int else { throw ImportFileError.unrecognized }
            let appVersion = object["appVersion"] as? String
            guard version <= piruExportVersion else {
                throw ImportFileError.newerFormat(version: version, appVersion: appVersion)
            }
            return .piruNative(appVersion: appVersion)
        }
        if object["experiences"] != nil { return .psyLog }
        if object["doseEntries"] != nil { return .legacy }
        if isDrugsPro(object) { return .drugsPro }
        if object["sealed"] != nil, object["kind"] != nil { throw ImportFileError.encrypted }
        throw ImportFileError.unrecognized
    }

    /// Classifies and fully decodes the file without touching any store, throwing
    /// the same errors ``importJSON(data:context:customStore:)`` would. A
    /// destructive restore runs this before wiping, so a file that cannot
    /// import never empties the journal.
    nonisolated static func validate(_ data: Data) throws {
        switch try classify(data) {
        case let .piruNative(appVersion):
            do {
                _ = try JSONDecoder().decode(PiruFile.self, from: data)
            } catch let error as DecodingError {
                throw ImportFileError.malformedNative(appVersion: appVersion, underlying: error)
            }
        case .psyLog:
            _ = try JSONDecoder().decode(PsyLogFile.self, from: data)
        case .drugsPro:
            _ = try JSONDecoder().decode(DrugsProFile.self, from: data)
        case .legacy:
            try validateLegacy(data: data)
        }
    }

    /// Routes the file to the importer ``classify(_:)`` names. A native file
    /// the decoder rejects surfaces as ``ImportFileError/malformedNative`` so
    /// the alert can say which app wrote it. `mode` is `.replace` only when the
    /// caller has just emptied the store for this import. Saves the context and
    /// emits the dose-log change tick itself, so a caller adds neither.
    ///
    /// `psyLogRouting` sends a PsychonautWiki file's named people to their
    /// profiles' stores (``PsyLogImportMapping``); without it only the file
    /// owner's doses import. Each store written into is finished and committed
    /// under its own profile's scope.
    @MainActor
    static func importJSON(
        data: Data,
        context: ModelContext,
        customStore: CustomSubstanceStore = .shared,
        mode: ImportMode = .merge,
        settings: SettingsScope = .live,
        psyLogRouting: PsyLogRouting? = nil,
    ) throws {
        var fileSettings: PiruSettingsData?
        var otherStores: [PsyLogImportedStore] = []
        switch try classify(data) {
        case let .piruNative(appVersion):
            do {
                fileSettings = try importPiruNative(data: data, context: context, customStore: customStore)
            } catch let error as DecodingError {
                throw ImportFileError.malformedNative(appVersion: appVersion, underlying: error)
            }
        case .psyLog:
            otherStores = try importPsyLog(data: data, context: context, customStore: customStore, routing: psyLogRouting)
        case .drugsPro:
            try importDrugsPro(data: data, context: context)
        case .legacy:
            try importLegacy(data: data, context: context)
        }
        resolveImportedDoses(in: context)
        // A file with no color rows (or one that predates them) would leave every
        // imported substance gray on the surfaces that read the rows, until the
        // launch mint pass ran on the next launch.
        SubstanceColorStore.mintMissingRows(in: context)

        // Last, because a changed source priority drops the substance catalog's
        // resolved caches, which the backfills above read.
        if let fileSettings {
            applySettings(fileSettings, mode: mode, to: settings)
        }

        try commitImport(context: context)

        for store in otherStores {
            try ProfileScope.$pinned.withValue(store.profile) {
                resolveImportedDoses(in: store.context)
                SubstanceColorStore.mintMissingRows(in: store.context)
                try commitImport(context: store.context)
            }
        }
    }

    /// Clusters session-less imported doses into sessions and resolves the PSID
    /// identity of anything that came in name-only, so imported doses key on
    /// identity and title from their resolved form right away, not only after
    /// the next launch. Both passes are data-driven: a native import, which
    /// assigns its own sessions and identities, finds nothing pending.
    @MainActor
    static func resolveImportedDoses(in context: ModelContext) {
        SessionService.assignUnassignedDoses(in: context)
        PSIDBackfillMigration.run(context: context)
        CuratedIdentityBackfillMigration.run(context: context)
    }

    /// Commits an import, then signals — the order every dose write follows. The
    /// tick wakes readers of the committed store (tolerance, body levels, launch
    /// caches, which fetch on `DatabaseActor`) and keys the Insights models'
    /// memos, so sent before the commit it lets them cache the pre-import log
    /// under the post-import revision, and nothing re-signals when autosave lands.
    @MainActor
    static func commitImport(context: ModelContext) throws {
        try context.save()
        DoseLogService.shared.changed()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Re-reads everything an import can change that a live singleton holds in
    /// memory, so the running app shows the imported profile, notification
    /// choices, units, skin, dock, tab bar and search history without a relaunch, and
    /// schedules the restored meds' reminders. Called by the import and
    /// restore screens after a successful import.
    @MainActor
    static func refreshLiveStores(container: ModelContainer) {
        UserProfileStore.shared.configure(container: container)
        NotificationPreferencesStore.shared.configure(container: container)
        CustomUnitStore.shared.configure(container: container)
        SkinStore.shared.reloadFromDefaults()
        DockPreferences.shared.reloadFromDefaults()
        TabLayoutStore.shared.reloadFromDefaults()
        SearchHistoryStore.shared.reloadFromDefaults()
        DoseNotificationManager.syncMedReminders(in: container.mainContext)
        Task(name: "Rewarm substance catalog") { await SubstanceStore.shared.ensureAllLoaded() }
    }

    /// A user-facing message for an import failure: what the file is when no
    /// importer could take it, and otherwise the failing field, because
    /// `DecodingError`'s stock `localizedDescription` ("The data couldn't be
    /// read because it is missing.") names neither the field nor the file
    /// shape, which made real user reports undiagnosable.
    nonisolated static func importErrorMessage(for error: Error) -> String {
        switch error {
        case ImportFileError.empty:
            String(localized: "The file is empty. Nothing was saved into it, so export again and wait for the save to finish before importing.")
        case ImportFileError.notJSON:
            String(localized: "The file isn't valid JSON.")
        case ImportFileError.unrecognized:
            String(localized: "This file isn't a Piru export or a PsychonautWiki journal.")
        case ImportFileError.encrypted:
            String(localized: "This is an encrypted Piru backup. Import it from Tools → Data & Backup, which asks for its passphrase.")
        case let ImportFileError.newerFormat(version, appVersion):
            writtenBy(
                appVersion,
                String(localized: "This file uses export format \(version), which this version of Piru can't read yet. Update Piru, then import it."),
            )
        case let ImportFileError.malformedNative(appVersion, underlying):
            writtenBy(appVersion, decodingErrorMessage(for: underlying))
        case let decodingError as DecodingError:
            decodingErrorMessage(for: decodingError)
        default:
            error.localizedDescription
        }
    }

    /// Appends the writing app when the file named one, so a report of a
    /// field problem says which build produced it.
    private nonisolated static func writtenBy(_ appVersion: String?, _ message: String) -> String {
        guard let appVersion else { return message }
        return String(localized: "\(message) The file was written by \(appVersion).")
    }

    private nonisolated static func decodingErrorMessage(for decodingError: DecodingError) -> String {
        switch decodingError {
        case let .keyNotFound(key, context):
            return String(localized: "The file is missing a required field: \(fieldPath(context.codingPath + [key])).")
        case let .valueNotFound(_, context):
            return String(localized: "The file has an empty value for a required field: \(fieldPath(context.codingPath)).")
        case let .typeMismatch(_, context), let .dataCorrupted(context):
            let path = fieldPath(context.codingPath)
            if path.isEmpty {
                return String(localized: "The file isn't valid JSON.")
            }
            return String(localized: "The file has an unexpected value at: \(path).")
        @unknown default:
            return decodingError.localizedDescription
        }
    }

    /// Renders a coding path as `experiences[2].sortDate`.
    private nonisolated static func fieldPath(_ path: [any CodingKey]) -> String {
        var rendered = ""
        for key in path {
            if let index = key.intValue {
                rendered += "[\(index)]"
            } else {
                rendered += rendered.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
        return rendered
    }

    /// Merge imported custom substances into the store: add new ones, update
    /// same-name matches (keeping the existing row's UUID), skip exact dupes.
    static func importCustomSubstances(_ list: [PiruCustomSubstanceData], into customStore: CustomSubstanceStore) {
        var existingByName: [String: CustomSubstanceEntry] = Dictionary(
            customStore.all.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first },
        )
        for imported in list {
            let incoming = imported.asEntry
            let key = incoming.name.lowercased()
            if let existing = existingByName[key] {
                guard existing != incoming else { continue }
                let merged = CustomSubstanceEntry(
                    id: existing.id,
                    name: incoming.name,
                    displayName: incoming.displayName,
                    category: incoming.category,
                    defaultRoute: incoming.defaultRoute,
                    unit: incoming.unit,
                    notes: incoming.notes,
                    doses: incoming.doses,
                    duration: incoming.duration,
                    halfLifeMinutes: incoming.halfLifeMinutes,
                    components: incoming.components,
                    createdAt: incoming.createdAt,
                )
                customStore.update(merged)
                existingByName[key] = merged
            } else {
                customStore.add(incoming)
                existingByName[key] = incoming
            }
        }
    }

    /// Content-based identity for a dose entry, used to skip duplicates on
    /// import. Lowercased substance/unit so cosmetic casing differences don't
    /// defeat it; millisecond timestamp matches the export precision. A `nil`
    /// amount is an unknown dose, which matches only another unknown dose.
    static func doseDedupKey(substance: String, timestamp: Date, amount: Double?, unit: String, route: RouteOfAdministration) -> String {
        "\(substance.lowercased())|\(timestamp.msSince1970)|\(amount.map { "\($0)" } ?? "?")|\(unit.lowercased())|\(route.rawValue)"
    }

    /// ``doseDedupKey(substance:timestamp:amount:unit:route:)`` for a stored dose.
    static func doseDedupKey(for entry: DoseEntry, route: RouteOfAdministration? = nil) -> String {
        doseDedupKey(
            substance: entry.substance, timestamp: entry.timestamp, amount: entry.isUnknownDose ? nil : entry.amount,
            unit: entry.unit, route: route ?? entry.route,
        )
    }

    /// Gives an imported experience its session: the session already holding
    /// doses the file repeats (`matched`), else a new one when the experience
    /// brought at least one new dose. A reused session takes the file's title
    /// and note only where it has none, so an edit made here survives, and a
    /// re-import still brings in notes an earlier import could not place.
    /// Returns `nil`, inserting nothing, when there is no session to hold them.
    @MainActor
    @discardableResult
    static func importedSession(
        doses: [DoseEntry],
        matched: Session?,
        title: String?,
        note: String?,
        context: ModelContext,
    ) -> Session? {
        let session: Session
        if let matched {
            session = matched
            if session.title == nil { session.title = title }
            if session.note == nil { session.note = note }
        } else {
            guard let start = doses.map(\.timestamp).min() else { return nil }
            session = Session(startDate: start, title: title, note: note)
            context.insert(session)
        }
        for dose in doses {
            dose.session = session
        }
        session.refreshDoseBounds()
        SessionNoteService.ensureSummaryNote(for: session)
        return session
    }

    static func deleteAll(context: ModelContext) throws {
        try PiruSchema.deleteAll(in: context)
        DoseLogEntries.shared.invalidate()
    }

    static var exportFilename: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HHmmss"
        return "Piru \(f.string(from: .now))"
    }
}

// MARK: - Import dedup

/// The journal's doses by ``DataExportImport/doseDedupKey(for:route:)``, so an
/// importer skips a dose the journal already holds, or one it took earlier in
/// the same file, and finds the session that holds a repeated dose.
@MainActor
struct ImportedDoseIndex {
    enum Claim {
        case new
        /// Already taken; `stored` is the journal's copy, `nil` when the
        /// first copy came earlier in this file.
        case duplicate(stored: DoseEntry?)
    }

    private var stored: [String: DoseEntry] = [:]
    private var seen: Set<String> = []

    init(_ entries: [DoseEntry]) {
        for entry in entries {
            add(DataExportImport.doseDedupKey(for: entry), entry)
            // The launch backfill files a dose logged as "Estradiol Valerate"
            // under Estradiol with the ester as its salt form, while the file
            // it came from still names the ester.
            if let saltForm = entry.saltForm {
                add(DataExportImport.doseDedupKey(
                    substance: "\(entry.substance) \(saltForm)", timestamp: entry.timestamp,
                    amount: entry.isUnknownDose ? nil : entry.amount, unit: entry.unit, route: entry.route,
                ), entry)
            }
        }
    }

    private mutating func add(_ key: String, _ entry: DoseEntry) {
        seen.insert(key)
        if stored[key] == nil { stored[key] = entry }
    }

    /// Takes `key` for an incoming dose, or reports it already taken.
    mutating func claim(_ key: String) -> Claim {
        seen.insert(key).inserted ? .new : .duplicate(stored: stored[key])
    }
}

// MARK: - Import file errors

/// Why a file could not be imported before any format's decoder ran, or, for
/// a Piru-native file, which app wrote the file the decoder rejected. Rendered
/// for the user by ``DataExportImport/importErrorMessage(for:)``.
nonisolated enum ImportFileError: Error {
    /// Zero bytes: the save never wrote the content.
    case empty
    case notJSON
    /// Valid JSON, but none of the shapes Piru reads.
    case unrecognized
    /// An encrypted Piru backup, which only the restore flow can open.
    case encrypted
    /// A Piru-native file in a format newer than ``DataExportImport/piruExportVersion``.
    case newerFormat(version: Int, appVersion: String?)
    /// A Piru-native file the decoder rejected, with the app that wrote it.
    case malformedNative(appVersion: String?, underlying: DecodingError)
}

// MARK: - File Document for Export

struct PiruDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json, .commaSeparatedText]
    }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
