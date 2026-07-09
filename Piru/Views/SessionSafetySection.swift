import SwiftUI

/// The session's safety card: interaction warnings shown in full (they used to
/// hide behind a collapsed disclosure at the bottom of the screen — folding the
/// last section saved no space, it just hid the warning), the heart-rate
/// summary when vitals are on, and the recovery-guidance link. Every row shares
/// one anatomy — a fixed 22pt leading icon column with a title/subtitle stack —
/// so the warning, the vitals summary, and the recovery link read as one card
/// instead of three unrelated treatments.
struct SessionSafetySection: View {
    let interactions: [InteractionResult]
    let hrSummary: HRSummary?

    var body: some View {
        Section {
            ForEach(interactions.enumerated(), id: \.offset) { _, warning in
                interactionRow(warning)
            }

            if let hrSummary {
                hrSummaryRow(hrSummary)
            }

            recoveryTipsRow
        }
    }

    // MARK: - Rows

    private func interactionRow(_ warning: InteractionResult) -> some View {
        SafetyRow(
            icon: warning.severity == .dangerous ? "exclamationmark.triangle.fill" : "exclamationmark.triangle",
            tint: warning.severity.labelColor,
        ) {
            HStack(spacing: 6) {
                Text("\(warning.severity.label): \(warning.substanceA) + \(warning.substanceB)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(warning.severity.labelColor)
                if warning.source != .classRule {
                    Text(warning.source.label)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(warning.severity.color.opacity(0.15), in: Capsule())
                        .foregroundStyle(warning.severity.labelColor)
                }
            }
        } subtitle: {
            Text(warning.description)
        }
        .accessibilityElement(children: .combine)
    }

    private func hrSummaryRow(_ summary: HRSummary) -> some View {
        SafetyRow(icon: "heart.fill", tint: VitalsPalette.heart) {
            HStack(spacing: 6) {
                Text("Heart rate")
                    .font(.subheadline.weight(.semibold))
                Text("avg \(summary.average) · peak \(summary.peak) bpm")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryLabel)
            }
        } subtitle: {
            if let resting = summary.resting {
                Text(
                    summary.average > resting + 3
                        ? "Elevated vs your resting \(resting) bpm"
                        : "In line with your resting \(resting) bpm",
                )
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var recoveryTipsRow: some View {
        NavigationLink(value: PushRoute.comedownGuide) {
            SafetyRow(icon: "heart.text.clipboard", tint: Theme.accent) {
                Text("Recovery tips")
                    .font(.subheadline.weight(.semibold))
            } subtitle: {
                Text("Hydration, food, and rest for the comedown")
            }
        }
    }
}

/// One row of the safety card: a tinted icon tile, a title, and an optional
/// secondary line — the shared anatomy that aligns the interaction warning, the
/// vitals summary, and the recovery link.
private struct SafetyRow<Title: View, Subtitle: View>: View {
    let icon: String
    let tint: Color
    @ViewBuilder var title: Title
    @ViewBuilder var subtitle: Subtitle

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title
                subtitle
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 1)
        }
        .padding(.vertical, 2)
    }
}
