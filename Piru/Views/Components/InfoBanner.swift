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
    let title: LocalizedStringKey
    /// The body beneath the title — usually one or more captions.
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconTint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .sectionLabel()
                content
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)
        }
    }
}
