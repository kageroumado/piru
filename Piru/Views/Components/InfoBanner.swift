import SwiftUI

/// The shared grammar for an inline note: a tinted leading glyph, a title, and
/// whatever body the caller supplies.
///
/// It is a layout, not a severity — the caller picks `iconTint`, so the same
/// structure serves a calm heads-up and a caution alike and the two read as one
/// family rather than two designs.
struct InfoBanner<Content: View>: View {
    /// SF Symbol name for the leading glyph.
    let icon: String
    /// Glyph color; the only thing that encodes tone.
    let iconTint: Color
    /// The banner's headline.
    let title: Text
    /// The body beneath the title — usually one or more captions.
    let content: Content

    init(icon: String, iconTint: Color, title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(icon: icon, iconTint: iconTint, title: Text(title), content: content)
    }

    /// For a headline that is already a `Text`: a resolved resource or a name
    /// from the database, which must not be looked up as a catalog key.
    init(icon: String, iconTint: Color, title: Text, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.iconTint = iconTint
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.piru(.title3))
                .foregroundStyle(iconTint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                title
                    .sectionLabel()
                content
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)
        }
    }
}
