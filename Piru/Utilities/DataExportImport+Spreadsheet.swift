import Foundation
import SwiftData

// MARK: - Spreadsheet import

extension DataExportImport {
    /// How a spreadsheet import landed.
    struct SpreadsheetImportOutcome: Equatable {
        let imported: Int
        /// Rows already in the journal, from an earlier import of the same or
        /// an overlapping sheet.
        let duplicates: Int
    }

    /// Inserts the drafts a ``SpreadsheetConverter`` produced, skipping any
    /// dose the journal already holds, then clusters them into sessions and
    /// commits like every other import.
    ///
    /// Which drafts are already in the journal is ``spreadsheetDuplicates(_:context:resolver:)``.
    @MainActor
    @discardableResult
    static func importSpreadsheet(
        _ drafts: [SpreadsheetDoseDraft],
        context: ModelContext,
        resolver: SpreadsheetSubstanceResolver = SpreadsheetSubstanceMatch.library,
    ) throws -> SpreadsheetImportOutcome {
        let duplicates = spreadsheetDuplicates(drafts, context: context, resolver: resolver)
        var imported = 0
        var names = Set<String>()
        for (draft, isDuplicate) in zip(drafts, duplicates) where !isDuplicate {
            context.insert(DoseEntry(
                substance: draft.substance,
                amount: draft.amount,
                unit: draft.unit,
                route: draft.route,
                timestamp: draft.timestamp,
                timeZoneIdentifier: nil,
                notes: draft.notes,
                tags: draft.tags,
                locationName: draft.locationName,
                latitude: draft.latitude,
                longitude: draft.longitude,
                isApproximate: draft.isApproximate,
                isUnknownDose: draft.isUnknownDose,
            ))
            names.insert(draft.substance)
            imported += 1
        }

        var colorRows = (try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []
        for name in names.sorted() {
            if let row = SubstanceColorStore.ensureRow(for: name, existing: colorRows, in: context) {
                colorRows.append(row)
            }
        }
        resolveImportedDoses(in: context)
        try commitImport(context: context)
        return SpreadsheetImportOutcome(imported: imported, duplicates: duplicates.count { $0 })
    }

    /// How many of `drafts` the journal already holds, so the preview can say
    /// so before anything is written.
    @MainActor
    static func spreadsheetDuplicateCount(
        _ drafts: [SpreadsheetDoseDraft],
        context: ModelContext,
        resolver: SpreadsheetSubstanceResolver = SpreadsheetSubstanceMatch.library,
    ) -> Int {
        spreadsheetDuplicates(drafts, context: context, resolver: resolver).count { $0 }
    }

    /// Per draft, whether the journal already holds it.
    ///
    /// A draft matches a journal dose on substance (as the catalog names it),
    /// time to the millisecond, amount, unit (in Piru's spelling) and route,
    /// so importing a sheet twice, or two exported tabs that overlap, adds
    /// each dose once. Each journal dose answers for one draft: two identical
    /// rows in a file are two doses, and against one copy in the journal one
    /// of them still imports. Drafts are never matched against each other.
    ///
    /// A draft placed at noon for want of a time also needs the same notes,
    /// because its time is a placeholder: two same-day doses of the same
    /// amount differ only in what was written beside them, and a dose logged
    /// by hand at noon has its own notes. A re-imported row carries the notes
    /// its first import wrote, so it still matches.
    @MainActor
    static func spreadsheetDuplicates(
        _ drafts: [SpreadsheetDoseDraft],
        context: ModelContext,
        resolver: SpreadsheetSubstanceResolver = SpreadsheetSubstanceMatch.library,
    ) -> [Bool] {
        var journal = spreadsheetJournalNotes(in: context, resolver: resolver)
        return drafts.map { draft in
            let key = spreadsheetDedupKey(draft)
            guard var candidates = journal[key] else { return false }
            let notes = draft.notes ?? ""
            guard let match = candidates.firstIndex(of: notes) ?? (draft.timeIsInferred ? nil : candidates.indices.first) else {
                return false
            }
            candidates.remove(at: match)
            journal[key] = candidates.isEmpty ? nil : candidates
            return true
        }
    }

    /// The journal's doses by dedup key, each as its notes, one per dose.
    @MainActor
    private static func spreadsheetJournalNotes(in context: ModelContext, resolver: SpreadsheetSubstanceResolver) -> [String: [String]] {
        let existing = (try? context.fetch(FetchDescriptor<DoseEntry>())) ?? []
        var canonical: [String: String] = [:]
        var index: [String: [String]] = [:]
        for entry in existing {
            let name = canonical[entry.substance] ?? {
                let resolved = resolver(entry.substance)?.name ?? entry.substance
                canonical[entry.substance] = resolved
                return resolved
            }()
            let key = spreadsheetDedupKey(
                substance: name, timestamp: entry.timestamp, amount: entry.amount, unit: entry.unit, route: entry.route,
            )
            index[key, default: []].append(entry.notes ?? "")
        }
        return index
    }

    private static func spreadsheetDedupKey(_ draft: SpreadsheetDoseDraft) -> String {
        spreadsheetDedupKey(
            substance: draft.substance, timestamp: draft.timestamp, amount: draft.amount, unit: draft.unit, route: draft.route,
        )
    }

    /// ``doseDedupKey(substance:timestamp:amount:unit:route:)`` with the unit in
    /// Piru's spelling and the time rounded to the millisecond, which is the
    /// precision the CSV export writes.
    private static func spreadsheetDedupKey(
        substance: String, timestamp: Date, amount: Double, unit: String, route: RouteOfAdministration,
    ) -> String {
        let milliseconds = Int64((timestamp.timeIntervalSince1970 * 1_000).rounded())
        return "\(substance.lowercased())|\(milliseconds)|\(amount)|\(SpreadsheetUnits.normalized(unit).lowercased())|\(route.rawValue)"
    }
}

// MARK: - Spreadsheet export

extension DataExportImport {
    /// The CSV export's columns. English on purpose: the importer recognizes
    /// headers in six languages, and a fixed layout reads the same everywhere.
    static let spreadsheetColumns = [
        "Date", "Substance", "Amount", "Unit", "Route", "Approximate", "Notes", "Tags", "Location", "Latitude", "Longitude",
    ]

    /// The journal as CSV, oldest dose first: ISO 8601 times with their UTC
    /// offset, an empty amount for an unknown dose, text that would start a
    /// formula prefixed with `'`, and a UTF-8 byte-order mark so Excel reads
    /// accented and CJK text correctly.
    @MainActor
    static func spreadsheetCSV(context: ModelContext, timeZone: TimeZone = .current) throws -> Data {
        let doses = try context.fetch(FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp)]))
        var rows = [spreadsheetColumns]
        // Typed text is neutralized so a note like "=SUM(…)" or "-shaky" opens as
        // text, never as a formula; the numbers and dates Piru writes stay bare.
        let text = DelimitedText.neutralizingFormula
        for dose in doses {
            rows.append([
                iso8601(dose.timestamp, timeZone: timeZone),
                text(dose.substance),
                dose.isUnknownDose ? "" : spreadsheetNumber(dose.amount),
                text(dose.unit),
                dose.route.rawValue,
                dose.isApproximate ? "yes" : "",
                text(dose.notes ?? ""),
                text(dose.tags.joined(separator: ", ")),
                text(dose.locationName ?? ""),
                dose.latitude.map(spreadsheetNumber) ?? "",
                dose.longitude.map(spreadsheetNumber) ?? "",
            ])
        }
        return Data(("\u{FEFF}" + DelimitedText.write(rows)).utf8)
    }

    /// `2015-06-25T23:28:00+02:00`, with milliseconds when the time has them.
    nonisolated static func iso8601(_ date: Date, timeZone: TimeZone) -> String {
        let totalMilliseconds = Int64((date.timeIntervalSince1970 * 1_000).rounded())
        let wholeSeconds = Int64((Double(totalMilliseconds) / 1_000).rounded(.down))
        let milliseconds = Int(totalMilliseconds - wholeSeconds * 1_000)
        let instant = Date(timeIntervalSince1970: Double(wholeSeconds))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: instant)
        let offset = timeZone.secondsFromGMT(for: instant)
        let sign = offset < 0 ? "-" : "+"
        var text = String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0,
        )
        if milliseconds > 0 { text += String(format: ".%03d", milliseconds) }
        text += sign + String(format: "%02d:%02d", abs(offset) / 3_600, abs(offset) % 3_600 / 60)
        return text
    }

    /// A number in its shortest exact spelling, decimal point, no exponent.
    nonisolated static func spreadsheetNumber(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        let shortest = "\(value)"
        guard shortest.contains("e") else { return shortest }
        var fixed = String(format: "%.12f", value)
        while fixed.hasSuffix("0") {
            fixed.removeLast()
        }
        return fixed.hasSuffix(".") ? String(fixed.dropLast()) : fixed
    }
}
