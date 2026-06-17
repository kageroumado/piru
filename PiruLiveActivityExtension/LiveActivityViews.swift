import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Lock Screen View

struct LockScreenView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    /// Default must match the app (true). The Live Activity and the in-app graph
    /// share this key/store; a divergent default made the LA draw an un-stacked
    /// curve (single bell) while the app showed the stacked redose curve.
    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru"))
    private var stackRedoses = true

    private var substances: [ActiveSubstanceState] {
        context.state.activeSubstances
    }

    private var earliestDose: Date {
        substances.map(\.doseTimestamp).min() ?? context.state.lastUpdated
    }

    private var latestEnd: Date {
        substances.map { sub in
            sub.doseTimestamp.addingTimeInterval(sub.totalMinutes * 60)
        }.max() ?? context.state.lastUpdated.addingTimeInterval(3_600)
    }

    private var substanceColors: [Color] {
        let colors = substances.map { Color(hex: $0.colorHex) }
        guard !colors.isEmpty else { return [Color(hex: "FFAACC")] }
        // Ensure at least 2 colors for a gradient
        return colors.count == 1 ? [colors[0], colors[0]] : colors
    }

    var body: some View {
        VStack(spacing: 6) {
            // Timeline Graph – updates when Live Activity state is pushed
            TimelineGraphView(
                substances: substances,
                currentTime: context.state.lastUpdated,
                compact: true,
                stackRedoses: stackRedoses,
                synchronous: true,
            )
            .frame(height: 80)

            // Gradient progress bar that auto-fills
            ProgressView(
                timerInterval: earliestDose ... latestEnd,
                countsDown: false,
            ) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(
                LinearGradient(
                    colors: substanceColors,
                    startPoint: .leading,
                    endPoint: .trailing,
                ),
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
        }.max() ?? context.state.lastUpdated.addingTimeInterval(3_600)
    }

    var body: some View {
        Text(latestEnd, style: .timer)
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.secondary)
    }
}

struct ExpandedBottomView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru"))
    private var stackRedoses = true

    var body: some View {
        TimelineGraphView(
            substances: context.state.activeSubstances,
            currentTime: context.state.lastUpdated,
            compact: true,
            stackRedoses: stackRedoses,
            synchronous: true,
        )
        .frame(height: 50)
    }
}

// MARK: - Dynamic Island Compact Icons

/// Pill icon with a small clock badge overlaid on the top-right corner.
struct PillClockIcon: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "pill.fill")
                .font(.system(size: 12))
            Circle()
                .fill(.black)
                .frame(width: 9, height: 9)
                .overlay(
                    Image(systemName: "clock")
                        .font(.system(size: 6, weight: .medium)),
                )
                .offset(x: 3, y: 1)
        }
        .foregroundStyle(.white)
    }
}

/// Small declining graph icon indicating substance levels are decreasing.
struct GraphDeclineIcon: View {
    var body: some View {
        Image(systemName: "chart.line.downtrend.xyaxis")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
    }
}

/// Custom shape drawing an exponential decay curve with L-shaped axes.
private struct DeclineCurveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Y axis
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: h))
        // X axis
        path.addLine(to: CGPoint(x: w, y: h))

        // Hand-tuned polyline for the Dynamic Island compact icon — purely
        // decorative, not derived from PK.
        path.move(to: CGPoint(x: w * 0.08, y: h * 0.08))
        path.addCurve(
            to: CGPoint(x: w * 0.92, y: h * 0.88),
            control1: CGPoint(x: w * 0.2, y: h * 0.15),
            control2: CGPoint(x: w * 0.55, y: h * 0.85),
        )

        return path
    }
}

// MARK: - Dynamic Island Compact Views

struct CompactLeadingView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    private var earliestDose: Date {
        context.state.activeSubstances.map(\.doseTimestamp).min() ?? context.state.lastUpdated
    }

    var body: some View {
        HStack(spacing: 3) {
            PillClockIcon()
            Text(earliestDose, style: .timer)
                .font(.caption2.monospacedDigit().weight(.medium))
        }
        .frame(minWidth: 32)
    }
}

struct CompactTrailingView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    private var latestEnd: Date {
        context.state.activeSubstances.map { sub in
            sub.doseTimestamp.addingTimeInterval(sub.totalMinutes * 60)
        }.max() ?? context.state.lastUpdated.addingTimeInterval(3_600)
    }

    var body: some View {
        HStack(spacing: 3) {
            GraphDeclineIcon()
            Text(latestEnd, style: .timer)
                .font(.caption2.monospacedDigit())
        }
        .frame(minWidth: 32)
    }
}

// MARK: - Formatting Helpers

private func elapsedString(from start: Date, to now: Date) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(start)))
    let hours = seconds / 3_600
    let minutes = (seconds % 3_600) / 60
    return hours > 0
        ? String(localized: "\(hours)h \(minutes)m")
        : String(localized: "\(minutes)m")
}

private func remainingString(from now: Date, to end: Date) -> String {
    let seconds = max(0, Int(end.timeIntervalSince(now)))
    let hours = seconds / 3_600
    let minutes = (seconds % 3_600) / 60
    return hours > 0
        ? String(localized: "\(hours)h \(minutes)m")
        : String(localized: "\(minutes)m")
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
