import SwiftUI

// MARK: - Shared card chrome

// TODO(integrator): promote to Components/ if reused outside QuickLog.
/// Inset-grouped card chrome shared by the results, suggestions, and staged
/// surfaces — the dock's one visual container.
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
