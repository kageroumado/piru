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
        state.endDate ?? state.lastUpdated.addingTimeInterval(3_600)
    }

    /// The whole session, earliest dose to latest end, for a session that has
    /// run its course.
    static func span(_ state: PiruActivityAttributes.ContentState) -> Range<Date> {
        let start = earliestDose(state)
        return start ..< max(start, latestEnd(state))
    }

    /// Substance colors, falling back to the app's soft-pink accent when empty.
    static func colors(_ state: PiruActivityAttributes.ContentState) -> [Color] {
        let colors = state.activeSubstances.map(\.tint.color)
        return colors.isEmpty ? [P3Color.neutral.color] : colors
    }

    /// The next phase boundary any active substance will cross, evaluated at
    /// `asOf` (defaulting to the real current time, **not** `state.lastUpdated`).
    /// `phase` is the phase being *entered* at `date`, tinted with that
    /// substance's color. `nil` once every substance has fully run its course.
    ///
    /// Chosen when the view renders: a content update, the `staleDate`
    /// re-render, or a system redraw. ActivityKit has no time-driven way to
    /// swap a label, so while the app is suspended the choice holds until the
    /// next render and its countdown rests at 0m once the boundary passes
    /// (the graph rail, rings and Elapsed keep moving on their own).
    static func nextTransition(
        _ state: PiruActivityAttributes.ContentState, asOf now: Date = .now,
    ) -> PhaseTransition? {
        var next: PhaseTransition?
        for sub in state.activeSubstances {
            var boundaries: [(SessionPhase, Double)] = [
                (.comeup, sub.onsetEndMinutes),
                (.peak, sub.comeupEndMinutes),
                (.offset, sub.peakEndMinutes),
            ]
            if sub.afterglowEndMinutes != nil {
                boundaries.append((.afterglow, sub.offsetEndMinutes))
            }
            boundaries.append((.ended, sub.totalMinutes))

            for (phase, minutes) in boundaries {
                let date = sub.doseTimestamp.addingTimeInterval(minutes * 60)
                guard date > now else { continue }
                if next == nil || date < next!.date {
                    next = PhaseTransition(phase: phase, date: date, color: sub.tint.color)
                }
            }
        }
        return next
    }
}

/// An upcoming phase change: which phase begins, when, and the color of the
/// substance it belongs to.
struct PhaseTransition {
    let phase: SessionPhase
    let date: Date
    let color: Color
}

/// Phases a dose transitions *into*, each with a glyph so the island can show
/// "next phase in 0h42" without spending width on words.
enum SessionPhase {
    case comeup
    case peak
    case offset
    case afterglow
    case ended

    var symbolName: String {
        switch self {
        case .comeup: DosePhaseGlyph.comeup
        case .peak: DosePhaseGlyph.peak
        case .offset: DosePhaseGlyph.offset
        case .afterglow: DosePhaseGlyph.afterglow
        case .ended: DosePhaseGlyph.ended
        }
    }

    /// VoiceOver label. `.ended`'s countdown is literally the time remaining,
    /// so it reuses the existing "Remaining" key.
    var title: LocalizedStringKey {
        switch self {
        case .comeup: "Come-up"
        case .peak: "Peak"
        case .offset: "Offset"
        case .afterglow: "Afterglow"
        case .ended: "Remaining"
        }
    }
}

// MARK: - Hours/Minutes Timer Format

/// Compact hours+minutes with no seconds (e.g. `3h 2m`), auto-updating on
/// minute boundaries via `Text(.dateRange(…), format: .hoursMinutes)`.
///
/// Two constraints pick this shape:
/// - `Text(_:style: .timer)` always shows seconds and is greedy for width,
///   so it stretches the compact island full-width on device.
/// - The Live Activity render server decodes the format style from the
///   archived view, so it must be a *Foundation* type — a custom
///   `DiscreteFormatStyle` defined in this extension fails to decode and the
///   system silently falls back to the all-text-redacted placeholder render.
///   `Date.ComponentsFormatStyle` is built in and formats a `Range<Date>`, so
///   `.dateRange(startingAt:)`/`.dateRange(endingAt:)` cover both count-up
///   (elapsed) and count-down (next phase) without sign issues.
extension FormatStyle where Self == Date.ComponentsFormatStyle {
    static var hoursMinutes: Date.ComponentsFormatStyle {
        .components(style: .narrow, fields: [.hour, .minute])
    }
}

// MARK: - Session Rings

/// Watch-activity-style concentric rings for the two most recent substances.
///
/// The full circle represents the whole session window (earliest dose →
/// latest projected end). Each substance's arc runs from its own dose time to
/// "now", so the session-opening dose starts at 12 o'clock and a later redose
/// starts partway around — the ring doubles as a clock of the session.
///
/// Each arc is a `ProgressView(timerInterval:)`, which the system advances
/// between renders, so the rings keep time while the app is suspended. A
/// widget renders it as the system capacity gauge (custom progress styles are
/// ignored there), so the gauge supplies the stroke and track; the ring is
/// turned to start at its dose and masked to end where that dose's curve does.
struct SessionRingsView: View {
    let state: PiruActivityAttributes.ContentState
    /// How far each inner ring is inset from the one around it.
    var ringSpacing: CGFloat = 4.5

    private struct Ring: Identifiable {
        let id: Int
        let color: Color
        let startFraction: Double
        /// Where this dose's own curve runs out; the arc never passes it.
        let endFraction: Double
        /// The time one full turn takes, starting at this dose.
        let turn: ClosedRange<Date>
    }

    private var rings: [Ring] {
        let sessionStart = SessionTiming.earliestDose(state)
        let span = SessionTiming.latestEnd(state).timeIntervalSince(sessionStart)
        guard span > 0 else { return [] }

        func fraction(_ date: Date) -> Double {
            min(max(date.timeIntervalSince(sessionStart) / span, 0), 1)
        }

        let newestFirst = state.activeSubstances
            .sorted { $0.doseTimestamp > $1.doseTimestamp }
            .prefix(2)
        return newestFirst.enumerated().map { index, sub in
            Ring(
                id: index,
                color: sub.tint.color,
                startFraction: fraction(sub.doseTimestamp),
                endFraction: fraction(sub.endDate),
                turn: sub.doseTimestamp ... sub.doseTimestamp.addingTimeInterval(span),
            )
        }
    }

    var body: some View {
        ZStack {
            ForEach(rings) { ring in
                ProgressView(timerInterval: ring.turn, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(ring.color)
                .mask { SessionWedge(fraction: ring.endFraction - ring.startFraction) }
                .rotationEffect(.degrees(ring.startFraction * 360))
                .padding(CGFloat(ring.id) * ringSpacing)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A pie slice from 12 o'clock clockwise through `fraction` of a turn,
/// reaching past the frame's corners so it never clips a ring's stroke.
private struct SessionWedge: Shape {
    let fraction: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: max(rect.width, rect.height),
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + fraction * 360),
            clockwise: false,
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Timer Components

/// "Elapsed" caption stacked over an auto-updating `1h 4m` counter.
struct ElapsedTimerView: View {
    let sessionStart: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Elapsed")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(.dateRange(startingAt: sessionStart), format: .hoursMinutes)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: 56, alignment: .leading)
        }
    }
}

/// Upcoming phase (name + glyph) with a countdown, e.g. "Peak ✦ / 46m".
/// Icon tinted with the color of the substance whose boundary is next.
struct NextPhaseView: View {
    /// - `compact`: countdown + icon only (Dynamic Island compact trailing).
    /// - `stacked`: name + icon over the countdown, trailing-aligned — mirrors
    ///   `ElapsedTimerView`'s stacked style (expanded island + Lock Screen).
    enum Style {
        case compact
        case stacked
    }

    let transition: PhaseTransition
    var style: Style = .stacked

    var body: some View {
        Group {
            switch style {
            case .compact:
                HStack(spacing: 4) {
                    countdown
                    icon(size: CompactMetrics.iconFontSize)
                        .frame(width: CompactMetrics.iconSide, height: CompactMetrics.iconSide)
                }
            case .stacked:
                // Mirror of the leading side's [ring + text stack]: the phase
                // glyph matches the rings' 26 pt footprint.
                HStack(spacing: 8) {
                    VStack(alignment: .trailing, spacing: 1) {
                        title
                        countdown
                    }
                    icon(size: 17)
                        .frame(width: 26, height: 26)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(transition.phase.title))
        .accessibilityValue(Text(.dateRange(endingAt: transition.date), format: .hoursMinutes))
    }

    private var title: some View {
        Text(transition.phase.title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
    }

    /// Auto-updating text reserves width for its widest future string and the
    /// ActivityKit renderer ignores `fixedSize()` — unbounded, it stretches the
    /// compact island to full width, so it needs an explicit cap. The renderer
    /// also ignores the *frame alignment* for the glyphs (they draw leading in
    /// the reservation); `multilineTextAlignment(.trailing)` is what actually
    /// right-aligns them, pushing the reservation's slack inward (invisible).
    private var countdown: some View {
        Text(.dateRange(endingAt: transition.date), format: .hoursMinutes)
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 50, alignment: .trailing)
    }

    private func icon(size: CGFloat) -> some View {
        Image(systemName: transition.phase.symbolName)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(transition.color)
            .accessibilityHidden(true)
    }
}

// MARK: - Lock Screen View

struct LockScreenView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    /// Default must match the app (true). The Live Activity and the in-app graph
    /// share this key/store; a divergent default made the LA draw an un-stacked
    /// curve (single bell) while the app showed the stacked redose curve.
    @AppStorage("stackRedoses", store: UserDefaults(suiteName: AppIdentity.appGroup))
    private var stackRedoses = true

    private var state: PiruActivityAttributes.ContentState {
        context.state
    }
    private var earliestDose: Date {
        SessionTiming.earliestDose(state)
    }

    /// Once every curve has run out the card collapses to one row, drawn at
    /// the stale date the app sets on the last dose's end. That repaint needs
    /// no app, so a card iOS leaves up until the app next wakes (or until
    /// ActivityKit's own expiry) is one line rather than a finished graph
    /// under a clock that keeps counting.
    var body: some View {
        Group {
            if state.hasRunOut() {
                CompletedSessionView(state: state)
            } else {
                liveCard
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Opaque black, not a translucent wash. A half-black tint lets the
        // wallpaper through, so the card's actual lightness is whatever the user
        // happens to have behind it — and this content is authored for a dark
        // surface (hardcoded `.white` values, `.secondary` captions), so on a
        // bright wallpaper it loses contrast. Black is also what the Dynamic
        // Island always is and what survives the Always-On display's reduced
        // luminance, so all three presentations read as one surface.
        // Adding `containerBackground(.black, for: .widget)` changes nothing: the
        // Lock Screen composites the card with vibrancy either way. The faint
        // wallpaper seam across the card comes from the system.
        .activityBackgroundTint(.black)
        .activitySystemActionForegroundColor(.white)
        // `.secondary` resolves to a *dark* gray in the light color scheme,
        // which is invisible on black, so pin the scheme the content is drawn for.
        .environment(\.colorScheme, .dark)
    }

    /// Lock Screen Live Activities are capped at 160 pt tall. The content stack
    /// must stay comfortably under that or the system compresses spacing and
    /// padding to force-fit — which reads as "broken padding". Budget:
    /// graph 80 + timer row ~29 + spacing 8 + padding 24 ≈ 141.
    private var liveCard: some View {
        VStack(spacing: 8) {
            // Curves change only with a push; the now rail advances on its own.
            TimelineGraphView(
                substances: state.activeSubstances,
                currentTime: .now,
                compact: true,
                stackRedoses: stackRedoses,
                timeDrivenNow: true,
                synchronous: true,
            )
            .frame(height: 80)

            // Same design as the expanded island, below the graph: rings +
            // stacked Elapsed (left), stacked next-phase (right). The rings
            // carry session progress, so no separate bar.
            HStack {
                HStack(spacing: 8) {
                    SessionRingsView(state: state)
                        .frame(width: 26, height: 26)
                    ElapsedTimerView(sessionStart: earliestDose)
                }
                Spacer(minLength: 12)
                // The card collapses at the end, so a transition is always
                // ahead here; the guard covers a render racing that instant.
                if let transition = SessionTiming.nextTransition(state) {
                    NextPhaseView(transition: transition, style: .stacked)
                }
            }
        }
    }
}

/// The Lock Screen card for a session that has run its course: the full
/// rings, "Session complete" over the session's length (fixed, where the live
/// card's Elapsed counts up), and the ended glyph.
struct CompletedSessionView: View {
    let state: PiruActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            SessionRingsView(state: state)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("Session complete")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(SessionTiming.span(state), format: .hoursMinutes)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Image(systemName: DosePhaseGlyph.ended)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SessionTiming.colors(state).first ?? .white)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Dynamic Island Expanded Views

struct ExpandedLeadingView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    var body: some View {
        HStack(spacing: 8) {
            SessionRingsView(state: context.state)
                .frame(width: 26, height: 26)
            ElapsedTimerView(sessionStart: SessionTiming.earliestDose(context.state))
        }
        .padding(.leading, 6)
        .padding(.top, 2)
    }
}

struct ExpandedTrailingView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    var body: some View {
        Group {
            if let transition = SessionTiming.nextTransition(context.state) {
                NextPhaseView(transition: transition, style: .stacked)
            }
        }
        .padding(.trailing, 6)
        .padding(.top, 2)
    }
}

struct ExpandedBottomView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    @AppStorage("stackRedoses", store: UserDefaults(suiteName: AppIdentity.appGroup))
    private var stackRedoses = true

    var body: some View {
        TimelineGraphView(
            substances: context.state.activeSubstances,
            currentTime: .now,
            compact: true,
            stackRedoses: stackRedoses,
            timeDrivenNow: true,
            synchronous: true,
        )
        .frame(height: 58)
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }
}

// MARK: - Dynamic Island Compact Views

/// Mirror of the compact trailing side: icon on the outside, time on the
/// inside — rings + elapsed. `CompactMetrics` keeps the two sides symmetric.
struct CompactLeadingView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    var body: some View {
        HStack(spacing: 4) {
            SessionRingsView(state: context.state, ringSpacing: 4)
                .frame(width: CompactMetrics.iconSide, height: CompactMetrics.iconSide)
            elapsed
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: 50, alignment: .leading)
        }
    }

    /// Counts up while the session runs, then holds at the session's length.
    private var elapsed: Text {
        if context.state.hasRunOut() {
            Text(SessionTiming.span(context.state), format: .hoursMinutes)
        } else {
            Text(.dateRange(startingAt: SessionTiming.earliestDose(context.state)), format: .hoursMinutes)
        }
    }
}

/// Shared sizing for the compact island's two sides.
enum CompactMetrics {
    static let iconSide: CGFloat = 18
    static let iconFontSize: CGFloat = 13
}

struct CompactTrailingView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    var body: some View {
        if let transition = SessionTiming.nextTransition(context.state) {
            NextPhaseView(transition: transition, style: .compact)
        } else {
            // No upcoming boundary — the session has run its course (elapsed
            // already lives on the leading side).
            Image(systemName: DosePhaseGlyph.ended)
                .font(.system(size: CompactMetrics.iconFontSize, weight: .semibold))
                .foregroundStyle(SessionTiming.colors(context.state).first ?? .white)
                .frame(width: CompactMetrics.iconSide, height: CompactMetrics.iconSide)
                .accessibilityLabel("Session complete")
        }
    }
}

// MARK: - Minimal View

struct MinimalView: View {
    let context: ActivityViewContext<PiruActivityAttributes>

    var body: some View {
        SessionRingsView(state: context.state, ringSpacing: 4)
            .frame(width: 22, height: 22)
    }
}
