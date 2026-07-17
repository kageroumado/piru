import SwiftUI

// MARK: - Shared card chrome

/// Inset-grouped card chrome shared by the results, suggestions, and staged
/// surfaces — the dock's one visual container.
// TODO(integrator): promote to Components/ if reused outside QuickLog.
struct DockGroupedCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: DoseTrayMetrics.cardCornerRadius, style: .continuous),
            )
    }
}

// MARK: - Interaction warnings

/// The live interaction warnings as their own card, sitting above the commit
/// bar — not loose rows floating on the sheet.
struct DockInteractionsCard: View {
    let interactions: [InteractionResult]

    var body: some View {
        DockGroupedCard {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(interactions.enumerated()), id: \.offset) { _, warning in
                    InteractionWarningRow(warning: warning)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
