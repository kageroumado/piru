import SwiftUI
import UIKit

/// Renders a session as a shareable image by composing the app's **real** views —
/// the timeline graph plus `EntryRowView` rows inside insetGrouped-style cards —
/// so the export is visually identical to the on-screen session, not a bespoke
/// redraw. Long sessions flow into two columns. Replaces the old Core-Graphics
/// `DayLogImageExporter`.
@MainActor
enum SessionShareImage {
    /// Row count past which the entry list splits into two columns.
    static let twoColumnThreshold = 8

    static func render(
        title: String,
        dateText: String,
        entries: [DoseEntry],
        colors: [SubstanceColor],
        stackRedoses: Bool,
        scheme: ColorScheme,
        capturedAt: Date = .now,
    ) -> UIImage? {
        guard !entries.isEmpty else { return nil }
        let displays = DayEntryDisplay.make(from: entries, colors: colors)
        let (states, markers) = ActiveSubstanceState.timeline(for: entries, colors: colors)
        let card = SessionShareCard(
            title: title,
            dateText: dateText,
            capturedAt: capturedAt,
            displays: displays,
            states: states,
            markers: markers,
            stackRedoses: stackRedoses,
            scheme: scheme,
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }
}

struct SessionShareCard: View {
    let title: String
    let dateText: String
    let capturedAt: Date
    let displays: [DayEntryDisplay]
    let states: [ActiveSubstanceState]
    let markers: [DoseMarker]
    let stackRedoses: Bool
    let scheme: ColorScheme

    private var twoColumn: Bool {
        displays.count > SessionShareImage.twoColumnThreshold
    }
    private var cardWidth: CGFloat {
        twoColumn ? 740 : 390
    }
    private var contentWidth: CGFloat {
        cardWidth - 40
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            timeline
            entriesSection
            cumulativeSection
            watermark
        }
        .padding(20)
        .frame(width: cardWidth)
        .background(Theme.background)
        .environment(\.colorScheme, scheme)
    }

    /// Big title falls back to the date when the session has no custom title,
    /// so a titleless session doesn't print the date twice.
    private var displayTitle: String {
        title.isEmpty ? dateText : title
    }

    /// Always shows the capture time (the snapshot moment the graph's "now" bar
    /// marks); prepends the date when the big title is a custom session name.
    private var subtitle: String {
        let time = capturedAt.formatted(date: .omitted, time: .shortened)
        if title.isEmpty || title == dateText { return time }
        return "\(dateText) · \(time)"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(displayTitle)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
            RoundedRectangle(cornerRadius: 1.5).fill(Theme.accent).frame(width: 40, height: 3).padding(.top, 2)
        }
    }

    /// Substances logged more than once this session, with running totals —
    /// mirrors the day-detail's cumulative section.
    private var cumulative: [(name: String, total: Double, unit: String, count: Int)] {
        var grouped: [String: (name: String, total: Double, unit: String, count: Int)] = [:]
        var order: [String] = []
        for display in displays {
            let key = display.core.displayName.lowercased()
            if let existing = grouped[key] {
                grouped[key] = (existing.name, existing.total + display.core.amount, existing.unit, existing.count + 1)
            } else {
                grouped[key] = (display.core.displayName, display.core.amount, display.core.unit, 1)
                order.append(key)
            }
        }
        return order.compactMap { grouped[$0] }.filter { $0.count > 1 }
    }

    @ViewBuilder private var cumulativeSection: some View {
        let items = cumulative
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cumulative")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(0.8)
                    .foregroundStyle(Theme.secondaryLabel)
                ForEach(items, id: \.name) { item in
                    HStack {
                        Text(item.name).font(.subheadline).foregroundStyle(.primary)
                        Spacer()
                        Text("\(item.total.doseFormatted) \(item.unit) (\(item.count)×)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
    }

    @ViewBuilder private var timeline: some View {
        if !states.isEmpty {
            TimelineGraphView(
                substances: states,
                currentTime: .now,
                compact: false,
                markers: markers,
                stackRedoses: stackRedoses,
                dayBounded: true,
                synchronous: true,
            )
            .frame(width: contentWidth, height: 200)
        }
    }

    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("^[\(displays.count) entry](inflect: true)")
                .font(.headline)
                .foregroundStyle(.primary)
            if twoColumn {
                let mid = (displays.count + 1) / 2
                HStack(alignment: .top, spacing: 16) {
                    groupedCard(Array(displays[..<mid]))
                    groupedCard(Array(displays[mid...]))
                }
            } else {
                groupedCard(displays)
            }
        }
    }

    /// An insetGrouped-style card: real `EntryRowView` rows with leading-inset
    /// hairline dividers, on `CardBackground()` — the on-screen list section.
    private func groupedCard(_ items: [DayEntryDisplay]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.core.entryID) { index, display in
                if index > 0 { Divider().padding(.leading, 16) }
                EntryRowView(display: display, showRelativeTime: false)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
            }
        }
        .background { CardBackground().clipShape(RoundedRectangle(cornerRadius: 12)) }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var watermark: some View {
        Text(verbatim: "Generated by Piru · kagerou.glass/piru")
            .font(.caption2)
            .foregroundStyle(Theme.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
    }
}
