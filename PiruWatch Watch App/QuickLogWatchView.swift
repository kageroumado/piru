import SwiftUI

/// The watch's home screen: a tap-to-log grid of the user's favorites + recents, pushed from
/// the phone. No search, no library — if a substance isn't a favorite/recent, that's a phone
/// task. A mass tile opens a Crown amount adjust; an alcohol tile opens the drink-preset flow.
struct QuickLogWatchView: View {
    @Environment(WatchSyncCoordinator.self) private var sync

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Quick Log")
        }
        .id(sync.manifest?.journalGeneration ?? 0)
    }

    @ViewBuilder
    private var content: some View {
        if let items = sync.manifest?.items, !items.isEmpty {
            List {
                if sync.pendingCount > 0 {
                    Label("^[\(sync.pendingCount) entry](inflect: true) syncing", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    NavigationLink {
                        destination(for: item)
                    } label: {
                        QuickLogTile(item: item)
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "No Favorites Yet",
                systemImage: "star",
                description: Text("Favorite a substance or record an entry on your iPhone to find it here."),
            )
        }
    }

    @ViewBuilder
    private func destination(for item: QuickLogManifestItem) -> some View {
        if item.isByVolume {
            DrinkLogView(item: item)
        } else {
            AmountLogView(item: item)
        }
    }
}

/// One row: a color dot, the substance name, and its default measurement (or "Drink").
struct QuickLogTile: View {
    let item: QuickLogManifestItem

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tileColor)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName ?? item.substance)
                    .font(.headline)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if item.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        }
        // One element: name, then amount and route, then Favorite — instead of
        // three stops and an unlabeled star.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.displayName ?? item.substance)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        item.isFavorite ? "\(spokenSubtitle), \(String(localized: "Favorite"))" : spokenSubtitle
    }

    /// The subtitle with a comma for its middle dot, which VoiceOver would
    /// otherwise read aloud.
    private var spokenSubtitle: String {
        if item.isByVolume { return String(localized: "Drink") }
        return "\(WatchDoseFormat.amount(item.amount)) \(item.unit), \(WatchDoseFormat.route(item.route))"
    }

    private var subtitle: String {
        if item.isByVolume { return String(localized: "Drink") }
        return "\(WatchDoseFormat.amount(item.amount)) \(item.unit) · \(WatchDoseFormat.route(item.route))"
    }

    private var tileColor: Color {
        item.tint?.color ?? .accentColor
    }
}
