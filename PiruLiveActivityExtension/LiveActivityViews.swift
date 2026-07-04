import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Session Timing Helpers

/// Shared timing math derived from a content state, so every region agrees on
/// the same "session" window without duplicating the reduce logic.
enum SessionTiming {
    /// Earliest dose timestamp across all active substances (session start).
    static func earliestDose(_ state: PiruActivityAttributes.ContentState) -> Date {
        state.activeSubstances.map(\.doseTimestamp).min() ?? state.lastUpdated
    }

    /// Latest projected session end: `max(doseTimestamp + totalMinutes)`.
    static func latestEnd(_ state: PiruActivityAttributes.ContentState) -> Date {
        state.activeSubstances.map { sub in
            sub.doseTimestamp.addingTimeInterval(sub.totalMinutes * 60)
        }.max() ?? state.lastUpdated.addingTimeInterval(3_600)
    }

    /// Elapsed fraction of the whole session, evaluated at `lastUpdated`
    /// (content-push time). Clamped to `0...1`. Coarse — refreshes only when a
    /// new content state is pushed (≈ every 60 s), which is fine for a ring.
    static func progress(_ state: PiruActivityAttributes.ContentState) -> Double {
        let start = earliestDose(state)
        let end = latestEnd(state)
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return 0 }
        let elapsed = state.lastUpdated.timeIntervalSince(start)
        return min(max(elapsed / span, 0), 1)
    }

    /// Substance colors, falling back to the app's soft-pink accent when empty.
    static func colors(_ state: PiruActivityAttributes.ContentState) -> [Color] {
        let colors = state.activeSubstances.map { Color(hex: $0.colorHex) }
        return colors.isEmpty ? [Color(hex: "FFAACC")] : colors
    }
}

// MARK: - Radial Progress Glyph

/// A clock-like radial gauge: a track that starts at 12 o'clock and sweeps
/// clockwise through ~330°, ending near 11 o'clock (a ~30° "start/end seam"
/// gap centered at the top). A solid progress arc fills from 12 o'clock by
/// `progress × 330°`, tipped with a small indicator dot at its leading end.
///
/// Reads as "12 = beginning, clockwise = more time elapsed, 11 = end". Tinted
/// by the substance color (single) or an `AngularGradient` of the substance
/// colors (multiple).
struct RadialProgressGlyph: View {
    var progress: Double
    var colors: [Color]
    var lineWidth: CGFloat = 3

    /// 330° of a full turn — the swept portion; the remaining 30° is the top gap.
    private static let sweepFraction = 330.0 / 360.0

    private var clamped: Double {
        min(max(progress, 0), 1)
    }

    private var arcStyle: AnyShapeStyle {
        if colors.count <= 1 {
            return AnyShapeStyle(colors.first ?? Color(hex: "FFAACC"))
        }
        // Wrap back to the first color so the sweep reads continuously.
        return AnyShapeStyle(
            AngularGradient(
                colors: colors + [colors[0]],
                center: .center,
                startAngle: .degrees(-90),
                endAngle: .degrees(-90 + 330),
            ),
        )
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = (side - lineWidth) / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            // Leading tip of the progress arc: from top (12 o'clock), clockwise.
            let tipAngle = Angle.degrees(-90 + Self.sweepFraction * 360 * clamped)
            let tip = CGPoint(
                x: center.x + radius * CGFloat(cos(tipAngle.radians)),
                y: center.y + radius * CGFloat(sin(tipAngle.radians)),
            )

            ZStack {
                // Faint background track (full 330° sweep).
                Circle()
                    .trim(from: 0, to: Self.sweepFraction)
                    .stroke(
                        .white.opacity(0.22),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round),
                    )
                    .rotationEffect(.degrees(-90))

                // Progress arc.
                Circle()
                    .trim(from: 0, to: Self.sweepFraction * clamped)
                    .stroke(
                        arcStyle,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round),
                    )
                    .rotationEffect(.degrees(-90))

                // Indicator dot at the leading end of the progress arc.
                Circle()
                    .fill(.white)
                    .frame(width: lineWidth * 1.5, height: lineWidth * 1.5)
                    .position(tip)
                    .opacity(clamped > 0.001 ? 1 : 0)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Substance Header (name + color dot)

/// A compact row of active-substance name chips with their color dots — the
/// Lock Screen's answer to "what is currently active?".
struct SubstanceHeaderView: View {
    let substances: [ActiveSubstanceState]

    private static let maxShown = 3

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(substances.prefix(Self.maxShown).enumerated()), id: \.offset) { _, sub in
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: sub.colorHex))
                        .frame(width: 7, height: 7)
                    Text(sub.substanceName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
            if substances.count > Self.maxShown {
                Text("+\(substances.count - Self.maxShown)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Labeled Timer

/// A caption label stacked over a self-updating timer counter.
struct LabeledTimer: View {
    let label: LocalizedStringKey
    let date: Date
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(date, style: .timer)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
        }
    }
}

// MARK: - Lock Screen View

struct LockScreenView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    /// Default must match the app (true). The Live Activity and the in-app graph
    /// share this key/store; a divergent default made the LA draw an un-stacked
    /// curve (single bell) while the app showed the stacked redose curve.
    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru"))
    private var stackRedoses = true

    private var state: PiruActivityAttributes.ContentState {
        context.state
    }
    private var substances: [ActiveSubstanceState] {
        state.activeSubstances
    }
    private var earliestDose: Date {
        SessionTiming.earliestDose(state)
    }
    private var latestEnd: Date {
        SessionTiming.latestEnd(state)
    }

    private var barColors: [Color] {
        let colors = SessionTiming.colors(state)
        return colors.count == 1 ? [colors[0], colors[0]] : colors
    }

    var body: some View {
        VStack(spacing: 8) {
            // What's active — name(s) + color dots.
            SubstanceHeaderView(substances: substances)

            // Timeline graph — updates when Live Activity state is pushed.
            TimelineGraphView(
                substances: substances,
                currentTime: state.lastUpdated,
                compact: true,
                stackRedoses: stackRedoses,
                synchronous: true,
            )
            .frame(height: 72)

            // Thin session-progress bar under the graph.
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
                    colors: barColors,
                    startPoint: .leading,
                    endPoint: .trailing,
                ),
            )

            // Elapsed (left) / Remaining (right).
            HStack(alignment: .firstTextBaseline) {
                LabeledTimer(label: "Elapsed", date: earliestDose, alignment: .leading)
                Spacer(minLength: 12)
                LabeledTimer(label: "Remaining", date: latestEnd, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .activityBackgroundTint(.black.opacity(0.5))
    }
}

// MARK: - Dynamic Island Expanded Views

struct ExpandedLeadingView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    var body: some View {
        LabeledTimer(
            label: "Elapsed",
            date: SessionTiming.earliestDose(context.state),
            alignment: .leading,
        )
    }
}

struct ExpandedTrailingView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    var body: some View {
        LabeledTimer(
            label: "Remaining",
            date: SessionTiming.latestEnd(context.state),
            alignment: .trailing,
        )
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

// MARK: - Dynamic Island Compact Views

struct CompactLeadingView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    var body: some View {
        RadialProgressGlyph(
            progress: SessionTiming.progress(context.state),
            colors: SessionTiming.colors(context.state),
            lineWidth: 3,
        )
        .frame(width: 20, height: 20)
        .padding(.leading, 2)
    }
}

struct CompactTrailingView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    var body: some View {
        Text(SessionTiming.latestEnd(context.state), style: .timer)
            .font(.caption2.monospacedDigit().weight(.medium))
            .foregroundStyle(.white)
            .frame(minWidth: 32)
            .multilineTextAlignment(.trailing)
    }
}

// MARK: - Minimal View

struct MinimalView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    var body: some View {
        RadialProgressGlyph(
            progress: SessionTiming.progress(context.state),
            colors: SessionTiming.colors(context.state),
            lineWidth: 2.5,
        )
        .frame(width: 18, height: 18)
    }
}

// MARK: - Previews

#Preview("Radial glyph") {
    HStack(spacing: 20) {
        RadialProgressGlyph(progress: 0.0, colors: [Color(hex: "FFAACC")])
            .frame(width: 44, height: 44)
        RadialProgressGlyph(progress: 0.35, colors: [Color(hex: "66CCFF")])
            .frame(width: 44, height: 44)
        RadialProgressGlyph(
            progress: 0.72,
            colors: [Color(hex: "FFAACC"), Color(hex: "66CCFF")],
        )
        .frame(width: 44, height: 44)
        RadialProgressGlyph(progress: 1.0, colors: [Color(hex: "AAFF99")])
            .frame(width: 44, height: 44)
    }
    .padding()
    .background(.black)
}
