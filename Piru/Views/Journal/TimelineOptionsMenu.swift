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

/// The vertical timeline's display options as one `Menu` — zoom presets, gap
/// compression, curve mode, and dose-strength scaling. Both surfaces that draw
/// the strip (the pushed Timeline screen's toolbar and the Journal's Timeline
/// grouping) present this same menu over the same app-group defaults, so a
/// change made on either shows on the other.
struct TimelineOptionsMenu<Label: View>: View {
    @Binding var zoom: Double
    @Binding var compressGaps: Bool
    @Binding var pkCurves: Bool
    @Binding var strengthScaling: Bool
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            ForEach(TimelineZoom.presets, id: \.self) { preset in
                Button {
                    zoom = preset
                } label: {
                    if abs(zoom - preset) < 0.01 {
                        SwiftUI.Label(TimelineZoom.label(preset), systemImage: "checkmark")
                    } else {
                        Text(TimelineZoom.label(preset))
                    }
                }
            }
            Divider()
            Toggle("Compress empty time", isOn: $compressGaps)
            Toggle("Scale by Dose Strength", isOn: $strengthScaling)
            Divider()
            Button {
                pkCurves = false
            } label: {
                if pkCurves {
                    Text("Effect curves")
                } else {
                    SwiftUI.Label("Effect curves", systemImage: "checkmark")
                }
                Text("How strongly effects are felt over time")
            }
            Button {
                pkCurves = true
            } label: {
                if pkCurves {
                    SwiftUI.Label("Body load (PK)", systemImage: "checkmark")
                } else {
                    Text("Body load (PK)")
                }
                Text("How much is estimated to remain in your body")
            }
        } label: {
            label()
        }
        .accessibilityLabel(Text("Display Options"))
        .accessibilityValue(Text(verbatim: TimelineZoom.label(zoom)))
    }
}
