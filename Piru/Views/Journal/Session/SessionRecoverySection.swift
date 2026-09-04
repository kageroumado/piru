import SwiftUI

/// The session's Recovery section: the same fold-open category rows the comedown
/// guide shows under "Relevant to you", scoped to the substance categories in
/// *this* session, plus a link into the full guide. Bringing the guidance onto
/// the session screen — rather than a bare "Recovery tips" link — makes it feel
/// like part of the session.
struct SessionRecoverySection: View {
    let categories: [SubstanceCategory]

    var body: some View {
        Section("Recovery Tips") {
            ForEach(categories, id: \.self) { category in
                ComedownCategoryDisclosure(category: category)
            }
            NavigationLink(value: PushRoute.comedownGuide) {
                // Matches the category rows above: a 24pt leading icon column and
                // the same body font, tinted to read as the "see everything" link.
                HStack(spacing: Spacing.lg) {
                    Image(systemName: "heart.text.clipboard")
                        .foregroundStyle(Theme.accent)
                        .frame(width: 24)
                    Text("All recovery tips")
                        .font(.body)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }
}
