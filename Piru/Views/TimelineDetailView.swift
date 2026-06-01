import SwiftData
import SwiftUI

/// Fullscreen, interactive version of the day's PK timeline. Reuses the shared
/// `TimelineGraphView(compact: false)` renderer but adds room, a legend with
/// tap-to-isolate, and window presets. Presented as a navigator sheet via
/// `SheetRoute.timelineDetail(date:)`.
struct TimelineDetailView: View {
    let date: Date

    @Environment(\.appNavigator) private var navigator
    @Query private var entries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]
    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru"))
    private var stackRedoses = true

    /// Active window preset driving the graph's initial framing.
    @State private var window: TimeWindow = .all
    /// Case-insensitive substance name isolated by a legend tap, or nil.
    @State private var isolated: String?
    @State private var exportedImage: UIImage?
    @State private var showShareSheet = false
    @State private var isExporting = false

    init(date: Date) {
        self.date = date
        let start = Calendar.current.sessionDayStart(for: date)
        let end = start.addingTimeInterval(86_400)
        _entries = Query(
            filter: #Predicate<DoseEntry> { entry in
                entry.timestamp >= start && entry.timestamp < end
            },
            sort: \DoseEntry.timestamp,
        )
    }

    private var substanceStates: [ActiveSubstanceState] {
        ActiveSubstanceState.timeline(for: entries, colors: Array(substanceColors)).states
    }

    private var doseMarkers: [DoseMarker] {
        ActiveSubstanceState.timeline(for: entries, colors: Array(substanceColors)).markers
    }

    /// One chip per distinct substance drawn on the graph, in first-dose order,
    /// carrying the color the curve uses so the legend reads as a key.
    private var legendItems: [LegendItem] {
        var seen = Set<String>()
        var items: [LegendItem] = []
        for state in substanceStates {
            let key = state.substanceName.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            items.append(LegendItem(
                key: key,
                name: state.substanceName,
                color: Color(hex: state.colorHex),
            ))
        }
        return items
    }

    private var dateTitle: String {
        let base = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide)
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        return date.formatted(sameYear ? base : base.year())
    }

    var body: some View {
        VStack(spacing: GraphMetrics.section) {
            TimelineGraphView(
                substances: substanceStates,
                currentTime: .now,
                compact: false,
                markers: doseMarkers,
                stackRedoses: stackRedoses,
                highlighted: isolated,
                presetSpanMinutes: window.spanMinutes,
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, GraphMetrics.cardInset)

            legend

            WindowPicker(selection: $window)
                .padding(.horizontal, GraphMetrics.cardInset)
        }
        .padding(.vertical, GraphMetrics.section)
        .background(Theme.background)
        .navigationTitle(dateTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { navigator.dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $stackRedoses) {
                    Label("Stack Redoses", systemImage: "square.stack.3d.up.fill")
                }
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exportDayLog()
                } label: {
                    if isExporting {
                        ProgressView().tint(Theme.accent)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .disabled(isExporting || entries.isEmpty)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let exportedImage {
                TimelineShareSheet(image: exportedImage)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    /// Wrapping chips; tapping toggles isolation of that substance's curve.
    @ViewBuilder
    private var legend: some View {
        if legendItems.count > 1 {
            FlowLayout(spacing: 8) {
                ForEach(legendItems) { item in
                    let isOn = isolated == item.key
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isolated = isOn ? nil : item.key
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 9, height: 9)
                            Text(item.name)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .background(
                        Capsule().fill(isOn ? item.color.opacity(0.18) : Color(.secondarySystemFill)),
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            isOn ? item.color.opacity(0.6) : .clear,
                            lineWidth: 1,
                        ),
                    )
                    .opacity(isolated == nil || isOn ? 1 : 0.5)
                }
            }
            .padding(.horizontal, GraphMetrics.cardInset)
        }
    }

    private func exportDayLog() {
        isExporting = true
        let entriesCopy = entries.map { entry in
            DayLogImageExporter.EntryData(
                substance: entry.substance,
                amount: entry.amount,
                unit: entry.unit,
                route: entry.route,
                timestamp: entry.timestamp,
                notes: entry.notes,
                tags: entry.tags,
                category: SubstanceLibrary.lookupByNameOrAlias(entry.substance)?.category,
                doseLevel: SubstanceLibrary.lookupByNameOrAlias(entry.substance)?
                    .doseRange(for: entry.route)?.level(for: entry.amount),
                colorHex: Array(substanceColors).hexColorMap[entry.substance.lowercased()],
            )
        }
        let exportDate = date
        Task {
            let image = DayLogImageExporter.generateImage(date: exportDate, entries: entriesCopy)
            isExporting = false
            if let image {
                exportedImage = image
                showShareSheet = true
            }
        }
    }
}

// MARK: - Window presets

/// Initial framing presets for the fullscreen timeline. `spanMinutes` is the
/// target visible window passed to `TimelineGraphView`; `nil` fits everything.
enum TimeWindow: String, CaseIterable, Identifiable {
    case h4, h8, h12, h24, all

    var id: String { rawValue }

    var spanMinutes: Double? {
        switch self {
        case .h4: 4 * 60
        case .h8: 8 * 60
        case .h12: 12 * 60
        case .h24: 24 * 60
        case .all: nil
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .h4: "4h"
        case .h8: "8h"
        case .h12: "12h"
        case .h24: "24h"
        case .all: "All"
        }
    }
}

private struct WindowPicker: View {
    @Binding var selection: TimeWindow

    var body: some View {
        Picker("Window", selection: $selection) {
            ForEach(TimeWindow.allCases) { window in
                Text(window.label).tag(window)
            }
        }
        .pickerStyle(.segmented)
    }
}

// MARK: - Legend model

private struct LegendItem: Identifiable {
    let key: String
    let name: String
    let color: Color
    var id: String { key }
}

// MARK: - Share sheet

private struct TimelineShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
