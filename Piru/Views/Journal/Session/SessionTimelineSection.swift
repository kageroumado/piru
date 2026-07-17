import SwiftUI
import TipKit

/// The day-detail's timeline graph — a single headerless, full-bleed section.
/// No collapse chevron (the graph earns its place at the top of every session)
/// and no always-on gesture caption: the pan/zoom/inspect hint is a one-time
/// TipKit popover instead. Enlarge and Live Activity live in the ⋯ toolbar menu,
/// so the graph carries no chrome of its own.
struct SessionTimelineSection: View {
    let states: [ActiveSubstanceState]
    let markers: [DoseMarker]
    let laneCount: Int
    @Binding var timelineEnlarged: Bool
    let hasOngoingDose: Bool
    let vitals: SessionVitals?

    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var stackRedoses = true
    @AppStorage(LaneModeDefaults.enabledKey, store: UserDefaults(suiteName: LaneModeDefaults.suite)) private var laneModeEnabled = LaneModeDefaults.enabledDefault
    @AppStorage(LaneModeDefaults.thresholdKey, store: UserDefaults(suiteName: LaneModeDefaults.suite)) private var laneModeThreshold = LaneModeDefaults.thresholdDefault

    var body: some View {
        Section {
            let bandExtra = (vitals?.hasHeartRate == true) ? GraphMetrics.vitalsBandTotal(enlarged: timelineEnlarged) : 0
            AnimatableHeight(height: GraphMetrics.graphHeight(enlarged: timelineEnlarged, laneCount: laneCount, laneModeEnabled: laneModeEnabled, laneModeThreshold: laneModeThreshold) + bandExtra) {
                TimelineGraphView(
                    substances: states,
                    currentTime: .now,
                    compact: false,
                    markers: markers,
                    stackRedoses: stackRedoses,
                    dayBounded: true,
                    vitals: vitals,
                    vitalsBandEnlarged: timelineEnlarged,
                    focusAroundNow: hasOngoingDose,
                    chartFrame: true,
                    synchronous: true,
                )
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.84), value: timelineEnlarged)
            // Bordered-chart treatment: no card fill (clear the shared
            // CardBackground for this row) and a modest top margin so the frame
            // breathes below the nav bar. List rows clip their content to the
            // section's rounded-rect mask (no public opt-out), so the row carries
            // enough side/bottom margin that the flat chart's corners, axis
            // labels, and pan-extent track stay clear of the corner rounding.
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .popoverTip(GraphGestureTip())
        }
        // The screen's 16pt section gap plus the row's own 8pt bottom margin
        // reads as a hole below a fill-less chart; tighten the gap to compensate.
        .listSectionSpacing(12)
    }
}

/// Hosts a fixed-height child whose height is itself the animation driver.
///
/// Animating `.frame(height:)` on a `Canvas` directly makes SwiftUI rasterise the
/// drawing and scale the bitmap from its center — the curves blink out for a frame
/// and the whole graph "pops" from the middle instead of growing down. Conforming
/// the host to `Animatable` on the height forces `body` to re-evaluate on **every**
/// interpolation step, so the `Canvas` re-runs its draw closure at each in-between
/// height and the timeline genuinely grows in place. The child keeps its identity
/// (and so its `@State`-memoised geometry) across the steps — only the proposed
/// height changes.
private struct AnimatableHeight<Content: View>: View, Animatable {
    var height: CGFloat
    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }

    @ViewBuilder var content: Content

    var body: some View {
        content.frame(height: height)
    }
}
