import SwiftUI

struct EntryRowView: View {
    let entry: DoseEntry
    var color: Color? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let color {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 3)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.substance)
                    .font(.headline)
                Text("\(entry.amount.formatted()) \(entry.unit) — \(entry.route.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                if !entry.tags.isEmpty {
                    TagChipsView(tags: entry.tags, compact: true)
                }
            }

            Spacer()

            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .padding(.vertical, 2)
    }
}
