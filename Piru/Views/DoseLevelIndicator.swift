import SwiftUI

struct DoseLevelIndicator: View {
    let doseRange: DoseRange
    let currentDose: Double?

    private var level: DoseLevel? {
        guard let currentDose else { return nil }
        return doseRange.level(for: currentDose)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let level {
                HStack(spacing: 6) {
                    Circle()
                        .fill(level.swiftUIColor)
                        .frame(width: 10, height: 10)
                    Text(level.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(level.swiftUIColor)
                }
            }

            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    segmentView(segment, index: index)
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())

            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    Text(segment.label)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.secondaryLabel)
                        .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : (index == segments.count - 1 ? .trailing : .center))
                }
            }
        }
    }

    private struct Segment {
        let label: String
        let level: DoseLevel
        let range: ClosedRange<Double>?
    }

    private var segments: [Segment] {
        var segs: [Segment] = []
        if let threshold = doseRange.threshold, let lightLow = doseRange.light?.lowerBound {
            segs.append(Segment(label: "\(threshold.doseFormatted)", level: .threshold, range: threshold ... lightLow))
        }
        if let light = doseRange.light {
            segs.append(Segment(label: "\(light.lowerBound.doseFormatted)", level: .light, range: light))
        }
        if let common = doseRange.common {
            segs.append(Segment(label: "\(common.lowerBound.doseFormatted)", level: .common, range: common))
        }
        if let strong = doseRange.strong {
            segs.append(Segment(label: "\(strong.lowerBound.doseFormatted)", level: .strong, range: strong))
        }
        if let heavy = doseRange.heavy {
            let upper = heavy * 1.5
            segs.append(Segment(label: "\(heavy.doseFormatted)+", level: .heavy, range: heavy ... upper))
        }
        return segs
    }

    @ViewBuilder
    private func segmentView(_ segment: Segment, index _: Int) -> some View {
        let isActive = level == segment.level
        Rectangle()
            .fill(segment.level.swiftUIColor.opacity(isActive ? 1.0 : 0.3))
            .overlay {
                if isActive, segment.level != .heavy, let currentDose, let range = segment.range {
                    GeometryReader { geo in
                        let pct = min(max((currentDose - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
                        Circle()
                            .fill(.white)
                            .frame(width: 8, height: 8)
                            .shadow(radius: 1)
                            .position(x: geo.size.width * pct, y: geo.size.height / 2)
                    }
                }
            }
    }
}

// MARK: - Inline Dose Level Badge (for amount field)

struct DoseLevelBadge: View {
    let level: DoseLevel

    var body: some View {
        Text("(\(String(localized: level.displayName)))")
            .font(.caption.weight(.semibold))
            .foregroundStyle(level.swiftUIColor)
    }
}

// MARK: - Dose Info View

struct DoseInfoView: View {
    let substance: Substance
    let route: RouteOfAdministration
    let currentDose: Double?

    private var doseRange: DoseRange? {
        substance.doseRange(for: route)
    }

    var body: some View {
        if let doseRange {
            VStack(alignment: .leading, spacing: 10) {
                let unit = substance.unit(for: route)
                DoseLevelIndicator(doseRange: doseRange, currentDose: currentDose)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    if let threshold = doseRange.threshold {
                        GridRow {
                            doseLabel("Threshold", level: DoseLevel.threshold)
                            Text("\(threshold.doseFormatted) \(unit)")
                                .font(.caption.monospacedDigit())
                        }
                    }
                    if let light = doseRange.light {
                        GridRow {
                            doseLabel("Light", level: DoseLevel.light)
                            Text("\(light.lowerBound.doseFormatted) - \(light.upperBound.doseFormatted) \(unit)")
                                .font(.caption.monospacedDigit())
                        }
                    }
                    if let common = doseRange.common {
                        GridRow {
                            doseLabel("Common", level: DoseLevel.common)
                            Text("\(common.lowerBound.doseFormatted) - \(common.upperBound.doseFormatted) \(unit)")
                                .font(.caption.monospacedDigit())
                        }
                    }
                    if let strong = doseRange.strong {
                        GridRow {
                            doseLabel("Strong", level: DoseLevel.strong)
                            Text("\(strong.lowerBound.doseFormatted) - \(strong.upperBound.doseFormatted) \(unit)")
                                .font(.caption.monospacedDigit())
                        }
                    }
                    if let heavy = doseRange.heavy {
                        GridRow {
                            doseLabel("Heavy", level: DoseLevel.heavy)
                            Text("\(heavy.doseFormatted)+ \(unit)")
                                .font(.caption.monospacedDigit())
                        }
                    }
                }

                switch doseRange.dosingPrecision(unit: unit) {
                case .critical: VolumetricDosingDisclaimer()
                case .recommended: PreciseScaleNote()
                case .none: EmptyView()
                }
            }
        }
    }

    private func doseLabel(_ label: LocalizedStringResource, level: DoseLevel) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(level.swiftUIColor)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }
}

// MARK: - Volumetric Dosing Disclaimer

struct VolumetricDosingDisclaimer: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("Extremely Potent Substance")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                Text("Active in microgram (µg) quantities — 1/1000th of a milligram. Volumetric dosing is required at all times for safe and accurate measurement. Never attempt to measure doses by eye or with standard scales.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}

/// Shown for plant entries dosed in active-compound content (unit like "mg THC"):
/// the ladder is molecule mg, not plant weight, so explain the conversion.
struct THCContentNote: View {
    var body: some View {
        Label {
            Text("Doses are milligrams of THC, not flower weight. Flower needed ≈ desired THC ÷ the strain's %THC (e.g. 3 mg ÷ 18% ≈ 0.02 g). Smoking loses 50–80% to combustion, so real flower amounts run higher.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        } icon: {
            Image(systemName: "leaf")
                .foregroundStyle(.secondary)
        }
    }
}

/// Softer guidance for low-milligram substances: a precise scale matters, but
/// they're not active in microgram quantities so the stronger banner would mislead.
struct PreciseScaleNote: View {
    var body: some View {
        Label {
            Text("Dosed in low milligrams — use a precise milligram scale (0.001 g resolution). Hard to measure accurately by eye or with kitchen scales.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        } icon: {
            Image(systemName: "scalemass")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Experience Phase

/// Visual identity (label + colour) for each phase of an acute experience.
/// Centralised so the timeline bar and the phase rows stay in lock-step — the
/// bar is the overview, the rows the detail, and they must agree on hue.
///
/// The palette traces the arc of an experience: cool and quiet before it
/// begins (blue), rising (teal), warm at the height (orange), cooling on the
/// way down (purple), then neutral residue (gray).
private enum ExperiencePhase: CaseIterable {
    case onset, comeup, peak, offset, afterglow

    var label: LocalizedStringResource {
        switch self {
        case .onset: "Onset"
        case .comeup: "Come-up"
        case .peak: "Peak"
        case .offset: "Offset"
        case .afterglow: "Afterglow"
        }
    }

    var color: Color {
        switch self {
        case .onset: .blue
        case .comeup: .teal
        case .peak: .orange
        case .offset: .purple
        case .afterglow: Color(.systemGray3)
        }
    }

    func range(in profile: DurationProfile) -> DurationRange? {
        switch self {
        case .onset: profile.onset
        case .comeup: profile.comeup
        case .peak: profile.peak
        case .offset: profile.offset
        case .afterglow: profile.afterglow
        }
    }
}

// MARK: - Duration Timeline Bar

/// A single legible bar that shows the *shape* of the experience — how the
/// phases divide the timeline proportionally by their typical length. No text
/// legend: the rows beneath carry the same colours and spell each phase out.
struct DurationTimelineBar: View {
    let duration: DurationProfile

    private var segments: [(phase: ExperiencePhase, minutes: Double)] {
        ExperiencePhase.allCases.compactMap { phase in
            guard let range = phase.range(in: duration) else { return nil }
            return (phase, range.midpoint)
        }
    }

    private var totalMinutes: Double {
        segments.reduce(0) { $0 + $1.minutes }
    }

    var body: some View {
        if !segments.isEmpty {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        let fraction = totalMinutes > 0
                            ? segment.minutes / totalMinutes
                            : 1.0 / Double(segments.count)
                        segment.phase.color
                            .frame(width: geo.size.width * fraction)
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Duration Phase Rows

/// The labelled per-phase rows that accompany a ``DurationTimelineBar``,
/// styled to match ``DoseRangeRows`` so the Dosage and Duration cards read as
/// siblings. Each row flattens into its own list cell (gaining the standard
/// hairline separators); ``total`` is emphasised as the summary line.
struct DurationPhaseRows: View {
    let duration: DurationProfile

    var body: some View {
        ForEach(ExperiencePhase.allCases, id: \.self) { phase in
            if let range = phase.range(in: duration) {
                row(phase.label, value: range.displayString, color: phase.color)
            }
        }
        if let total = duration.total {
            HStack {
                Text("Total")
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Spacer()
                Text(total.displayString)
                    .monospacedDigit()
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
        }
    }

    private func row(_ label: LocalizedStringResource, value: String, color: Color) -> some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .font(.subheadline)
    }
}

// MARK: - Dose Range Rows

/// The labelled threshold/light/common/strong/heavy rows that accompany a
/// ``DoseLevelIndicator``. Shared between the substance detail screen and the
/// logged-entry detail screen so both render the dose ladder identically.
struct DoseRangeRows: View {
    let doseRange: DoseRange
    let unit: String

    var body: some View {
        if let threshold = doseRange.threshold {
            row("Threshold", value: "\(threshold.doseFormatted) \(unit)", level: .threshold)
        }
        if let light = doseRange.light {
            row("Light", value: "\(light.lowerBound.doseFormatted) – \(light.upperBound.doseFormatted) \(unit)", level: .light)
        }
        if let common = doseRange.common {
            row("Common", value: "\(common.lowerBound.doseFormatted) – \(common.upperBound.doseFormatted) \(unit)", level: .common)
        }
        if let strong = doseRange.strong {
            row("Strong", value: "\(strong.lowerBound.doseFormatted) – \(strong.upperBound.doseFormatted) \(unit)", level: .strong)
        }
        if let heavy = doseRange.heavy {
            row("Heavy", value: "\(heavy.doseFormatted)+ \(unit)", level: .heavy)
        }
    }

    private func row(_ label: LocalizedStringResource, value: String, level: DoseLevel) -> some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(level.swiftUIColor)
                    .frame(width: 8, height: 8)
                Text(label)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .font(.subheadline)
    }
}

// MARK: - Duration Info View

/// Composes the redesigned duration card: a legible timeline bar over spacious
/// per-phase rows. Emitted as flattened siblings (no wrapping `VStack`) so the
/// rows pick up the enclosing list's separators, exactly like the Dosage card.
struct DurationInfoView: View {
    let duration: DurationProfile

    var body: some View {
        DurationTimelineBar(duration: duration)
            .padding(.vertical, 6)
        DurationPhaseRows(duration: duration)
    }
}

// MARK: - Dose Level Color

extension DoseLevel {
    var swiftUIColor: Color {
        switch self {
        case .sub: .gray
        case .threshold: .blue
        case .light: .green
        case .common: .yellow
        case .strong: .orange
        case .heavy: .red
        }
    }

    /// Legible text variant of ``swiftUIColor``. Pure yellow is unreadable as
    /// text on a light surface, so `.common` darkens to amber in light mode
    /// while keeping its yellow identity in dark mode; the other hues read
    /// fine in both schemes.
    var labelColor: Color {
        self == .common ? Theme.legibleYellow : swiftUIColor
    }
}
