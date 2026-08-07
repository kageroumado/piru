import SwiftUI
import WidgetKit

/// Piru's watch complication: a one-tap shortcut into wrist quick-log. Tapping any
/// complication launches its host watch app, and the app's root IS the quick-log grid —
/// so no deep link is needed. Static content (a glanceable pill glyph); it never refreshes.
struct QuickLogComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickLog", provider: Provider()) { _ in
            ComplicationView()
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Quick Log")
        .description("Log a dose from your wrist.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}

private struct Entry: TimelineEntry {
    let date: Date
}

private struct Provider: TimelineProvider {
    func placeholder(in _: Context) -> Entry {
        Entry(date: Date())
    }

    func getSnapshot(in _: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // Static shortcut — one entry, never refreshed.
        completion(Timeline(entries: [Entry(date: Date())], policy: .never))
    }
}

private struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Quick Log", systemImage: "pills.fill")
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: "pills.fill")
                Text("Quick Log")
            }
        case .accessoryCorner:
            Image(systemName: "pills.fill")
                .font(.title2)
                .widgetLabel("Piru")
        default: // accessoryCircular
            Image(systemName: "pills.fill")
                .font(.title2)
        }
    }
}
