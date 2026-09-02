import SwiftUI

/// The vertical timeline's zoom scale — its preset ladder, the pinch bounds,
/// and how a factor reads in the UI.
nonisolated enum TimelineZoom {
    /// Preset ladder, ~×1.6 per step up to the pinch ceiling.
    static let presets: [Double] = [0.6, 1.0, 1.6, 2.5, 5.0]

    /// Pinch-to-zoom bounds; the top preset sits at the ceiling.
    static let range: ClosedRange<Double> = 0.5 ... 5.0

    static func label(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0 ... 1))))×"
    }
}

/// How much of a dose the timeline's bubbles spell out. Persisted as
/// `timelineBubbleStyle` in the app-group defaults.
nonisolated enum TimelineBubbleStyle: String {
    /// Name over dose + route chip; the trailing readout beside them.
    case full
    /// Name and dose on one line, no route chip — the bubble demoted to a
    /// label so the curve lane keeps more of the width.
    case compact
}

/// The vertical timeline's display options as one `Menu` — zoom and curve
/// mode as submenus that show their current value, then the four toggles. Both surfaces that draw the strip (the pushed Timeline screen's
/// toolbar and the Journal's Timeline grouping) present this same menu over
/// the same app-group defaults, so a change made on either shows on the other.
struct TimelineOptionsMenu<Label: View>: View {
    @Binding var zoom: Double
    @Binding var compressGaps: Bool
    @Binding var pkCurves: Bool
    @Binding var strengthScaling: Bool
    @Binding var showsAxis: Bool
    @Binding var bubbleStyle: TimelineBubbleStyle
    @ViewBuilder let label: () -> Label

    private var compactEntries: Binding<Bool> {
        Binding(
            get: { bubbleStyle == .compact },
            set: { bubbleStyle = $0 ? .compact : .full },
        )
    }

    var body: some View {
        Menu {
            Picker(selection: $zoom) {
                ForEach(TimelineZoom.presets, id: \.self) { preset in
                    Text(TimelineZoom.label(preset)).tag(preset)
                }
            } label: {
                Text("Zoom")
                Text(TimelineZoom.label(zoom))
            }
            .pickerStyle(.menu)
            Picker(selection: $pkCurves) {
                Text("Effect curves").tag(false)
                Text("Body load (PK)").tag(true)
            } label: {
                Text("Curves")
                Text(pkCurves ? "Body load (PK)" : "Effect curves")
            }
            .pickerStyle(.menu)
            Divider()
            Toggle("Show Timeline Axis", isOn: $showsAxis)
            Toggle("Compact Entries", isOn: compactEntries)
            Toggle("Compress Empty Time", isOn: $compressGaps)
            Toggle("Scale by Dose Strength", isOn: $strengthScaling)
        } label: {
            label()
        }
        .accessibilityLabel(Text("Display Options"))
        .accessibilityValue(Text(verbatim: TimelineZoom.label(zoom)))
    }
}
