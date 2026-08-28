import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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

/// The two on-disk shapes Piru can write.
enum ExportFormat: Equatable {
    /// Piru-native, lossless (sessions, per-dose location, background flags, …).
    case piru
    /// PsychonautWiki's modern interchange format — importable by PW, but lossy
    /// for Piru-only fields.
    case psyLog
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
    ) throws -> Data {
        switch format {
        case .piru: try encodeJSON(makePiruFile(context: context, customStore: customStore))
        case .psyLog: try encodeJSON(makePsyLogFile(context: context))
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
            let file = try makePiruFile(context: context, customStore: customStore)
            return try await Task.detached(priority: .userInitiated) { try encodeJSON(file) }.value
        case .psyLog:
            let file = try makePsyLogFile(context: context)
            return try await Task.detached(priority: .userInitiated) { try encodeJSON(file) }.value
        }
    }

    nonisolated static func encodeJSON(_ value: some Encodable & Sendable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    /// Detects the file shape and routes to the right importer:
    /// - `piruExportVersion` → Piru-native (lossless).
    /// - `experiences` → PsychonautWiki, both the modern (`exportSource`
    ///   present) and the old (`customSubstances` present, no `exportSource`)
    ///   shapes; ``importPsyLog`` decodes both leniently.
    /// - otherwise → Piru's own early `doseEntries` backup format.
    @MainActor
    static func importJSON(data: Data, context: ModelContext, customStore: CustomSubstanceStore = .shared) throws {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if json?["piruExportVersion"] != nil {
            try importPiruNative(data: data, context: context, customStore: customStore)
        } else if json?["experiences"] != nil {
            try importPsyLog(data: data, context: context, customStore: customStore)
        } else {
            try importLegacy(data: data, context: context)
        }
        // Cluster any session-less imports (PsyLog/legacy) into sessions. The
        // native importer assigns its own sessions, so this is a no-op for it.
        SessionService.assignUnassignedDoses(in: context)

        // Resolve the PSID identity of anything that came in name-only — a PsyLog
        // dose, or a native file written before PSID — so it keys on identity and
        // titles from its resolved form right away, not only after the next launch.
        // Data-driven (substanceUID == nil gate), so a fully-resolved native import
        // finds nothing pending. Curated rows (imported favorites/daily) too.
        PSIDBackfillMigration.run(context: context)
        CuratedIdentityBackfillMigration.run(context: context)

        // One debounced tick wakes the tolerance cache after a bulk import (the burst coalesces).
        DoseLogService.shared.changed()
    }

    /// A user-facing message for an import failure. `DecodingError`'s stock
    /// `localizedDescription` ("The data couldn't be read because it is
    /// missing.") names neither the field nor the file shape, which made real
    /// user reports undiagnosable — so name the failing field explicitly.
    nonisolated static func importErrorMessage(for error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }
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
            return error.localizedDescription
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
    /// defeat it; millisecond timestamp matches the export precision.
    static func doseDedupKey(substance: String, timestamp: Date, amount: Double, unit: String, route: RouteOfAdministration) -> String {
        "\(substance.lowercased())|\(timestamp.msSince1970)|\(amount)|\(unit.lowercased())|\(route.rawValue)"
    }

    static func deleteAll(context: ModelContext) throws {
        try context.delete(model: DoseEntry.self)
        try context.delete(model: Session.self)
        try context.delete(model: DailyDoseItem.self)
        try context.delete(model: SubstanceColor.self)
        try context.delete(model: UserColor.self)
        try context.delete(model: FavoriteSubstance.self)
        try context.delete(model: InventoryItem.self)
        // The curated quick-log list is derived from history — clearing the doses
        // without clearing it leaves ghost chips referencing substances that no
        // longer exist. It re-seeds from history on the next quick-log open.
        try context.delete(model: QuickLogDose.self)
    }

    static var exportFilename: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HHmmss"
        return "Piru \(f.string(from: .now))"
    }
}

// MARK: - File Document for Export

struct PiruDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json]
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
