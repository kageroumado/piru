import SwiftUI

struct EntryRowView: View {
    let entry: DoseEntry
    var color: Color?
    /// Whether to show the "13h ago" relative line under the clock time. Set by
    /// the day detail for today/yesterday so every row in a recent day matches;
    /// older days show the clock time alone, keeping the column symmetric.
    var showRelativeTime: Bool = false
    @State private var customStore = CustomSubstanceStore.shared

    /// Leading inset that aligns the secondary line under the name (past the
    /// colour dot + its spacing).
    private static let textInset: CGFloat = 18

    private var doseLevel: DoseLevel? {
        guard let substance = SubstanceLibrary.lookupByNameOrAlias(entry.substance),
              let doseRange = substance.doseRange(for: entry.route) else { return nil }
        return doseRange.level(for: entry.amount)
    }

    /// Elapsed time since the dose, e.g. "45m ago", "13h 25m ago", or "1d ago".
    private var relativeTime: String {
        let elapsed = max(0, Date.now.timeIntervalSince(entry.timestamp))
        let totalMinutes = Int(elapsed / 60)
        guard totalMinutes >= 1 else { return String(localized: "just now") }
        let hours = totalMinutes / 60
        if hours >= 24 {
            let days = hours / 24
            return String(localized: "\(days)d ago")
        }
        let minutes = totalMinutes % 60
        if hours > 0, minutes > 0 {
            return String(localized: "\(hours)h \(minutes)m ago")
        } else if hours > 0 {
            return String(localized: "\(hours)h ago")
        } else {
            return String(localized: "\(minutes)m ago")
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let color {
                        Circle()
                            .fill(color)
                            .frame(width: 10, height: 10)
                    }
                    Text(customStore.displayName(for: entry.substance))
                        .font(.headline)
                }
                VStack(alignment: .leading, spacing: 4) {
                    // One coherent line — route · amount · level — differentiated
                    // by weight and colour rather than mixing plain text with a
                    // pill. The dose level qualifies the amount, so it sits next
                    // to it; the route leads as context, the amount and level are
                    // the emphasised data.
                    HStack(spacing: 5) {
                        // Lowercased so the line reads as a phrase — "rectal · 20
                        // mg" — not a title. A no-op for the case-less CJK
                        // localizations.
                        Text(String(localized: entry.route.localizedName).lowercased())
                            .foregroundStyle(Theme.secondaryLabel)
                        Text(verbatim: "·").foregroundStyle(.tertiary)
                        Text("\(entry.amount.doseFormatted) \(entry.unit)")
                            .foregroundStyle(.primary)
                            .fontWeight(.semibold)
                        if let doseLevel {
                            Text(verbatim: "·").foregroundStyle(.tertiary)
                            Text(String(localized: doseLevel.displayName).lowercased())
                                .fontWeight(.semibold)
                                .foregroundStyle(doseLevel.labelColor)
                        }
                    }
                    .font(.subheadline)
                    if !entry.tags.isEmpty {
                        TagChipsView(tags: entry.tags, compact: true)
                    }
                }
                .padding(.leading, color == nil ? 0 : Self.textInset)
            }

            Spacer()

            TimelineView(.periodic(from: .now, by: 60)) { _ in
                VStack(alignment: .trailing, spacing: 2) {
                    Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline)
                    if showRelativeTime {
                        Text(relativeTime)
                            .font(.caption)
                    }
                }
                .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .padding(.vertical, 2)
    }
}
