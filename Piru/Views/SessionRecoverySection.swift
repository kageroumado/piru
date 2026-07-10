import SwiftUI

/// The session's Recovery section: the same fold-open category rows the comedown
/// guide shows under "Relevant to you", scoped to the substance categories in
/// *this* session, plus a link into the full guide. Bringing the guidance onto
/// the session screen — rather than a bare "Recovery tips" link — makes it feel
/// like part of the session rather than a bolt-on. Omitted when nothing in the
/// session has category-specific guidance.
struct SessionRecoverySection: View {
    let categories: [SubstanceCategory]

    var body: some View {
        Section("Recovery") {
            ForEach(categories, id: \.self) { category in
                ComedownCategoryDisclosure(category: category)
            }
            NavigationLink(value: PushRoute.comedownGuide) {
                Label("All recovery tips", systemImage: "heart.text.clipboard")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}
