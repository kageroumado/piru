import SwiftUI

// MARK: - Shared card chrome

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
