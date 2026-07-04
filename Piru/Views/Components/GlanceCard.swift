import SwiftUI

/// The shared header for every glance-style card (Insights, Tools, Education):
/// a fixed-size tinted icon, the title, and a trailing accessory. Extracted so
/// all cards render **identical** fonts and icon sizing — the icon lives in a
/// fixed-width box so a filled symbol and an outline symbol occupy the same
/// space and every title lines up.
struct GlanceCardHeader<Trailing: View>: View {
    let icon: String
    var iconTint: Color = Theme.accent
    let title: Text
    var titleColor: Color = .primary
    @ViewBuilder var trailing: () -> Trailing

    /// Fixed icon column width — wide enough for the broadest `.headline` symbol
    /// so nothing clips, narrow enough to read as an inline icon.
    static var iconWidth: CGFloat {
        26
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(iconTint)
                .frame(width: Self.iconWidth, alignment: .center)
            title
                .font(.headline)
                .foregroundStyle(titleColor)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

/// A trailing chevron for a glance-style header — `.right` for a push card,
/// `.down` (rotating) for a foldable one.
struct GlanceCardChevron: View {
    var systemName: String = "chevron.right"
    var rotated: Bool = false

    var body: some View {
        Image(systemName: systemName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.secondaryLabel)
            .rotationEffect(.degrees(rotated ? 180 : 0))
    }
}

/// A compact preview row shared by the Insights "In your system" card and the
/// Tools Interactions/Inventory summary cards: a leading colour dot, a title,
/// and trailing detail supplied by the caller.
struct GlanceRow<Trailing: View>: View {
    let dotColor: Color
    let title: Text
    var titleColor: Color = .primary
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 9, height: 9)
            title
                .font(.subheadline.weight(.medium))
                .foregroundStyle(titleColor)
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

/// The "+N more" footer shared by the summary/preview cards.
struct GlanceMoreRow: View {
    let count: Int

    var body: some View {
        HStack {
            Text("+\(count) more")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
            Spacer()
        }
    }
}

/// The app's Apple Health–style "glance" card: a shared ``GlanceCardHeader``
/// with a trailing chevron, over inline content (a graph, calendar, or summary
/// rows), wrapped as a tappable `NavigationLink`.
///
/// Used across the Insights tab (Usage, In-your-system, Adherence, Tolerance)
/// and the Tools tab's cards so they read as one cohesive system. The Insights
/// cards colour the title to match `tint` (they sit over large graphs); the
/// graph-less Tools cards keep the title neutral.
struct GlanceCard<Content: View>: View {
    let icon: String
    /// The leading icon's colour (the category tint).
    var tint: Color = Theme.accent
    /// The title text colour. Defaults to the regular label colour.
    var titleColor: Color = .primary
    let title: Text
    let route: PushRoute
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 12) {
                GlanceCardHeader(icon: icon, iconTint: tint, title: title, titleColor: titleColor) {
                    GlanceCardChevron()
                }

                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
