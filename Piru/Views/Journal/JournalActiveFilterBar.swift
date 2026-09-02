import SwiftUI

/// One removable chip per active filter value (tags, then categories, then
/// routes) and a trailing Clear. Only rendered while a filter is active — the
/// funnel menu is where filters are *applied*; this strip is where the current
/// selection stays visible and individually dismissible.
struct JournalActiveFilterBar: View {
    @Binding var tags: Set<String>
    @Binding var categories: Set<SubstanceCategory>
    @Binding var routes: Set<RouteOfAdministration>
    let onClear: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.md) {
                ForEach(tags.sorted(), id: \.self) { tag in
                    JournalFilterChip(title: Text(verbatim: "#\(tag)")) {
                        tags.remove(tag)
                    }
                }
                ForEach(categories.sorted { $0.rawValue < $1.rawValue }, id: \.self) { category in
                    JournalFilterChip(title: Text(category.displayName)) {
                        categories.remove(category)
                    }
                }
                ForEach(routes.sorted { $0.rawValue < $1.rawValue }, id: \.self) { route in
                    JournalFilterChip(title: Text(route.localizedName)) {
                        routes.remove(route)
                    }
                }

                Button {
                    withAnimation(.snappy) { onClear() }
                } label: {
                    Text("Clear")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.md)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Spacing.xs)
        }
        .scrollIndicators(.hidden)
    }
}

/// One value of one facet, with the ✕ that drops it.
///
/// No `capsuleChip` here: this is a selected-state chip — a solid accent fill
/// under a white label, not the 10% tint of a categorical badge — and it wraps
/// a label plus a glyph rather than a bare `Text`.
private struct JournalFilterChip: View {
    let title: Text
    let remove: () -> Void

    var body: some View {
        Button {
            withAnimation(.snappy) { remove() }
        } label: {
            HStack(spacing: 5) {
                title
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .opacity(Theme.Opacity.strong)
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.md)
            .background(Theme.accent, in: Capsule())
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Removes this filter."))
    }
}
