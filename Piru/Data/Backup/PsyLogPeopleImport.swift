import Foundation
import SwiftData

/// A PsychonautWiki file that names the people it holds doses for, read and
/// waiting for the user to say whose journal each person's doses go into.
nonisolated struct PsyLogPendingImport: Identifiable, Sendable {
    let id = UUID()
    let data: Data
    /// The owner (unnamed doses) first when present, then each named person.
    let consumers: [PsyLogConsumer]
    let experienceCount: Int

    /// The pending import for a PsychonautWiki file that names anyone; `nil`
    /// for every other file, which imports as it always has.
    static func inspect(_ data: Data) -> PsyLogPendingImport? {
        guard (try? DataExportImport.classify(data)) == .psyLog,
              let file = try? JSONDecoder().decode(PsyLogFile.self, from: data),
              file.namesAnyone else { return nil }
        return PsyLogPendingImport(data: data, consumers: file.consumers, experienceCount: file.experiences.count)
    }
}

/// Hands a pending PsychonautWiki import to the people sheet
/// (``SheetRoute/psyLogImport``) and its outcome back to the screen that
/// picked the file. One import at a time, as there is one file picker.
@MainActor
enum PsyLogImportRequest {
    enum Outcome {
        case imported
        case cancelled
        case failed(String)
    }

    private(set) static var current: (pending: PsyLogPendingImport, onFinish: (Outcome) -> Void)?

    /// Present the people sheet for `pending`.
    static func present(
        _ pending: PsyLogPendingImport,
        navigator: AppNavigator = .shared,
        onFinish: @escaping (Outcome) -> Void,
    ) {
        current = (pending, onFinish)
        navigator.present(.psyLogImport)
    }

    /// Report how the import ended to the screen that asked for it, once.
    static func finish(_ outcome: Outcome) {
        let request = current
        current = nil
        request?.onFinish(outcome)
    }
}
