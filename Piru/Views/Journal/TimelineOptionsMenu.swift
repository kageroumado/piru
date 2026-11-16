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
nonisolated enum TimelineBubbleStyle: String, Codable {
    /// Name over dose + route chip; the trailing readout beside them.
    case full
    /// Name and dose on one line, no route chip — the bubble demoted to a
    /// label so the curve lane keeps more of the width.
    case compact
}

/// What an effect curve's width is measured against. Persisted as
/// `timelineCurveScale` in the app-group defaults.
nonisolated enum TimelineCurveScale: String, Codable, CaseIterable {
    /// The dose's strength on its substance's own ladder (`amount / heavy`),
    /// so widths compare across substances.
    case doseStrength
    /// Relative to the largest dose of the same substance in the week, month
    /// or quarter up to and including this one, so a substance's usual dose
    /// fills the lane and a lighter one reads as lighter.
    case week
    case month
    case quarter
    /// Relative to the largest dose of the substance in the whole log.
    case allTime

    /// How far back a dose looks for the largest dose to measure against;
    /// `nil` for the ladder, `.infinity` for the whole log.
    var lookback: TimeInterval? {
        switch self {
        case .doseStrength: nil
        case .week: 7 * 86400
        case .month: 30 * 86400
        case .quarter: 90 * 86400
        case .allTime: .infinity
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .doseStrength: "Dose Strength"
        case .week: "Largest Dose, 7 Days"
        case .month: "Largest Dose, 30 Days"
        case .quarter: "Largest Dose, 90 Days"
        case .allTime: "Largest Dose Ever"
        }
    }
}

/// The vertical timeline's display options as one `Menu` — zoom, curve
/// mode and curve scale as submenus that show their current value, then the
/// three toggles.
/// Both surfaces that draw the strip (the pushed Timeline screen's toolbar
/// and the Journal's Timeline grouping) present this same menu over the same
/// app-group defaults, so a change made on either shows on the other.
///
/// Zoom, curves, and gap compression describe the strip's geometry, so with
/// the axis off — the bubbles stacked as a plain list — they are left out
/// rather than offered with no visible effect. (`.disabled` on a menu-style
/// `Picker` inside a `Menu` renders it fully active on iOS 26.)
struct TimelineOptionsMenu<Label: View>: View {
    @Binding var zoom: Double
    @Binding var compressGaps: Bool
    @Binding var pkCurves: Bool
    @Binding var curveScale: TimelineCurveScale
    @Binding var showsAxis: Bool
    @Binding var bubbleStyle: TimelineBubbleStyle
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            TimelineOptionsMenuContent(
                zoom: $zoom,
                compressGaps: $compressGaps,
                pkCurves: $pkCurves,
                curveScale: $curveScale,
                showsAxis: $showsAxis,
                bubbleStyle: $bubbleStyle,
            )
        } label: {
            label()
        }
        .accessibilityLabel(Text("Display Options"))
        .accessibilityValue(Text(verbatim: TimelineZoom.label(zoom)))
    }
}

/// The rows of ``TimelineOptionsMenu``, for a menu that carries them beside
/// other options (the Journal's filter menu).
struct TimelineOptionsMenuContent: View {
    @Binding var zoom: Double
    @Binding var compressGaps: Bool
    @Binding var pkCurves: Bool
    @Binding var curveScale: TimelineCurveScale
    @Binding var showsAxis: Bool
    @Binding var bubbleStyle: TimelineBubbleStyle

    private var compactEntries: Binding<Bool> {
        Binding(
            get: { bubbleStyle == .compact },
            set: { bubbleStyle = $0 ? .compact : .full },
        )
    }

    var body: some View {
        if showsAxis {
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
            // Body-load curves are scaled by concentration, not dose.
            if !pkCurves {
                Picker(selection: $curveScale) {
                    ForEach(TimelineCurveScale.allCases, id: \.self) { scale in
                        Text(scale.title).tag(scale)
                    }
                } label: {
                    Text("Curve Scale")
                    Text(curveScale.title)
                }
                .pickerStyle(.menu)
            }
            Divider()
        }
        Toggle("Show Timeline Axis", isOn: $showsAxis)
        Toggle("Compact Entries", isOn: compactEntries)
        if showsAxis {
            Toggle("Compress Empty Time", isOn: $compressGaps)
        }
    }
}
