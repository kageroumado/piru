import Foundation
import UIKit

/// Renders the shareable medical PDF report from pre-snapshotted data.
///
/// **`nonisolated` by design** so generation can run off the main actor
/// (`UIGraphicsPDFRenderer` is documented thread-safe). The draw passes only
/// touch nonisolated helpers (`HalfLifeDatabase.halfLife(for:)`,
/// `Calendar.sessionDayStart`, `Double.doseFormatted`, `PKModel`) and the
/// snapshot value types below. The one genuinely MainActor-bound lookup —
/// `InteractionChecker.drugClasses(for:)`, which memoises into a mutable
/// static cache and resolves through the `SubstanceLibrary`/`SubstanceStore`
/// singleton — is resolved on main at snapshot-build time and carried in
/// `InteractionSnapshot`, so nothing here re-enters the main actor. See
/// `ReportView.generateReport()`, which builds the snapshot on main and
/// renders + writes the file from a detached task.
nonisolated enum PDFReportGenerator {
    // MARK: - Layout

    private enum Layout {
        static let pageSize = CGSize(width: 612, height: 792)
        static let margin: CGFloat = 50
        static let contentWidth: CGFloat = pageSize.width - margin * 2
        static let lineSpacing: CGFloat = 4
        static let sectionSpacing: CGFloat = 24
        static let rowHeight: CGFloat = 18
    }

    private enum Fonts {
        static let title = UIFont.systemFont(ofSize: 22, weight: .bold)
        static let subtitle = UIFont.systemFont(ofSize: 11, weight: .regular)
        static let sectionHeader = UIFont.systemFont(ofSize: 14, weight: .semibold)
        static let body = UIFont.systemFont(ofSize: 10, weight: .regular)
        static let bodyBold = UIFont.systemFont(ofSize: 10, weight: .semibold)
        static let caption = UIFont.systemFont(ofSize: 8.5, weight: .regular)
    }

    private enum Colors {
        static let accent = UIColor(red: 0.93, green: 0.34, blue: 0.53, alpha: 1)
        static let text = UIColor.black
        static let secondaryText = UIColor.darkGray
        static let lightGray = UIColor(white: 0.92, alpha: 1)
        static let zebraStripe = UIColor(white: 0.96, alpha: 1)
        static let tableHeaderBg = UIColor(white: 0.94, alpha: 1)
        static let accentLight = UIColor(red: 0.93, green: 0.34, blue: 0.53, alpha: 0.08)
        static let dangerousBg = UIColor(red: 1.0, green: 0.90, blue: 0.90, alpha: 1)
        static let unsafeBg = UIColor(red: 1.0, green: 0.95, blue: 0.88, alpha: 1)
        static let cautionBg = UIColor(red: 1.0, green: 0.98, blue: 0.88, alpha: 1)
        static let dangerousRed = UIColor(red: 0.85, green: 0.15, blue: 0.15, alpha: 1)
        static let unsafeOrange = UIColor(red: 0.90, green: 0.55, blue: 0.10, alpha: 1)
        static let cautionYellow = UIColor(red: 0.65, green: 0.55, blue: 0.10, alpha: 1)
    }

    // MARK: - Snapshots

    struct EntrySnapshot {
        let substance: String
        let amount: Double
        let unit: String
        let route: String
        let timestamp: Date
        let notes: String?
        let tags: [String]
        /// Adherence-join fields mirroring ``AdherenceCalculator/matches`` —
        /// the PSID identity key plus the raw route, so the PDF's adherence
        /// table credits exactly what the in-app screen credits.
        var identityKey: String = ""
        var routeRaw: String = ""
    }

    struct DailyDoseSnapshot {
        let substance: String
        let amount: Double
        let unit: String
        let route: String
        let sortOrder: Int
        /// See ``EntrySnapshot/identityKey``.
        var identityKey: String = ""
        var routeRaw: String = ""
    }

    struct InteractionSnapshot {
        let severity: InteractionSeverity
        let substanceA: String
        let substanceB: String
        let description: String
        /// Drug classes resolved on the main actor at snapshot-build time —
        /// `InteractionChecker.drugClasses(for:)` is MainActor-bound, so the
        /// draw pass consumes these instead of looking classes up itself.
        let drugClassesA: [DrugClass]
        let drugClassesB: [DrugClass]
    }

    struct ReportData {
        let entries: [EntrySnapshot]
        let dailyDoseItems: [DailyDoseSnapshot]
        let interactions: [InteractionSnapshot]
        let startDate: Date
        let endDate: Date
        let notes: String
        let patientName: String
    }

    // MARK: - Page Tracking

    private struct Cursor {
        let context: UIGraphicsPDFRendererContext
        var y: CGFloat = 0
        var pageNumber: Int = 0

        mutating func newPage() {
            if pageNumber > 0 {
                drawPageNumber()
            }
            context.beginPage()
            pageNumber += 1
            y = Layout.margin
        }

        mutating func ensureSpace(_ needed: CGFloat) {
            if y + needed > Layout.pageSize.height - Layout.margin - 30 {
                newPage()
            }
        }

        private func drawPageNumber() {
            let attr: [NSAttributedString.Key: Any] = [
                .font: Fonts.caption,
                .foregroundColor: Colors.secondaryText,
            ]
            let text = "Page \(pageNumber)"
            let size = (text as NSString).size(withAttributes: attr)
            let x = (Layout.pageSize.width - size.width) / 2
            text.draw(at: CGPoint(x: x, y: Layout.pageSize.height - 30), withAttributes: attr)
        }

        func drawFinalPageNumber() {
            let attr: [NSAttributedString.Key: Any] = [
                .font: Fonts.caption,
                .foregroundColor: Colors.secondaryText,
            ]
            let text = "Page \(pageNumber)"
            let size = (text as NSString).size(withAttributes: attr)
            let x = (Layout.pageSize.width - size.width) / 2
            text.draw(at: CGPoint(x: x, y: Layout.pageSize.height - 30), withAttributes: attr)
        }
    }

    // MARK: - Generate

    static func generate(from data: ReportData) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: Layout.pageSize))

        return renderer.pdfData { context in
            var cursor = Cursor(context: context)

            drawHeader(&cursor, data: data)

            if !data.dailyDoseItems.isEmpty {
                drawSectionHeader(&cursor, title: "Current Medications")
                drawMedicationsTable(&cursor, items: data.dailyDoseItems)
            }

            // Adherence
            if !data.dailyDoseItems.isEmpty, !data.entries.isEmpty {
                drawSectionHeader(&cursor, title: "Adherence")
                drawAdherence(&cursor, entries: data.entries, dailyDoses: data.dailyDoseItems, startDate: data.startDate, endDate: data.endDate)
            }

            if !data.interactions.isEmpty {
                drawSectionHeader(&cursor, title: "Interaction Alerts")
                drawInteractions(&cursor, interactions: data.interactions)
            }

            // Duplicate substances
            let duplicates = findDuplicates(in: data.entries)
            if !duplicates.isEmpty {
                drawSectionHeader(&cursor, title: "Possible Duplicate Substances")
                drawDuplicates(&cursor, duplicates: duplicates)
            }

            let sortedEntries = data.entries.sorted { $0.timestamp < $1.timestamp }
            if !sortedEntries.isEmpty {
                let summary = buildSubstanceSummary(from: sortedEntries)
                drawSectionHeader(&cursor, title: "Substance Summary")
                drawSubstanceSummary(&cursor, summary: summary)

                // PK concentration charts for top substances with half-life data
                let topForPK = summary.prefix(5)
                let pkSubstances = topForPK.compactMap { stat -> (name: String, halfLife: Double, doseCount: Int)? in
                    guard let hl = HalfLifeDatabase.halfLife(for: stat.name) else { return nil }
                    return (name: stat.name, halfLife: hl, doseCount: stat.totalDoses)
                }
                if !pkSubstances.isEmpty {
                    drawSectionHeader(&cursor, title: "Pharmacokinetic Profiles")
                    for pk in pkSubstances {
                        drawPKChart(&cursor, substanceName: pk.name, halfLifeMinutes: pk.halfLife)
                    }
                }
            }

            if !sortedEntries.isEmpty {
                drawSectionHeader(&cursor, title: "Usage Log")
                drawUsageLog(&cursor, entries: sortedEntries)
            }

            if !data.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                drawSectionHeader(&cursor, title: "Notes")
                drawWrappedText(&cursor, text: data.notes, font: Fonts.body, color: Colors.text)
            }

            drawFooter(&cursor)
            cursor.drawFinalPageNumber()
        }
    }

    // MARK: - Header

    private static func drawHeader(_ cursor: inout Cursor, data: ReportData) {
        cursor.newPage()

        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: Fonts.title, .foregroundColor: Colors.accent,
        ]
        "Piru — Substance Report".draw(at: CGPoint(x: Layout.margin, y: cursor.y), withAttributes: titleAttr)
        cursor.y += 30

        let linePath = UIBezierPath()
        linePath.move(to: CGPoint(x: Layout.margin, y: cursor.y))
        linePath.addLine(to: CGPoint(x: Layout.margin + Layout.contentWidth, y: cursor.y))
        Colors.accent.setStroke()
        linePath.lineWidth = 2
        linePath.stroke()
        cursor.y += 10

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.locale = Locale(identifier: "en_US")

        let subtitleAttr: [NSAttributedString.Key: Any] = [
            .font: Fonts.subtitle, .foregroundColor: Colors.secondaryText,
        ]

        if !data.patientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            "Patient: \(data.patientName)".draw(
                at: CGPoint(x: Layout.margin, y: cursor.y), withAttributes: subtitleAttr,
            )
            cursor.y += 16
        }

        "Period: \(dateFormatter.string(from: data.startDate)) — \(dateFormatter.string(from: data.endDate))".draw(
            at: CGPoint(x: Layout.margin, y: cursor.y), withAttributes: subtitleAttr,
        )
        cursor.y += 16
        "Generated: \(dateFormatter.string(from: .now))".draw(
            at: CGPoint(x: Layout.margin, y: cursor.y), withAttributes: subtitleAttr,
        )
        cursor.y += 10

        // Quick stats badges
        let substanceCount = Set(data.entries.map(\.substance)).count
        let entryCount = data.entries.count
        let unsafeCount = data.interactions.count(where: { $0.severity == .unsafe || $0.severity == .dangerous })

        let statsAttr: [NSAttributedString.Key: Any] = [
            .font: Fonts.bodyBold, .foregroundColor: Colors.text,
        ]
        let stats = [
            "\(substanceCount) substances",
            "\(entryCount) entries",
            "\(unsafeCount) alert\(unsafeCount == 1 ? "" : "s")",
        ]
        var badgeX = Layout.margin
        for stat in stats {
            let size = (stat as NSString).size(withAttributes: statsAttr)
            let pillRect = CGRect(x: badgeX - 6, y: cursor.y - 2, width: size.width + 12, height: size.height + 4)
            Colors.zebraStripe.setFill()
            UIBezierPath(roundedRect: pillRect, cornerRadius: 8).fill()
            stat.draw(at: CGPoint(x: badgeX, y: cursor.y), withAttributes: statsAttr)
            badgeX += size.width + 20
        }
        cursor.y += Layout.sectionSpacing
    }

    // MARK: - Section Header

    private static func drawSectionHeader(_ cursor: inout Cursor, title: String) {
        cursor.ensureSpace(80)
        cursor.y += 12

        // Left accent bar
        let attr: [NSAttributedString.Key: Any] = [.font: Fonts.sectionHeader, .foregroundColor: Colors.text]
        let titleSize = (title as NSString).size(withAttributes: attr)
        let barRect = CGRect(x: Layout.margin, y: cursor.y + 1, width: 3, height: titleSize.height - 2)
        Colors.accent.setFill()
        UIBezierPath(roundedRect: barRect, cornerRadius: 1.5).fill()

        title.draw(at: CGPoint(x: Layout.margin + 10, y: cursor.y), withAttributes: attr)
        cursor.y += titleSize.height + 6

        let path = UIBezierPath()
        path.move(to: CGPoint(x: Layout.margin, y: cursor.y))
        path.addLine(to: CGPoint(x: Layout.margin + Layout.contentWidth, y: cursor.y))
        Colors.lightGray.setStroke()
        path.lineWidth = 0.5
        path.stroke()
        cursor.y += 8
    }

    // MARK: - Alternating Row Background

    private static func drawRowBackground(_ cursor: inout Cursor, rowIndex: Int, height: CGFloat) {
        if rowIndex % 2 == 1 {
            let rect = CGRect(x: Layout.margin - 4, y: cursor.y - 1, width: Layout.contentWidth + 8, height: height)
            Colors.zebraStripe.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 2).fill()
        }
    }

    private static func drawTableHeaderRow(_ cursor: inout Cursor) {
        let rect = CGRect(x: Layout.margin - 4, y: cursor.y - 2, width: Layout.contentWidth + 8, height: Layout.rowHeight)
        Colors.tableHeaderBg.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 2).fill()
    }

    private static func drawTableHeaderSeparator(_ cursor: inout Cursor) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: Layout.margin, y: cursor.y))
        path.addLine(to: CGPoint(x: Layout.margin + Layout.contentWidth, y: cursor.y))
        Colors.secondaryText.withAlphaComponent(0.3).setStroke()
        path.lineWidth = 0.5
        path.stroke()
        cursor.y += 4
    }

    // MARK: - Medications Table

    private static func drawMedicationsTable(_ cursor: inout Cursor, items: [DailyDoseSnapshot]) {
        let sorted = items.sorted { $0.sortOrder < $1.sortOrder }
        let colWidths: [CGFloat] = [Layout.contentWidth * 0.50, Layout.contentWidth * 0.25, Layout.contentWidth * 0.25]
        let headerAttr: [NSAttributedString.Key: Any] = [.font: Fonts.bodyBold, .foregroundColor: Colors.secondaryText]
        let nameAttr: [NSAttributedString.Key: Any] = [.font: Fonts.bodyBold, .foregroundColor: Colors.text]
        let rowAttr: [NSAttributedString.Key: Any] = [.font: Fonts.body, .foregroundColor: Colors.text]

        drawTableHeaderRow(&cursor)
        var x = Layout.margin
        for (i, header) in ["Substance", "Dose", "Route"].enumerated() {
            header.draw(at: CGPoint(x: x, y: cursor.y), withAttributes: headerAttr)
            x += colWidths[i]
        }
        cursor.y += Layout.rowHeight
        drawTableHeaderSeparator(&cursor)

        for (idx, item) in sorted.enumerated() {
            cursor.ensureSpace(Layout.rowHeight)
            drawRowBackground(&cursor, rowIndex: idx, height: Layout.rowHeight)
            x = Layout.margin
            item.substance.draw(at: CGPoint(x: x, y: cursor.y), withAttributes: nameAttr)
            x += colWidths[0]
            "\(item.amount.doseFormatted) \(item.unit)".draw(at: CGPoint(x: x, y: cursor.y), withAttributes: rowAttr)
            x += colWidths[1]
            item.route.draw(at: CGPoint(x: x, y: cursor.y), withAttributes: rowAttr)
            cursor.y += Layout.rowHeight
        }
        cursor.y += Layout.lineSpacing
    }

    // MARK: - Adherence

    private static func drawAdherence(_ cursor: inout Cursor, entries: [EntrySnapshot], dailyDoses: [DailyDoseSnapshot], startDate: Date, endDate: Date) {
        let calendar = Calendar.current
        let headerAttr: [NSAttributedString.Key: Any] = [.font: Fonts.bodyBold, .foregroundColor: Colors.secondaryText]
        let nameAttr: [NSAttributedString.Key: Any] = [.font: Fonts.bodyBold, .foregroundColor: Colors.text]
        let rowAttr: [NSAttributedString.Key: Any] = [.font: Fonts.body, .foregroundColor: Colors.text]
        let goodAttr: [NSAttributedString.Key: Any] = [.font: Fonts.bodyBold, .foregroundColor: UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1)]
        let warnAttr: [NSAttributedString.Key: Any] = [.font: Fonts.bodyBold, .foregroundColor: Colors.unsafeOrange]
        let badAttr: [NSAttributedString.Key: Any] = [.font: Fonts.bodyBold, .foregroundColor: Colors.dangerousRed]

        // Count total days in range
        let totalDays = max(1, calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 1)

        let colWidths: [CGFloat] = [Layout.contentWidth * 0.40, Layout.contentWidth * 0.20, Layout.contentWidth * 0.20, Layout.contentWidth * 0.20]

        drawTableHeaderRow(&cursor)
        var x = Layout.margin
        for (i, h) in ["Medication", "Days Taken", "Days Total", "Adherence"].enumerated() {
            h.draw(at: CGPoint(x: x, y: cursor.y), withAttributes: headerAttr)
            x += colWidths[i]
        }
        cursor.y += Layout.rowHeight
        drawTableHeaderSeparator(&cursor)

        for (idx, dose) in dailyDoses.sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() {
            cursor.ensureSpace(Layout.rowHeight)
            drawRowBackground(&cursor, rowIndex: idx, height: Layout.rowHeight)

            // The same predicate as the in-app Adherence screen
            // (`AdherenceCalculator.matches`): route gate AND (identity key
            // OR lowercased-name fallback) — a dose by another route is a
            // journal entry, not adherence credit.
            let daysTaken = Set(
                entries
                    .filter { entry in
                        entry.routeRaw == dose.routeRaw
                            && (
                                (!entry.identityKey.isEmpty && entry.identityKey == dose.identityKey)
                                    || entry.substance.lowercased() == dose.substance.lowercased()
                            )
                    }
                    .map { calendar.sessionDayStart(for: $0.timestamp) },
            ).count

            let pct = totalDays > 0 ? Double(daysTaken) / Double(totalDays) * 100 : 0
            let pctStr = "\(Int(pct))%"
            let pctAttr = pct >= 80 ? goodAttr : (pct >= 50 ? warnAttr : badAttr)

            x = Layout.margin
            dose.substance.draw(at: CGPoint(x: x, y: cursor.y), withAttributes: nameAttr)
            x += colWidths[0]
            "\(daysTaken)".draw(at: CGPoint(x: x, y: cursor.y), withAttributes: rowAttr)
            x += colWidths[1]
            "\(totalDays)".draw(at: CGPoint(x: x, y: cursor.y), withAttributes: rowAttr)
            x += colWidths[2]
            pctStr.draw(at: CGPoint(x: x, y: cursor.y), withAttributes: pctAttr)
            cursor.y += Layout.rowHeight
        }
        cursor.y += Layout.lineSpacing
    }

    // MARK: - Interactions (improved)

    private static func drawInteractions(_ cursor: inout Cursor, interactions: [InteractionSnapshot]) {
        var seen = Set<String>()
        let unique = interactions.filter { i in
            let key = [i.substanceA, i.substanceB].sorted().joined(separator: "|")
            return seen.insert(key).inserted
        }.sorted { $0.severity > $1.severity }

        for interaction in unique {
            let descText = cleanInteractionDescription(interaction.description)

            // Measure description height to know total card height
            let descWidth = Layout.contentWidth - 10
            let descAttr: [NSAttributedString.Key: Any] = [.font: Fonts.caption, .foregroundColor: Colors.secondaryText]
            let descHeight = (descText as NSString).boundingRect(
                with: CGSize(width: descWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: descAttr, context: nil,
            ).height

            // Check if drug classes are available to account for extra line height
            let classesA = interaction.drugClassesA
            let classesB = interaction.drugClassesB
            let classLineHeight: CGFloat = (!classesA.isEmpty || !classesB.isEmpty) ? 12 : 0
            let totalHeight = 16 + classLineHeight + descHeight + 10
            cursor.ensureSpace(totalHeight)

            let bgColor: UIColor
            let severityColor: UIColor
            let severityLabel: String
            let severityDot: String
            switch interaction.severity {
            case .dangerous:
                bgColor = Colors.dangerousBg
                severityColor = Colors.dangerousRed
                severityLabel = "DANGEROUS"
                severityDot = "🔴"
            case .unsafe:
                bgColor = Colors.unsafeBg
                severityColor = Colors.unsafeOrange
                severityLabel = "UNSAFE"
                severityDot = "🟠"
            case .caution:
                bgColor = Colors.cautionBg
                severityColor = Colors.cautionYellow
                severityLabel = "CAUTION"
                severityDot = "🟡"
            }

            // Background card
            let cardRect = CGRect(x: Layout.margin - 4, y: cursor.y - 2, width: Layout.contentWidth + 8, height: totalHeight)
            bgColor.setFill()
            UIBezierPath(roundedRect: cardRect, cornerRadius: 4).fill()

            // Left severity accent border
            let leftBar = CGRect(x: Layout.margin - 4, y: cursor.y - 2, width: 3, height: totalHeight)
            severityColor.setFill()
            UIBezierPath(roundedRect: leftBar, cornerRadius: 1.5).fill()

            // Severity + pair
            let badgeAttr: [NSAttributedString.Key: Any] = [.font: Fonts.bodyBold, .foregroundColor: severityColor]
            let pairAttr: [NSAttributedString.Key: Any] = [.font: Fonts.bodyBold, .foregroundColor: Colors.text]

            "\(severityDot) \(severityLabel)".draw(at: CGPoint(x: Layout.margin, y: cursor.y), withAttributes: badgeAttr)
            let pairText = "\(interaction.substanceA) + \(interaction.substanceB)"
            pairText.draw(at: CGPoint(x: Layout.margin + 110, y: cursor.y), withAttributes: pairAttr)
            cursor.y += 16

            // Drug class labels
            if !classesA.isEmpty || !classesB.isEmpty {
                let classAttr: [NSAttributedString.Key: Any] = [.font: Fonts.caption, .foregroundColor: Colors.secondaryText]
                let classLabelA = classesA.map(\.rawValue.capitalized).joined(separator: ", ")
                let classLabelB = classesB.map(\.rawValue.capitalized).joined(separator: ", ")
                let classText = "\(classLabelA.isEmpty ? "Unknown" : classLabelA)  +  \(classLabelB.isEmpty ? "Unknown" : classLabelB)"
                classText.draw(at: CGPoint(x: Layout.margin + 4, y: cursor.y), withAttributes: classAttr)
                cursor.y += 12
            }

            // Description (cleaned)
            (descText as NSString).draw(
                in: CGRect(x: Layout.margin + 4, y: cursor.y, width: descWidth, height: descHeight + 4),
                withAttributes: descAttr,
            )
            cursor.y += descHeight + 10
        }
    }

    /// Clean up FDA label text that gets cut off or has raw clinical data
    private static func cleanInteractionDescription(_ text: String) -> String {
        var cleaned = text

        // If the text starts with stray fragments (no capital letter start, or starts with drug names/enzymes), it's raw FDA data
        let rawPrefixes = ["dextromethorphan", "quinidine", "fluoxetine", "paroxetine", "venlafaxine", "CYP", "The concomitant"]
        for prefix in rawPrefixes {
            if cleaned.lowercased().hasPrefix(prefix.lowercased()) {
                return "Potential interaction detected via FDA label data. Consult a healthcare provider."
            }
        }

        // Truncate at common FDA label fragments
        let cutoffPatterns = [
            "), CYP", "CYP2D6", "CYP3A4", "CYP2C9",
            "[see Clinical Pharmacology", "[see Dosage",
            "The concomitant use of", ") The concomitant",
            "strong CYP", "inhibitors increased",
        ]
        for pattern in cutoffPatterns {
            if let range = cleaned.range(of: pattern) {
                let prefix = String(cleaned[cleaned.startIndex ..< range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if prefix.count > 15 {
                    cleaned = prefix
                    // Clean trailing punctuation
                    while cleaned.hasSuffix(",") || cleaned.hasSuffix(";") || cleaned.hasSuffix(" or") || cleaned.hasSuffix(" ") {
                        if cleaned.hasSuffix(" or") { cleaned = String(cleaned.dropLast(3)) } else { cleaned = String(cleaned.dropLast()) }
                    }
                    if !cleaned.hasSuffix(".") { cleaned += "." }
                    break
                }
            }
        }

        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " ,;"))
        if cleaned.isEmpty {
            return "Potential interaction detected. Consult a healthcare provider."
        }
        return cleaned
    }

    // MARK: - Duplicate Detection

    private struct DuplicateGroup {
        let names: [String]
        let totalEntries: Int
    }

    private static func findDuplicates(in entries: [EntrySnapshot]) -> [DuplicateGroup] {
        let allNames = Array(Set(entries.map(\.substance)))

        // Known equivalent names (lowercased)
        let equivalences: [[String]] = [
            ["spironolactone", "espironolactone"],
            ["l-theanine", "theanine"],
            ["atomoxetine", "strattera"],
            ["venlafaxine", "effexor"],
            ["aripiprazole", "abilify"],
            ["pregabalin", "lyrica"],
            ["memantine", "namenda"],
            ["tramadol", "ultram"],
            ["dxm", "dextromethorphan"],
            ["5-hydroxytryptophan", "5-htp"],
            ["nac", "n-acetylcysteine", "n-acetyl cysteine"],
            ["curcumin", "turmeric"],
        ]

        var groups: [DuplicateGroup] = []
        var matched = Set<String>()

        for equiv in equivalences {
            let found = allNames.filter { name in
                equiv.contains(name.lowercased())
            }
            if found.count >= 2 {
                let count = entries.count(where: { found.map { $0.lowercased() }.contains($0.substance.lowercased()) })
                groups.append(DuplicateGroup(names: found.sorted(), totalEntries: count))
                found.forEach { matched.insert($0.lowercased()) }
            }
        }

        return groups
    }

    private static func drawDuplicates(_ cursor: inout Cursor, duplicates: [DuplicateGroup]) {
        let noteAttr: [NSAttributedString.Key: Any] = [.font: Fonts.body, .foregroundColor: Colors.text]
        let captionAttr: [NSAttributedString.Key: Any] = [.font: Fonts.caption, .foregroundColor: Colors.secondaryText]

        for (idx, group) in duplicates.enumerated() {
            cursor.ensureSpace(30)
            drawRowBackground(&cursor, rowIndex: idx, height: 28)

            let names = group.names.joined(separator: "  ↔  ")
            "⚠️  \(names)".draw(at: CGPoint(x: Layout.margin, y: cursor.y), withAttributes: noteAttr)
            cursor.y += 14
            "These may be the same substance logged under different names (\(group.totalEntries) total entries)".draw(
                at: CGPoint(x: Layout.margin + 20, y: cursor.y), withAttributes: captionAttr,
            )
            cursor.y += 16
        }
        cursor.y += Layout.lineSpacing
    }

    // MARK: - Substance Summary (with zebra striping)

    private struct SubstanceStat {
        let name: String
        let totalDoses: Int
        let averageDose: Double
        let unit: String
        let route: String
        let firstTaken: Date
        let lastTaken: Date
    }

    private static func buildSubstanceSummary(from entries: [EntrySnapshot]) -> [SubstanceStat] {
        let grouped = Dictionary(grouping: entries) { $0.substance }
        return grouped.map { name, entries in
            let sorted = entries.sorted { $0.timestamp < $1.timestamp }
            let avgDose = (entries.map(\.amount).reduce(0, +) / Double(entries.count))
            let mostCommonUnit = Dictionary(grouping: entries, by: \.unit)
                .max(by: { $0.value.count < $1.value.count })?.key ?? "mg"
            let mostCommonRoute = Dictionary(grouping: entries, by: \.route)
                .max(by: { $0.value.count < $1.value.count })?.key ?? "Oral"
            return SubstanceStat(
                name: name, totalDoses: entries.count, averageDose: avgDose,
                unit: mostCommonUnit, route: mostCommonRoute,
                firstTaken: sorted.first!.timestamp, lastTaken: sorted.last!.timestamp,
            )
        }.sorted { $0.totalDoses > $1.totalDoses }
    }

    private static func drawSubstanceSummary(_ cursor: inout Cursor, summary: [SubstanceStat]) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.locale = Locale(identifier: "en_US")

        let headerAttr: [NSAttributedString.Key: Any] = [.font: Fonts.bodyBold, .foregroundColor: Colors.secondaryText]
        let nameAttr: [NSAttributedString.Key: Any] = [.font: Fonts.bodyBold, .foregroundColor: Colors.text]
        let rowAttr: [NSAttributedString.Key: Any] = [.font: Fonts.body, .foregroundColor: Colors.text]
        let colWidths: [CGFloat] = [
            Layout.contentWidth * 0.30, Layout.contentWidth * 0.12,
            Layout.contentWidth * 0.18, Layout.contentWidth * 0.15,
            Layout.contentWidth * 0.25,
        ]

        drawTableHeaderRow(&cursor)
        var x = Layout.margin
        for (i, h) in ["Substance", "Doses", "Avg Dose", "Route", "Period"].enumerated() {
            h.draw(at: CGPoint(x: x, y: cursor.y), withAttributes: headerAttr)
            x += colWidths[i]
        }
        cursor.y += Layout.rowHeight
        drawTableHeaderSeparator(&cursor)

        for (idx, stat) in summary.enumerated() {
            cursor.ensureSpace(Layout.rowHeight)
            drawRowBackground(&cursor, rowIndex: idx, height: Layout.rowHeight)
            x = Layout.margin
            stat.name.draw(at: CGPoint(x: x, y: cursor.y), withAttributes: nameAttr)
            x += colWidths[0]
            "\(stat.totalDoses)".draw(at: CGPoint(x: x, y: cursor.y), withAttributes: rowAttr)
            x += colWidths[1]
            "\(formatAvgDose(stat.averageDose)) \(stat.unit)".draw(at: CGPoint(x: x, y: cursor.y), withAttributes: rowAttr)
            x += colWidths[2]
            stat.route.draw(at: CGPoint(x: x, y: cursor.y), withAttributes: rowAttr)
            x += colWidths[3]
            "\(dateFormatter.string(from: stat.firstTaken)) – \(dateFormatter.string(from: stat.lastTaken))".draw(
                at: CGPoint(x: x, y: cursor.y), withAttributes: rowAttr,
            )
            cursor.y += Layout.rowHeight
        }
        cursor.y += Layout.lineSpacing
    }

    // MARK: - PK Concentration Chart

    private static func drawPKChart(_ cursor: inout Cursor, substanceName: String, halfLifeMinutes: Double) {
        let chartWidth = Layout.contentWidth
        let chartHeight: CGFloat = 80
        let totalHeight: CGFloat = chartHeight + 30 // title + chart + bottom margin
        cursor.ensureSpace(totalHeight)

        // Title
        let titleAttr: [NSAttributedString.Key: Any] = [.font: Fonts.bodyBold, .foregroundColor: Colors.text]
        substanceName.draw(at: CGPoint(x: Layout.margin, y: cursor.y), withAttributes: titleAttr)

        // Half-life label
        let hlText = formatHalfLifeLabel(halfLifeMinutes)
        let hlAttr: [NSAttributedString.Key: Any] = [.font: Fonts.caption, .foregroundColor: Colors.secondaryText]
        let hlSize = (hlText as NSString).size(withAttributes: hlAttr)
        hlText.draw(at: CGPoint(x: Layout.margin + chartWidth - hlSize.width, y: cursor.y + 2), withAttributes: hlAttr)
        cursor.y += 16

        let chartOriginX = Layout.margin
        let chartOriginY = cursor.y

        // PK model parameters
        let ke = PKModel.ke(fromHalfLifeMinutes: halfLifeMinutes)
        let ka = PKModel.defaultKa(ke: ke)
        let cmaxVal = PKModel.cmax(ke: ke, ka: ka)
        guard cmaxVal > 0 else {
            cursor.y += chartHeight + 10
            return
        }

        // Determine time range: out to 5% of Cmax on descending side
        let totalMinutes = PKModel.timeToFraction(0.05, ke: ke, ka: ka)
        guard totalMinutes > 0 else {
            cursor.y += chartHeight + 10
            return
        }

        // Grid background
        let gridRect = CGRect(x: chartOriginX, y: chartOriginY, width: chartWidth, height: chartHeight)
        Colors.zebraStripe.setFill()
        UIBezierPath(roundedRect: gridRect, cornerRadius: 3).fill()

        // Horizontal grid lines (25%, 50%, 75%, 100%)
        let gridPath = UIBezierPath()
        Colors.lightGray.setStroke()
        gridPath.lineWidth = 0.5
        for fraction in [0.25, 0.5, 0.75, 1.0] {
            let gy = chartOriginY + chartHeight - (CGFloat(fraction) * chartHeight)
            gridPath.move(to: CGPoint(x: chartOriginX, y: gy))
            gridPath.addLine(to: CGPoint(x: chartOriginX + chartWidth, y: gy))
        }
        gridPath.stroke()

        // Y-axis percentage labels
        let yLabelAttr: [NSAttributedString.Key: Any] = [.font: Fonts.caption, .foregroundColor: Colors.secondaryText]
        for (fraction, label) in [(1.0, "100%"), (0.5, "50%")] as [(Double, String)] {
            let gy = chartOriginY + chartHeight - (CGFloat(fraction) * chartHeight)
            label.draw(at: CGPoint(x: chartOriginX + 2, y: gy), withAttributes: yLabelAttr)
        }

        // Vertical grid lines and hour labels
        let hourIntervalMinutes = bestHourInterval(totalMinutes: totalMinutes)
        var gridMinutes = hourIntervalMinutes
        while gridMinutes < totalMinutes {
            let gx = chartOriginX + CGFloat(gridMinutes / totalMinutes) * chartWidth
            let vLine = UIBezierPath()
            Colors.lightGray.setStroke()
            vLine.lineWidth = 0.5
            vLine.move(to: CGPoint(x: gx, y: chartOriginY))
            vLine.addLine(to: CGPoint(x: gx, y: chartOriginY + chartHeight))
            vLine.stroke()

            let hourLabel = formatTimeLabel(gridMinutes)
            let labelSize = (hourLabel as NSString).size(withAttributes: yLabelAttr)
            hourLabel.draw(
                at: CGPoint(x: gx - labelSize.width / 2, y: chartOriginY + chartHeight + 1),
                withAttributes: yLabelAttr,
            )
            gridMinutes += hourIntervalMinutes
        }

        // Draw PK curve
        let curvePath = UIBezierPath()
        let steps = 200
        for i in 0 ... steps {
            let t = totalMinutes * Double(i) / Double(steps)
            let c = PKModel.concentration(at: t, ke: ke, ka: ka) / cmaxVal
            let px = chartOriginX + CGFloat(t / totalMinutes) * chartWidth
            let py = chartOriginY + chartHeight - CGFloat(c) * chartHeight
            if i == 0 {
                curvePath.move(to: CGPoint(x: px, y: py))
            } else {
                curvePath.addLine(to: CGPoint(x: px, y: py))
            }
        }
        Colors.accent.setStroke()
        curvePath.lineWidth = 1.5
        curvePath.lineCapStyle = .round
        curvePath.lineJoinStyle = .round
        curvePath.stroke()

        // Filled area under curve
        let fillPath = UIBezierPath()
        fillPath.move(to: CGPoint(x: chartOriginX, y: chartOriginY + chartHeight))
        for i in 0 ... steps {
            let t = totalMinutes * Double(i) / Double(steps)
            let c = PKModel.concentration(at: t, ke: ke, ka: ka) / cmaxVal
            let px = chartOriginX + CGFloat(t / totalMinutes) * chartWidth
            let py = chartOriginY + chartHeight - CGFloat(c) * chartHeight
            fillPath.addLine(to: CGPoint(x: px, y: py))
        }
        fillPath.addLine(to: CGPoint(x: chartOriginX + chartWidth, y: chartOriginY + chartHeight))
        fillPath.close()
        Colors.accentLight.setFill()
        fillPath.fill()

        // Border around chart
        let borderPath = UIBezierPath(roundedRect: gridRect, cornerRadius: 3)
        Colors.lightGray.setStroke()
        borderPath.lineWidth = 0.5
        borderPath.stroke()

        cursor.y += chartHeight + 18
    }

    /// Choose a sensible hour-grid interval based on the total time range.
    private static func bestHourInterval(totalMinutes: Double) -> Double {
        let totalHours = totalMinutes / 60
        if totalHours <= 6 { return 60 } // every 1h
        if totalHours <= 24 { return 120 } // every 2h
        if totalHours <= 48 { return 360 } // every 6h
        if totalHours <= 168 { return 1_440 } // every 24h
        return 2_880 // every 48h
    }

    /// Format a time in minutes as a concise label (e.g. "2h", "12h", "2d").
    private static func formatTimeLabel(_ minutes: Double) -> String {
        let hours = minutes / 60
        if hours < 24 {
            return hours.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(hours))h"
                : String(format: "%.1fh", hours)
        }
        let days = hours / 24
        return days.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(days))d"
            : String(format: "%.1fd", days)
    }

    /// Format half-life as a human-readable string.
    private static func formatHalfLifeLabel(_ minutes: Double) -> String {
        if minutes < 60 {
            return "t\u{00BD} = \(Int(minutes)) min"
        }
        let hours = minutes / 60
        if hours < 24 {
            return hours.truncatingRemainder(dividingBy: 1) == 0
                ? "t\u{00BD} = \(Int(hours))h"
                : String(format: "t\u{00BD} = %.1fh", hours)
        }
        let days = hours / 24
        return days.truncatingRemainder(dividingBy: 1) == 0
            ? "t\u{00BD} = \(Int(days))d"
            : String(format: "t\u{00BD} = %.1fd", days)
    }

    // MARK: - Usage Log (bold substance names)

    private static func drawUsageLog(_ cursor: inout Cursor, entries: [EntrySnapshot]) {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.sessionDayStart(for: $0.timestamp) }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE, MMM d, yyyy"
        dayFormatter.locale = Locale(identifier: "en_US")

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        timeFormatter.locale = Locale(identifier: "en_US")

        let dayAttr: [NSAttributedString.Key: Any] = [.font: Fonts.bodyBold, .foregroundColor: Colors.accent]
        let timeAttr: [NSAttributedString.Key: Any] = [.font: Fonts.body, .foregroundColor: Colors.secondaryText]
        let nameAttr: [NSAttributedString.Key: Any] = [.font: Fonts.bodyBold, .foregroundColor: Colors.text]
        let doseAttr: [NSAttributedString.Key: Any] = [.font: Fonts.body, .foregroundColor: Colors.text]
        let noteAttr: [NSAttributedString.Key: Any] = [.font: Fonts.caption, .foregroundColor: Colors.secondaryText]

        for day in grouped.keys.sorted(by: >) {
            let dayEntries = grouped[day]!.sorted { $0.timestamp < $1.timestamp }
            cursor.ensureSpace(CGFloat(24 + dayEntries.count * 16))

            let dayText = dayFormatter.string(from: day)
            let daySize = (dayText as NSString).size(withAttributes: dayAttr)
            let dayBgRect = CGRect(x: Layout.margin - 4, y: cursor.y - 2, width: daySize.width + 12, height: daySize.height + 4)
            Colors.accentLight.setFill()
            UIBezierPath(roundedRect: dayBgRect, cornerRadius: 3).fill()
            dayText.draw(at: CGPoint(x: Layout.margin + 2, y: cursor.y), withAttributes: dayAttr)
            cursor.y += 20

            for (idx, entry) in dayEntries.enumerated() {
                cursor.ensureSpace(18)
                drawRowBackground(&cursor, rowIndex: idx, height: 15)

                let time = timeFormatter.string(from: entry.timestamp)
                var xPos = Layout.margin + 10

                // Time
                time.draw(at: CGPoint(x: xPos, y: cursor.y), withAttributes: timeAttr)
                xPos += 65

                // Dash
                "—".draw(at: CGPoint(x: xPos, y: cursor.y), withAttributes: timeAttr)
                xPos += 15

                // Bold substance name
                let nameStr = entry.substance as NSString
                nameStr.draw(at: CGPoint(x: xPos, y: cursor.y), withAttributes: nameAttr)
                xPos += nameStr.size(withAttributes: nameAttr).width + 6

                // Dose info
                "\(entry.amount.doseFormatted) \(entry.unit) (\(entry.route))".draw(
                    at: CGPoint(x: xPos, y: cursor.y), withAttributes: doseAttr,
                )
                cursor.y += 14

                if let notes = entry.notes, !notes.isEmpty {
                    notes.draw(at: CGPoint(x: Layout.margin + 20, y: cursor.y), withAttributes: noteAttr)
                    cursor.y += 12
                }
            }
            cursor.y += 8
        }
    }

    // MARK: - Footer

    private static func drawFooter(_ cursor: inout Cursor) {
        let disclaimerText = "This report was generated by Piru for informational and harm reduction purposes. It is not medical advice. Always consult a qualified healthcare provider regarding substance use and medication management."
        let attr: [NSAttributedString.Key: Any] = [.font: Fonts.caption, .foregroundColor: Colors.secondaryText]
        let textHeight = (disclaimerText as NSString).boundingRect(
            with: CGSize(width: Layout.contentWidth - 16, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attr, context: nil,
        ).height

        cursor.ensureSpace(textHeight + 36)
        cursor.y += 16

        // Disclaimer box
        let boxRect = CGRect(x: Layout.margin - 4, y: cursor.y, width: Layout.contentWidth + 8, height: textHeight + 16)
        Colors.zebraStripe.setFill()
        UIBezierPath(roundedRect: boxRect, cornerRadius: 4).fill()
        Colors.lightGray.setStroke()
        UIBezierPath(roundedRect: boxRect, cornerRadius: 4).stroke()

        cursor.y += 8
        (disclaimerText as NSString).draw(
            in: CGRect(x: Layout.margin + 4, y: cursor.y, width: Layout.contentWidth - 16, height: textHeight + 4),
            withAttributes: attr,
        )
        cursor.y += textHeight + 12
    }

    // MARK: - Utilities

    private static func drawWrappedText(_ cursor: inout Cursor, text: String, font: UIFont, color: UIColor, indent: CGFloat = 0, maxWidth: CGFloat? = nil) {
        let width = (maxWidth ?? Layout.contentWidth) - indent
        let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let nsText = text as NSString
        let boundingRect = nsText.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attr, context: nil,
        )
        cursor.ensureSpace(boundingRect.height + 4)
        nsText.draw(
            in: CGRect(x: Layout.margin + indent, y: cursor.y, width: width, height: boundingRect.height + 4),
            withAttributes: attr,
        )
        cursor.y += boundingRect.height + 4
    }

    private static func formatAvgDose(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "%.0f", value.rounded())
        } else if value >= 10 {
            return ((value * 10).rounded() / 10).doseFormatted
        }
        return value.doseFormatted
    }
}
