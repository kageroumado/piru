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
        doseHR: [UUID: DoseHRResponse] = [:],
        capturedAt: Date = .now,
    ) -> UIImage? {
        guard !entries.isEmpty else { return nil }
        let displays = DayEntryDisplay.make(from: entries, colors: colors, doseHR: doseHR)
        let (states, markers) = ActiveSubstanceState.timeline(for: entries, colors: colors)
        let card = SessionShareCard(
            title: title,
            dateText: dateText,
            capturedAt: capturedAt,
            entries: entries,
            colorMap: colors.colorMap,
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
    let entries: [DoseEntry]
    let colorMap: [String: Color]
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
            bodyLoadSection
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

    /// One shareable "in your body" row's data, flattened from the model so the
    /// active and cleared rows can be split across two columns together.
    private struct BodyLoadRowData: Identifiable {
        let id: String
        let dotColor: Color
        let name: String
        let count: Int
        let total: Double
        let unit: String
        let status: BodyLoadStatus?
    }

    /// The model's active-then-cleared rows as one ordered list, ready to slice
    /// into columns. `nil` status on cleared rows when nothing is still active
    /// keeps them single-line, matching the live section.
    private func bodyLoadRows(_ model: SessionBodyLoadModel) -> [BodyLoadRowData] {
        let hasActive = !model.active.isEmpty
        var rows = model.active.map { row in
            BodyLoadRowData(
                id: row.id,
                dotColor: row.active.color,
                name: row.displayName,
                count: row.count,
                total: row.sessionTotal,
                unit: row.unit,
                status: .eliminating(
                    percent: Int(row.active.eliminatedFraction * 100),
                    clear: SessionBodyLoadModel.clearText(for: row.active),
                    remaining: row.remaining,
                ),
            )
        }
        rows += model.cleared.map { row in
            BodyLoadRowData(
                id: row.id,
                dotColor: row.color,
                name: row.displayName,
                count: row.count,
                total: row.total,
                unit: row.unit,
                status: hasActive ? .cleared(hasActiveMetabolite: row.hasActiveMetabolite) : nil,
            )
        }
        return rows
    }

    /// "In your body" — the same per-substance elimination rows the live session
    /// detail shows, rendered from the shared ``SessionBodyLoadModel`` and
    /// ``BodyLoadRowLabel`` so the export can't drift from the screen. Static rows
    /// only (no expandable curves), split into two columns whenever the entries are.
    @ViewBuilder private var bodyLoadSection: some View {
        let model = SessionBodyLoadModel.make(entries: entries, colorMap: colorMap)
        if !model.isEmpty {
            let rows = bodyLoadRows(model)
            if twoColumn {
                let mid = (rows.count + 1) / 2
                HStack(alignment: .top, spacing: 16) {
                    bodyLoadCard(Array(rows[..<mid]))
                    bodyLoadCard(Array(rows[mid...]))
                }
            } else {
                bodyLoadCard(rows)
            }
        }
    }

    /// A grouped card of body-load rows with leading-inset hairline dividers, on
    /// `CardBackground()` — the same shell as ``groupedCard`` for the entry rows.
    private func bodyLoadCard(_ rows: [BodyLoadRowData]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().padding(.leading, 16) }
                BodyLoadRowLabel(
                    dotColor: row.dotColor,
                    name: row.name,
                    count: row.count,
                    total: row.total,
                    unit: row.unit,
                    status: row.status,
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }
        }
        .background { CardBackground().clipShape(RoundedRectangle(cornerRadius: 12)) }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Distinct substances drawn, split the way the renderer splits them: the
    /// graph draws a lane per duration-less (pin-only) substance too, so this
    /// counts across both, not curve substances alone.
    private var curveLaneCount: Int {
        Set(states.map { $0.substanceName.lowercased() }).count
    }

    private var markerLaneCount: Int {
        Set(markers.map { $0.substanceName.lowercased() })
            .subtracting(states.map { $0.substanceName.lowercased() })
            .count
    }

    @ViewBuilder private var timeline: some View {
        if !states.isEmpty {
            let store = UserDefaults(suiteName: LaneModeDefaults.suite)
            let laneEnabled = store?.object(forKey: LaneModeDefaults.enabledKey) as? Bool ?? LaneModeDefaults.enabledDefault
            let threshold = store?.object(forKey: LaneModeDefaults.thresholdKey) as? Int ?? LaneModeDefaults.thresholdDefault
            // Busy (lane-mode) sessions render as the app's *enlarged* small
            // multiples so each substance's strip stays readable; simple
            // overlapping-curve days keep the compact embedded height.
            let laneMode = laneEnabled && curveLaneCount >= threshold
            let height = GraphMetrics.graphHeight(
                enlarged: laneMode,
                curveLaneCount: curveLaneCount,
                markerLaneCount: markerLaneCount,
                laneModeEnabled: laneEnabled,
                laneModeThreshold: threshold,
            )
            TimelineGraphView(
                substances: states,
                currentTime: .now,
                compact: false,
                markers: markers,
                stackRedoses: stackRedoses,
                dayBounded: true,
                synchronous: true,
            )
            .frame(width: contentWidth, height: height)
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
