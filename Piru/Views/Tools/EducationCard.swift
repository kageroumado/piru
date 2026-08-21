import SwiftUI

/// The Tools tab's **Education** group — the same card style as the rest of the
/// tab (tinted header on a `themeCard`), but foldable: it expands in place to
/// reveal the learn-oriented screens (the ceiling effect, how tolerance works,
/// and the recovery guide) as tinted mini-cards.
struct EducationCard: View {
    @State private var isExpanded = false

    private struct Item: Identifiable {
        let tool: Tool
        var id: String {
            tool.id
        }
    }

    private let items: [Item] = [
        Item(tool: .ceiling),
        Item(tool: .toleranceInfo),
        Item(tool: .recovery),
        Item(tool: .drugClasses),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy(duration: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    GlanceCardHeader(icon: "graduationcap.fill", title: Text("Education")) {
                        GlanceCardChevron(systemName: "chevron.down", rotated: isExpanded)
                    }

                    Text("How dosing, tolerance, and recovery work")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Education"))
            .accessibilityHint(Text(isExpanded ? "Collapse" : "Expand"))

            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        NavigationLink(value: PushRoute.tool(item.tool)) {
                            EducationRow(tool: item.tool)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }
}

/// One row inside the expanded Education card — a tinted icon tile, title +
/// blurb, and a trailing chevron on a subtle accent-tinted inset.
private struct EducationRow: View {
    let tool: Tool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tool.icon)
                .font(.headline)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(tool.subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }
}
