import SwiftData
import SwiftUI

/// Full-screen home of the continuous timeline: the ribbon at reading size,
/// scrollable back through the whole dose history, with touch-and-hold
/// inspection. Pushed as a place (``PushRoute/timelineRibbon``) from the
/// Journal's compact ribbon card.
struct TimelineRibbonScreen: View {
    @Query(Self.entriesDescriptor) private var entries: [DoseEntry]
    @Query private var colors: [SubstanceColor]
    @State private var model = TimelineRibbonModel()

    /// Newest-first to match the ribbon model's expectations (and the Journal).
    private static var entriesDescriptor: FetchDescriptor<DoseEntry> {
        FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
    }

    /// Content fingerprint driving the rebuild task (edits included).
    private var signature: Int {
        var hasher = Hasher()
        for entry in entries {
            hasher.combine(entry.timestamp)
            hasher.combine(entry.substance)
            hasher.combine(entry.amount)
            hasher.combine(entry.unit)
            hasher.combine(entry.route)
            hasher.combine(entry.isBackgroundMed)
        }
        for color in colors {
            hasher.combine(color.substance)
            hasher.combine(color.hexColor)
        }
        return hasher.finalize()
    }

    var body: some View {
        Group {
            if model.revision > 0, model.snapshots.isEmpty {
                ContentUnavailableView {
                    Label("No Timeline Yet", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("Log a dose and its effect curve will appear here.")
                }
            } else {
                ribbonContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: signature) {
            await model.rebuild(entries: entries, colors: colors)
        }
    }

    private var ribbonContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer(minLength: 0)

            TimelineRibbonView(
                model: model,
                tileWidth: 220,
                height: 320,
                compact: false,
                scrubEnabled: true,
            )
            .themeCard()
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityLabel(Text("Continuous dose timeline"))

            Text("Scroll back through your history. Touch and hold to inspect a moment.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.horizontal, 14)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }
}
