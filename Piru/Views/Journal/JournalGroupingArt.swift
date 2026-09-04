import SwiftUI

/// The groupings' screen sketches for ``MenuPhoneThumbnail`` — each view's list
/// shape reduced to line art matching the real journal layouts: day-grouped
/// sessions in rounded cards, the timeline's axis-and-bubbles, and collapsible
/// section headers over indented rows.
enum JournalGroupingArt {
    static func sketch(for grouping: JournalGrouping) -> (GraphicsContext, CGRect, Color) -> Void {
        switch grouping {
        case .byDay: drawDayGroups
        case .timeline: drawTimelineSpine
        case .grouped: drawSectionGroups
        }
    }

    /// A vertical axis on the left with dose dots, connector lines reaching
    /// right into rounded card rows — the timeline's three-column shape.
    private static func drawTimelineSpine(_ context: GraphicsContext, in rect: CGRect, color: Color) {
        let unit = rect.height / 26
        let axisX = rect.minX + unit * 3
        // The time axis
        var axis = Path()
        axis.move(to: CGPoint(x: axisX, y: rect.minY))
        axis.addLine(to: CGPoint(x: axisX, y: rect.maxY))
        context.stroke(axis, with: .color(color.opacity(0.35)), lineWidth: 0.8)
        // Dose dots + connectors + card rows
        let cardX = rect.minX + unit * 7
        let cardW = rect.maxX - cardX
        for (index, dotY) in [rect.minY + unit * 3, rect.minY + unit * 11, rect.minY + unit * 20].enumerated() {
            let cardY = dotY + (index == 1 ? unit * 2.5 : 0)
            context.fill(
                Path(ellipseIn: CGRect(x: axisX - unit, y: dotY - unit, width: unit * 2, height: unit * 2)),
                with: .color(color),
            )
            var connector = Path()
            connector.move(to: CGPoint(x: axisX + unit, y: dotY))
            connector.addLine(to: CGPoint(x: cardX, y: cardY + unit * 2))
            context.stroke(connector, with: .color(color.opacity(Theme.Opacity.muted)), lineWidth: 0.6)
            let cardRect = CGRect(x: cardX, y: cardY, width: cardW, height: unit * 4)
            context.stroke(Path(roundedRect: cardRect, cornerRadius: unit), with: .color(color.opacity(Theme.Opacity.dimmed)), lineWidth: 0.6)
            line(context, x: cardX + unit, y: cardY + unit * 1.2, width: cardW * 0.5, height: unit * 0.9, color: color.opacity(0.7))
        }
    }

    /// A thin header line (date), then a rounded card containing session rows
    /// separated by hairlines — twice (two "days"). Mirrors the real layout
    /// where each day is a date header + a `.themeCard()`
    /// containing `SessionCardView` rows.
    private static func drawDayGroups(_ context: GraphicsContext, in rect: CGRect, color: Color) {
        let unit = rect.height / 26
        for groupTop in [rect.minY, rect.minY + unit * 14] {
            // Date header ("Aug 28 Wed")
            line(context, x: rect.minX + unit, y: groupTop, width: rect.width * 0.5, height: unit * 1.2, color: color)
            // Rounded card container
            let cardTop = groupTop + unit * 2.2
            let cardHeight = unit * 9
            let cardRadius = unit * 1.4
            let cardRect = CGRect(x: rect.minX, y: cardTop, width: rect.width, height: cardHeight)
            context.stroke(Path(roundedRect: cardRect, cornerRadius: cardRadius), with: .color(color.opacity(0.3)), lineWidth: 0.5)
            // Session rows inside the card
            let inset = unit * 1.2
            for row in 0 ..< 2 {
                let rowY = cardTop + inset + CGFloat(row) * (cardHeight - inset * 2) * 0.5
                line(context, x: rect.minX + inset, y: rowY, width: rect.width - inset * 2, height: unit * 1.2, color: color.opacity(0.7))
                line(context, x: rect.minX + inset, y: rowY + unit * 1.8, width: (rect.width - inset * 2) * 0.65, height: unit * 0.9, color: color.opacity(0.35))
            }
            // Hairline divider between rows
            let divY = cardTop + cardHeight * 0.5
            line(context, x: rect.minX + inset, y: divY, width: rect.width - inset * 2, height: 0.5, color: color.opacity(0.15))
        }
    }

    /// A bold section header line with a trailing chevron, then indented entry
    /// rows — twice (two groups). The header stands for the substance or
    /// category the section collapses under; the indent is the group's rows.
    private static func drawSectionGroups(_ context: GraphicsContext, in rect: CGRect, color: Color) {
        let unit = rect.height / 26
        for groupTop in [rect.minY, rect.minY + unit * 14] {
            // Section header
            line(context, x: rect.minX, y: groupTop, width: rect.width * 0.55, height: unit * 1.6, color: color)
            // Chevron placeholder (right side)
            let chevSize = unit * 1.2
            line(context, x: rect.maxX - chevSize, y: groupTop + (unit * 1.6 - chevSize) / 2, width: chevSize, height: chevSize, color: color.opacity(0.3))
            // Indented entry rows
            let indent = unit * 2.4
            for row in 0 ..< 2 {
                let y = groupTop + unit * (4 + CGFloat(row) * 3.8)
                line(context, x: rect.minX + indent, y: y, width: rect.width - indent, height: unit * 1.2, color: color.opacity(Theme.Opacity.dimmed))
                line(context, x: rect.minX + indent, y: y + unit * 1.6, width: (rect.width - indent) * 0.45, height: unit * 0.8, color: color.opacity(Theme.Opacity.emphasis))
            }
        }
    }

    private static func line(_ context: GraphicsContext, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, color: Color) {
        context.fill(
            Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: height / 2),
            with: .color(color),
        )
    }
}
