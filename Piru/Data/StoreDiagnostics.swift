import Foundation
import OSLog
import SwiftData

/// Builds a plain-text diagnostics report the user can send to the developer when
/// the store fails to open at launch. It pairs a store inventory (what exists on
/// disk, how many rows, which recoverable sidecars) with the recent `os_log`
/// entries from Piru's own subsystem — enough to pinpoint a recovery failure
/// without containing any dose data itself.
nonisolated enum StoreDiagnostics {
    static let subsystem = "dev.yumeji.piru"

    /// Assemble the full report. Runs the log fetch + read-only store probes off
    /// the main actor (both can block) and returns the text to share.
    static func reportText() async -> String {
        await Task.detached(priority: .userInitiated) {
            var out: [String] = []
            out.append("Piru diagnostics")
            out.append("Generated: \(ISO8601DateFormatter().string(from: stamp()))")
            out.append("App: \(appVersionLine())")
            out.append("")
            out.append(contentsOf: storeSection())
            out.append("")
            out.append("Recent logs (this launch):")
            out.append(contentsOf: logLines())
            return out.joined(separator: "\n")
        }.value
    }

    /// An error building the diagnostics report — surfaced to the user so a
    /// failure never looks like a silent no-op.
    enum ReportError: LocalizedError {
        case encodingFailed
        var errorDescription: String? {
            switch self {
            case .encodingFailed: String(localized: "Couldn't prepare the diagnostics file.")
            }
        }
    }

    /// Write the report to a temporary `.txt` file for a share sheet. Caller
    /// removes the file once sharing finishes. Throws (never returns a bad URL) so
    /// the caller can show an error rather than presenting an empty share sheet.
    static func writeReport() async throws -> URL {
        let text = await reportText()
        guard let data = text.data(using: .utf8) else { throw ReportError.encodingFailed }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("piru-diagnostics-\(Int(stamp().timeIntervalSince1970)).txt")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Sections

    private static func storeSection() -> [String] {
        let canonical = StoreRecovery.canonicalStoreURL()
        var lines = ["Canonical store: \(canonical.path)"]
        lines.append("  rows: \(StoreRecovery.userDataCount(at: canonical))")
        lines.append("  size: \(byteString(StoreRecovery.canonicalStoreBytes()))")
        let recoverable = StoreRecovery.recoverableStores()
        if recoverable.isEmpty {
            lines.append("Recoverable sidecars: none")
        } else {
            lines.append("Recoverable sidecars (\(recoverable.count)):")
            for store in recoverable {
                let when = store.timestamp.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"
                lines.append("  • \(store.reason): rows=\(store.rowCount), size=\(byteString(store.bytes)), when=\(when)")
            }
        }
        return lines
    }

    /// Recent entries from Piru's subsystem in this process. iOS scopes
    /// `OSLogStore` to the current process, which is exactly what we want — the
    /// launch-time recovery/migration logs live here.
    private static func logLines() -> [String] {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let since = store.position(date: stamp().addingTimeInterval(-1800))
            let entries = try store.getEntries(
                at: since,
                matching: NSPredicate(format: "subsystem == %@", subsystem),
            )
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm:ss.SSS"
            var lines: [String] = []
            for case let entry as OSLogEntryLog in entries {
                lines.append("\(fmt.string(from: entry.date)) [\(entry.category)] \(entry.composedMessage)")
            }
            return lines.isEmpty ? ["  (no Piru log entries captured)"] : lines
        } catch {
            return ["  (could not read logs: \(error.localizedDescription))"]
        }
    }

    // MARK: - Helpers

    private static func appVersionLine() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private static func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// A wall-clock timestamp. `Date()` is intentionally used here (diagnostics are
    /// one-shot and never replayed), isolated to one place.
    private static func stamp() -> Date { Date() }
}
