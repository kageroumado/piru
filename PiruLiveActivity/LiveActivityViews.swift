import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Lock Screen View

struct LockScreenView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    private var substances: [ActiveSubstanceState] {
        context.state.activeSubstances
    }

    private var earliestDose: Date {
        substances.map(\.doseTimestamp).min() ?? context.state.lastUpdated
    }

    private var latestEnd: Date {
        substances.map { sub in
            sub.doseTimestamp.addingTimeInterval(sub.totalMinutes * 60)
        }.max() ?? context.state.lastUpdated.addingTimeInterval(3600)
    }

    private var substanceColors: [Color] {
        let colors = substances.map { Color(hex: $0.colorHex) }
        guard !colors.isEmpty else { return [Color(hex: "FFAACC")] }
        // Ensure at least 2 colors for a gradient
        return colors.count == 1 ? [colors[0], colors[0]] : colors
    }

    var body: some View {
        VStack(spacing: 6) {
            // Timeline Graph – periodic refresh so knobs track real time
            TimelineView(.periodic(from: .now, by: 15)) { timeline in
                TimelineGraphView(
                    substances: substances,
                    currentTime: timeline.date,
                    compact: true
                )
                // Force Canvas re-render by changing view identity each tick
                .id(Int(timeline.date.timeIntervalSinceReferenceDate / 15))
            }
            .frame(height: 80)

            // Gradient progress bar that auto-fills
            ProgressView(
                timerInterval: earliestDose...latestEnd,
                countsDown: false
            ) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(
                LinearGradient(
                    colors: substanceColors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            // Time passed since first dose
            Text(earliestDose, style: .timer)
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .activityBackgroundTint(.black.opacity(0.5))
    }
}

// MARK: - Dynamic Island Expanded Views

struct ExpandedLeadingView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    private var earliestDose: Date {
        context.state.activeSubstances.map(\.doseTimestamp).min() ?? context.state.lastUpdated
    }

    var body: some View {
        Text(earliestDose, style: .timer)
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.white)
    }
}

struct ExpandedTrailingView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    private var latestEnd: Date {
        context.state.activeSubstances.map { sub in
            sub.doseTimestamp.addingTimeInterval(sub.totalMinutes * 60)
        }.max() ?? context.state.lastUpdated.addingTimeInterval(3600)
    }

    var body: some View {
        Text(latestEnd, style: .timer)
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.secondary)
    }
}

struct ExpandedBottomView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            TimelineGraphView(
                substances: context.state.activeSubstances,
                currentTime: timeline.date,
                compact: true
            )
            .id(Int(timeline.date.timeIntervalSinceReferenceDate / 15))
        }
        .frame(height: 50)
    }
}

// MARK: - Dynamic Island Compact Views

struct CompactLeadingView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    private var earliestDose: Date {
        context.state.activeSubstances.map(\.doseTimestamp).min() ?? context.state.lastUpdated
    }

    var body: some View {
        Text(earliestDose, style: .timer)
            .font(.caption2.monospacedDigit().weight(.medium))
            .frame(minWidth: 32)
    }
}

struct CompactTrailingView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    private var latestEnd: Date {
        context.state.activeSubstances.map { sub in
            sub.doseTimestamp.addingTimeInterval(sub.totalMinutes * 60)
        }.max() ?? context.state.lastUpdated.addingTimeInterval(3600)
    }

    var body: some View {
        Text(latestEnd, style: .timer)
            .font(.caption2.monospacedDigit())
            .frame(minWidth: 32)
            .multilineTextAlignment(.trailing)
    }
}

// MARK: - Minimal View

struct MinimalView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    var body: some View {
        if let first = context.state.activeSubstances.first {
            Circle()
                .fill(Color(hex: first.colorHex))
                .frame(width: 10, height: 10)
        }
    }
}
