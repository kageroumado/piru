import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

@MainActor
enum SessionShareImage {
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
    ) -> PlatformImage? {
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
        return renderer.platformImage
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

    private var displayTitle: String {
        title.isEmpty ? dateText : title
    }

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

    private struct BodyLoadRowData: Identifiable {
        let id: String
        let dotColor: Color
        let name: String
        let count: Int
        let total: Double
        let unit: String
        let status: BodyLoadStatus?
    }

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
