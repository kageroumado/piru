import SwiftData
import UIKit

/// Generates a beautiful shareable image of a day's dose log
enum DayLogImageExporter {
    // MARK: - Layout
    
    private enum Layout {
        static let width: CGFloat = 390 // iPhone-width image
        static let padding: CGFloat = 24
        static let cornerRadius: CGFloat = 20
        static let entrySpacing: CGFloat = 12
        static let sectionSpacing: CGFloat = 20
    }

    /// Point width the caller should render the timeline snapshot at, so it
    /// drops into the export's content column without rescaling artifacts.
    static let timelineWidth: CGFloat = Layout.width - Layout.padding * 2
    
    private enum Palette {
        // Dark theme (matches Piru's OLED dark mode)
        static let background = UIColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1)
        static let cardBg = UIColor(red: 0.09, green: 0.09, blue: 0.09, alpha: 1)
        static let accent = UIColor(red: 0.93, green: 0.34, blue: 0.53, alpha: 1) // Piru pink
        static let text = UIColor.white
        static let secondaryText = UIColor(white: 0.6, alpha: 1)
        static let tertiaryText = UIColor(white: 0.4, alpha: 1)
        static let divider = UIColor(white: 0.15, alpha: 1)
        
        /// Dose level colors
        static func doseLevelColor(_ level: DoseLevel) -> UIColor {
            switch level {
            case .sub: UIColor(white: 0.5, alpha: 1)
            case .threshold: UIColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1)
            case .light: UIColor(red: 0.3, green: 0.8, blue: 0.4, alpha: 1)
            case .common: UIColor(red: 0.9, green: 0.8, blue: 0.2, alpha: 1)
            case .strong: UIColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1)
            case .heavy: UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1)
            }
        }
        
        static func categoryColor(_ category: SubstanceCategory) -> UIColor {
            switch category {
            case .stimulant: UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1)
            case .psychedelic: UIColor(red: 0.6, green: 0.3, blue: 0.9, alpha: 1)
            case .dissociative: UIColor(red: 0.2, green: 0.8, blue: 0.8, alpha: 1)
            case .opioid: UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1)
            case .benzodiazepine: UIColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1)
            case .gabapentinoid: UIColor(red: 0.35, green: 0.3, blue: 0.8, alpha: 1)
            case .empathogen: UIColor(red: 1.0, green: 0.4, blue: 0.6, alpha: 1)
            case .cannabinoid: UIColor(red: 0.3, green: 0.75, blue: 0.35, alpha: 1)
            case .depressant: UIColor(red: 0.45, green: 0.55, blue: 0.72, alpha: 1)
            case .antidepressant: UIColor(red: 0.9, green: 0.8, blue: 0.2, alpha: 1)
            default: accent
            }
        }
    }
    
    private enum Fonts {
        static let title = UIFont.systemFont(ofSize: 22, weight: .bold)
        static let subtitle = UIFont.systemFont(ofSize: 13, weight: .regular)
        static let sectionHeader = UIFont.systemFont(ofSize: 11, weight: .semibold)
        static let substanceName = UIFont.systemFont(ofSize: 16, weight: .semibold)
        static let doseText = UIFont.systemFont(ofSize: 14, weight: .medium)
        static let detailText = UIFont.systemFont(ofSize: 12, weight: .regular)
        static let timeText = UIFont.systemFont(ofSize: 12, weight: .medium)
        static let caption = UIFont.systemFont(ofSize: 10, weight: .regular)
        static let tagText = UIFont.systemFont(ofSize: 10, weight: .medium)
        static let totalLabel = UIFont.systemFont(ofSize: 13, weight: .semibold)
        static let totalValue = UIFont.systemFont(ofSize: 15, weight: .bold)
        static let watermark = UIFont.systemFont(ofSize: 10, weight: .light)
    }
    
    // MARK: - Entry Data
    
    struct EntryData {
        let substance: String
        let amount: Double
        let unit: String
        let route: RouteOfAdministration
        let timestamp: Date
        let notes: String?
        let tags: [String]
        let category: SubstanceCategory?
        let doseLevel: DoseLevel?
        let colorHex: String?
    }
    
    struct DaySummary {
        let totalEntries: Int
        let uniqueSubstances: Int
        let firstDose: Date?
        let lastDose: Date?
        let cumulativeDoses: [(substance: String, total: Double, unit: String, count: Int)]
    }
    
    // MARK: - Generation
    
    @MainActor
    static func generateImage(
        date: Date,
        entries: [EntryData],
        timeline: UIImage? = nil,
    ) -> UIImage? {
        let entryData = entries.sorted(by: { $0.timestamp < $1.timestamp })

        guard !entryData.isEmpty else { return nil }

        // Build summary
        let summary = buildSummary(entries: entryData)

        // Calculate image height
        let height = calculateHeight(entries: entryData, summary: summary, timeline: timeline)
        let size = CGSize(width: Layout.width, height: height)

        // Render
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let context = ctx.cgContext
            drawImage(context: context, size: size, date: date, entries: entryData, summary: summary, timeline: timeline)
        }
    }

    /// Drawn height of the timeline snapshot once fitted to the content column,
    /// preserving its rendered aspect ratio. Zero when there's no snapshot.
    private static func timelineHeight(_ timeline: UIImage?) -> CGFloat {
        guard let timeline, timeline.size.width > 0 else { return 0 }
        let contentWidth = Layout.width - Layout.padding * 2
        return (contentWidth * timeline.size.height / timeline.size.width).rounded()
    }
    
    // MARK: - Height Calculation
    
    private static func calculateHeight(entries: [EntryData], summary: DaySummary, timeline: UIImage?) -> CGFloat {
        var h: CGFloat = Layout.padding // top padding
        h += 60 // header (title + subtitle)
        h += Layout.sectionSpacing

        // Summary card
        h += 80
        h += Layout.sectionSpacing

        // Timeline snapshot (if the graph was expanded)
        let timelineH = timelineHeight(timeline)
        if timelineH > 0 {
            h += timelineH
            h += Layout.sectionSpacing
        }

        // Cumulative doses (if any)
        if !summary.cumulativeDoses.isEmpty {
            h += 24 // section header
            h += CGFloat(summary.cumulativeDoses.count) * 28
            h += Layout.sectionSpacing
        }
        
        // Entries section header
        h += 24
        
        // Each entry card
        for entry in entries {
            h += entryCardHeight(entry)
            h += Layout.entrySpacing
        }
        
        h += Layout.sectionSpacing
        h += 30 // watermark
        h += Layout.padding // bottom padding
        
        return h
    }
    
    private static func entryCardHeight(_ entry: EntryData) -> CGFloat {
        var h: CGFloat = 16 // top padding
        h += 20 // substance name
        h += 4
        h += 18 // dose + route
        if entry.notes != nil, !(entry.notes?.isEmpty ?? true) {
            h += 4
            h += 16 // notes
        }
        if !entry.tags.isEmpty {
            h += 4
            h += 20 // tags
        }
        h += 16 // bottom padding
        return h
    }
    
    // MARK: - Drawing
    
    private static func drawImage(
        context: CGContext,
        size: CGSize,
        date: Date,
        entries: [EntryData],
        summary: DaySummary,
        timeline: UIImage?,
    ) {
        let rect = CGRect(origin: .zero, size: size)
        
        // Background
        context.setFillColor(Palette.background.cgColor)
        context.fill(rect)
        
        // Subtle gradient overlay
        let gradientColors = [
            UIColor(red: 0.93, green: 0.34, blue: 0.53, alpha: 0.03).cgColor,
            UIColor.clear.cgColor,
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: gradientColors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        
        var y: CGFloat = Layout.padding
        let x = Layout.padding
        let contentWidth = size.width - Layout.padding * 2
        
        // ── Header ──
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMMM d, yyyy"
        let dateString = dateFormatter.string(from: date)
        
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: Fonts.title,
            .foregroundColor: Palette.text,
        ]
        let titleStr = NSAttributedString(string: "Daily Log", attributes: titleAttrs)
        titleStr.draw(at: CGPoint(x: x, y: y))
        y += 28
        
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: Fonts.subtitle,
            .foregroundColor: Palette.secondaryText,
        ]
        let subtitleStr = NSAttributedString(string: dateString, attributes: subtitleAttrs)
        subtitleStr.draw(at: CGPoint(x: x, y: y))
        y += 20
        
        // Pink accent line
        context.setFillColor(Palette.accent.cgColor)
        context.fill(CGRect(x: x, y: y, width: 40, height: 2))
        y += Layout.sectionSpacing
        
        // ── Summary Card ──
        let summaryRect = CGRect(x: x, y: y, width: contentWidth, height: 72)
        drawRoundedRect(context: context, rect: summaryRect, radius: 12, color: Palette.cardBg)
        
        let colWidth = contentWidth / 4
        let summaryItems: [(String, String)] = [
            ("\(summary.totalEntries)", "doses"),
            ("\(summary.uniqueSubstances)", "substances"),
            (summary.firstDose.map { formatTime($0) } ?? "—", "first"),
            (summary.lastDose.map { formatTime($0) } ?? "—", "last"),
        ]
        
        for (i, item) in summaryItems.enumerated() {
            let colX = x + CGFloat(i) * colWidth
            let centerX = colX + colWidth / 2
            
            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: Fonts.totalValue,
                .foregroundColor: Palette.accent,
            ]
            let valueStr = NSAttributedString(string: item.0, attributes: valueAttrs)
            let valueSize = valueStr.size()
            valueStr.draw(at: CGPoint(x: centerX - valueSize.width / 2, y: y + 16))
            
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: Fonts.caption,
                .foregroundColor: Palette.tertiaryText,
            ]
            let labelStr = NSAttributedString(string: item.1, attributes: labelAttrs)
            let labelSize = labelStr.size()
            labelStr.draw(at: CGPoint(x: centerX - labelSize.width / 2, y: y + 42))
        }
        
        y += 72 + Layout.sectionSpacing

        // ── Timeline ──
        let timelineH = timelineHeight(timeline)
        if let timeline, timelineH > 0 {
            let tRect = CGRect(x: x, y: y, width: contentWidth, height: timelineH)
            context.saveGState()
            context.addPath(UIBezierPath(roundedRect: tRect, cornerRadius: 12).cgPath)
            context.clip()
            timeline.draw(in: tRect)
            context.restoreGState()
            y += timelineH + Layout.sectionSpacing
        }

        // ── Cumulative Doses ──
        if !summary.cumulativeDoses.isEmpty {
            drawSectionHeader(context: context, text: "CUMULATIVE TOTALS", x: x, y: y)
            y += 24
            
            for dose in summary.cumulativeDoses {
                let nameAttrs: [NSAttributedString.Key: Any] = [
                    .font: Fonts.detailText,
                    .foregroundColor: Palette.text,
                ]
                let nameStr = NSAttributedString(string: dose.substance, attributes: nameAttrs)
                nameStr.draw(at: CGPoint(x: x + 8, y: y + 4))
                
                let totalStr = NSAttributedString(
                    string: "\(dose.total.doseFormatted) \(dose.unit) (\(dose.count)×)",
                    attributes: [
                        .font: Fonts.totalLabel,
                        .foregroundColor: Palette.accent,
                    ],
                )
                let totalSize = totalStr.size()
                totalStr.draw(at: CGPoint(x: x + contentWidth - totalSize.width - 8, y: y + 3))
                
                y += 28
            }
            
            y += Layout.sectionSpacing
        }
        
        // ── Entries ──
        drawSectionHeader(context: context, text: "TIMELINE", x: x, y: y)
        y += 24
        
        for (index, entry) in entries.enumerated() {
            let cardHeight = entryCardHeight(entry)
            let cardRect = CGRect(x: x, y: y, width: contentWidth, height: cardHeight)
            
            // Card background
            drawRoundedRect(context: context, rect: cardRect, radius: 12, color: Palette.cardBg)
            
            // Color accent bar on left
            let accentColor: UIColor = if let hex = entry.colorHex {
                UIColor(hex: hex)
            } else if let category = entry.category {
                Palette.categoryColor(category)
            } else {
                Palette.accent
            }
            
            let barRect = CGRect(x: x, y: y, width: 4, height: cardHeight)
            let barPath = UIBezierPath(
                roundedRect: barRect,
                byRoundingCorners: [.topLeft, .bottomLeft],
                cornerRadii: CGSize(width: 12, height: 12),
            )
            context.saveGState()
            barPath.addClip()
            context.setFillColor(accentColor.cgColor)
            context.fill(barRect)
            context.restoreGState()
            
            var innerY = y + 16
            let innerX = x + 16
            let innerWidth = contentWidth - 32
            
            // Time on the right
            let timeStr = NSAttributedString(
                string: formatTime(entry.timestamp),
                attributes: [.font: Fonts.timeText, .foregroundColor: Palette.secondaryText],
            )
            let timeSize = timeStr.size()
            timeStr.draw(at: CGPoint(x: x + contentWidth - timeSize.width - 16, y: innerY))
            
            // Substance name
            let nameAttrs: [NSAttributedString.Key: Any] = [
                .font: Fonts.substanceName,
                .foregroundColor: Palette.text,
            ]
            let nameStr = NSAttributedString(string: entry.substance, attributes: nameAttrs)
            nameStr.draw(at: CGPoint(x: innerX, y: innerY))
            innerY += 24
            
            // Dose + route + level
            var doseString = "\(entry.amount.doseFormatted) \(entry.unit) — \(String(localized: entry.route.localizedName))"
            if let level = entry.doseLevel {
                doseString += " (\(String(localized: level.displayName)))"
            }
            
            let doseAttrs: [NSAttributedString.Key: Any] = [
                .font: Fonts.doseText,
                .foregroundColor: entry.doseLevel.map { Palette.doseLevelColor($0) } ?? Palette.secondaryText,
            ]
            let doseStr = NSAttributedString(string: doseString, attributes: doseAttrs)
            doseStr.draw(at: CGPoint(x: innerX, y: innerY))
            innerY += 22
            
            // Notes
            if let notes = entry.notes, !notes.isEmpty {
                let notesAttrs: [NSAttributedString.Key: Any] = [
                    .font: Fonts.detailText,
                    .foregroundColor: Palette.tertiaryText,
                ]
                let notesStr = NSAttributedString(string: "💬 \(notes)", attributes: notesAttrs)
                notesStr.draw(in: CGRect(x: innerX, y: innerY, width: innerWidth, height: 16))
                innerY += 20
            }
            
            // Tags
            if !entry.tags.isEmpty {
                var tagX = innerX
                for tag in entry.tags {
                    let tagAttrs: [NSAttributedString.Key: Any] = [
                        .font: Fonts.tagText,
                        .foregroundColor: Palette.accent,
                    ]
                    let tagStr = NSAttributedString(string: "#\(tag)", attributes: tagAttrs)
                    let tagSize = tagStr.size()
                    let tagWidth = tagSize.width + 12
                    
                    // Tag pill background
                    let tagRect = CGRect(x: tagX, y: innerY, width: tagWidth, height: 18)
                    drawRoundedRect(context: context, rect: tagRect, radius: 9, color: Palette.accent.withAlphaComponent(0.15))
                    tagStr.draw(at: CGPoint(x: tagX + 6, y: innerY + 2))
                    
                    tagX += tagWidth + 6
                    if tagX > x + contentWidth - 32 { break }
                }
            }
            
            // Timeline connector line between cards
            if index < entries.count - 1 {
                let lineX = x + 2
                context.setStrokeColor(Palette.divider.cgColor)
                context.setLineWidth(1)
                context.setLineDash(phase: 0, lengths: [3, 3])
                context.move(to: CGPoint(x: lineX, y: y + cardHeight))
                context.addLine(to: CGPoint(x: lineX, y: y + cardHeight + Layout.entrySpacing))
                context.strokePath()
                context.setLineDash(phase: 0, lengths: [])
            }
            
            y += cardHeight + Layout.entrySpacing
        }
        
        y += Layout.sectionSpacing
        
        // ── Watermark ──
        let watermarkAttrs: [NSAttributedString.Key: Any] = [
            .font: Fonts.watermark,
            .foregroundColor: Palette.tertiaryText,
        ]
        let watermarkStr = NSAttributedString(string: "Generated by Piru • kagerou.glass/piru", attributes: watermarkAttrs)
        let wmSize = watermarkStr.size()
        watermarkStr.draw(at: CGPoint(x: size.width / 2 - wmSize.width / 2, y: y))
    }
    
    // MARK: - Helpers
    
    private static func buildSummary(entries: [EntryData]) -> DaySummary {
        var grouped: [String: (total: Double, unit: String, count: Int)] = [:]
        for entry in entries {
            let key = entry.substance.lowercased()
            if let existing = grouped[key] {
                grouped[key] = (total: existing.total + entry.amount, unit: existing.unit, count: existing.count + 1)
            } else {
                grouped[key] = (total: entry.amount, unit: entry.unit, count: 1)
            }
        }
        
        let cumulative = grouped
            .filter { $0.value.count > 1 }
            .map { (substance: $0.key.capitalized, total: $0.value.total, unit: $0.value.unit, count: $0.value.count) }
            .sorted { $0.substance < $1.substance }
        
        return DaySummary(
            totalEntries: entries.count,
            uniqueSubstances: Set(entries.map { $0.substance.lowercased() }).count,
            firstDose: entries.first?.timestamp,
            lastDose: entries.last?.timestamp,
            cumulativeDoses: cumulative,
        )
    }
    
    private static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    
    private static func drawRoundedRect(context: CGContext, rect: CGRect, radius: CGFloat, color: UIColor) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        context.saveGState()
        context.setFillColor(color.cgColor)
        path.addClip()
        context.fill(rect)
        context.restoreGState()
    }
    
    private static func drawSectionHeader(context _: CGContext, text: String, x: CGFloat, y: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Fonts.sectionHeader,
            .foregroundColor: Palette.tertiaryText,
            .kern: 1.5,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        str.draw(at: CGPoint(x: x, y: y))
    }
}
