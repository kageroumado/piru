import SwiftUI

/// The dock at its smallest stop while doses are staged: the staged substances'
/// colors, their count, and Record, in the space the search pill takes. It frees
/// the cards behind for browsing a long list of favorites; tapping the summary
/// opens the tray again.
struct DockSummaryBar: View {
    let tray: DoseTrayModel
    let onExpand: () -> Void
    let onCommit: () -> Void

    @Environment(\.profileDirectory) private var directory

    private static let maxDots = 4

    var body: some View {
        HStack(spacing: Spacing.md) {
            Button(action: onExpand) {
                HStack(spacing: Spacing.md) {
                    dots
                    Text("^[\(tray.staged.count) dose](inflect: true)")
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if !tray.time.isNow {
                        Text(tray.time.chipLabel)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.cautionText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.tertiaryLabel)
                        .accessibilityHidden(true)
                }
                .padding(.leading, 14)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("^[\(tray.staged.count) staged dose](inflect: true)"))
            .accessibilityHint(Text("Shows the staged doses"))

            Button(action: onCommit) {
                HStack(spacing: Spacing.sm) {
                    // The For chip's pick, so the collapsed bar can't commit
                    // into someone else's journal unseen.
                    if let recipient = tray.recipientID.flatMap(directory.profile(id:)) {
                        ProfileAvatarView(recipient, diameter: 18)
                    }
                    Text("Record")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, Spacing.xxl)
                .frame(maxHeight: .infinity)
                .skinProminentFill(in: skinChipShape())
            }
            .buttonStyle(.plain)
            .padding(5)
        }
        .frame(height: QuickLogDockMetrics.fieldHeight)
        .background(Color.platformSecondarySystemFill, in: skinChipShape())
    }

    /// Overlapping color dots, one per staged substance, so the stack reads at a
    /// glance before the count does.
    private var dots: some View {
        HStack(spacing: -6) {
            ForEach(tray.staged.prefix(Self.maxDots)) { dose in
                Circle()
                    .fill(dose.tint?.color ?? .gray)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.platformSystemBackground, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }
}
