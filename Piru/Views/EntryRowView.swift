import SwiftUI

struct EntryRowView: View {
    let entry: DoseEntry
    var color: Color? = nil
    @State private var customStore = CustomSubstanceStore.shared

    private var doseLevel: DoseLevel? {
        guard let substance = SubstanceLibrary.lookupByNameOrAlias(entry.substance),
              let doseRange = substance.doseRange(for: entry.route) else { return nil }
        return doseRange.level(for: entry.amount)
    }

    private var relativeTime: String {
        let elapsed = Date.now.timeIntervalSince(entry.timestamp)
        guard elapsed > 0 else { return String(localized: "just now") }
        let totalMinutes = Int(elapsed / 60)
        let hours = totalMinutes / 60
        if hours >= 24 {
            return entry.timestamp.formatted(date: .abbreviated, time: .omitted)
        }
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 {
            return String(localized: "\(hours)h \(minutes)m ago")
        } else if hours > 0 {
            return String(localized: "\(hours)h ago")
        } else {
            return String(localized: "\(minutes)m ago")
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            if let color {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 3)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(customStore.displayName(for: entry.substance))
                    .font(.headline)
                HStack(spacing: 4) {
                    Text("\(entry.amount.doseFormatted) \(entry.unit) — \(String(localized: entry.route.localizedName))")
                    if let doseLevel {
                        Text("(\(String(localized: doseLevel.displayName)))")
                            .foregroundStyle(doseLevel.swiftUIColor)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                if !entry.tags.isEmpty {
                    TagChipsView(tags: entry.tags, compact: true)
                }
            }

            Spacer()

            TimelineView(.periodic(from: .now, by: 60)) { _ in
                VStack(alignment: .trailing, spacing: 2) {
                    Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline)
                    Text(relativeTime)
                        .font(.caption)
                }
                .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .padding(.vertical, 2)
    }
}
