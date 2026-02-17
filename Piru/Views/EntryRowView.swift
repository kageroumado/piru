import SwiftUI

struct EntryRowView: View {
    let entry: DoseEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.substance)
                    .font(.headline)
                Text("\(entry.amount.formatted()) \(entry.unit) — \(entry.route.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
