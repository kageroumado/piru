import SwiftUI

struct SourceLinkRow: View {
    let name: String
    let detail: String
    var description: String = ""
    var url: String = ""

    var body: some View {
        if !url.isEmpty, let link = URL(string: url) {
            Link(destination: link) {
                content
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
            }
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
            if !description.isEmpty {
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}
