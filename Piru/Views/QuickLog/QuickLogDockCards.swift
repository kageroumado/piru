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

// MARK: - Interaction warnings

/// The live interaction warnings as their own card, sitting above the commit
/// bar — not loose rows floating on the sheet.
///
/// This is the most interruptive interaction surface in the app: it appears
/// unbidden, mid-log, over the button. So it takes the highest floor. A
/// `.background` finding — two stimulants, cannabis with a benzo — is real and
/// stays reachable, as a count that opens the explorer, because a card that
/// says something every time someone stages a coffee is a card that stops being
/// read before the day it matters.
struct DockInteractionsCard: View {
    let interactions: [InteractionResult]

    @State private var showsQuiet = false

    private var loud: [InteractionResult] {
        interactions.admitted(.notable)
    }
    private var quiet: [InteractionResult] {
        interactions.filter { $0.prominence < .notable }
    }

    var body: some View {
        DockGroupedCard {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(loud.enumerated()), id: \.offset) { _, warning in
                    InteractionWarningRow(warning: warning)
                }
                if !quiet.isEmpty {
                    if showsQuiet {
                        ForEach(Array(quiet.enumerated()), id: \.offset) { _, warning in
                            InteractionWarningRow(warning: warning)
                        }
                    } else {
                        Button {
                            withAnimation(.snappy(duration: 0.18)) { showsQuiet = true }
                        } label: {
                            HStack(spacing: 6) {
                                ForEach(Array(quiet.prefix(4).enumerated()), id: \.offset) { _, item in
                                    Circle()
                                        .fill(item.severity.color)
                                        .frame(width: 6, height: 6)
                                }
                                Text("^[\(quiet.count) more](inflect: true)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryLabel)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
