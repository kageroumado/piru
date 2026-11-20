import SwiftUI

struct DoseLevelIndicator: View {
    let ladder: DoseLadder
    let dose: DoseQuantity?

    private var doseRange: DoseRange {
        ladder.range
    }

    /// The dose read in the ladder's unit — `nil` when it can't be, so no marker
    /// is placed rather than a gram dose read off a milligram scale.
    private var currentDose: Double? {
        dose.flatMap(ladder.reading(of:))
    }

    private var level: DoseLevel? {
        dose.flatMap(ladder.level(of:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let level {
                HStack(spacing: Spacing.sm) {
                    Circle()
                        .fill(level.swiftUIColor)
                        .frame(width: 10, height: 10)
                    Text(level.displayName)
                        .sectionLabel()
                        .foregroundStyle(level.labelColor)
                }
            }

            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    segmentView(segment)
                }
            }
            .frame(height: 6)
            .clipShape(skinChipShape())

            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    Text(segment.label)
                        .font(.chartAnnotation)
                        .foregroundStyle(Theme.secondaryLabel)
                        .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : (index == segments.count - 1 ? .trailing : .center))
                }
            }
        }
        // The ladder conveys the dose's tier by opacity and a marker dot alone;
        // collapse it into one spoken summary. Without a dose it's decorative —
        // the range rows beneath spell the ladder out.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Dose level"))
        .accessibilityValue(accessibilitySummary)
        .accessibilityHidden(level == nil)
    }

    private var accessibilitySummary: Text {
        guard let level, let currentDose else { return Text(verbatim: "") }
        let amount = "\(currentDose.doseFormatted) \(ladder.unit)"
        return Text("\(level.displayName) range, \(amount)")
    }

    private struct Segment {
        let label: String
        let level: DoseLevel
        let range: ClosedRange<Double>?
    }

    private var segments: [Segment] {
        var segs: [Segment] = []
        if let threshold = doseRange.threshold, let lightLow = doseRange.light?.lowerBound, threshold <= lightLow {
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
    private func segmentView(_ segment: Segment) -> some View {
        let isActive = level == segment.level
        Rectangle()
            .fill(segment.level.swiftUIColor.opacity(isActive ? 1.0 : 0.3))
            .overlay {
                if isActive, segment.level != .heavy, let currentDose, let range = segment.range,
                   range.upperBound > range.lowerBound {
                    GeometryReader { geo in
                        let pct = min(max((currentDose - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
                        Circle()
                            .fill(.white)
                            .frame(width: IconSize.dot, height: IconSize.dot)
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

// MARK: - Dose Level Color

extension DoseLevel {
    /// Mark color — dots, discs, bar fills. Text uses ``labelColor``.
    ///
    /// The one scale for a dose level: every surface reads its color here, and
    /// the levels run gray → green → gold → orange → red.
    var swiftUIColor: Color {
        switch self {
        case .sub: .Dose.Sub.accent
        case .threshold: .Dose.Threshold.accent
        case .light: .Dose.Light.accent
        case .common: .Dose.Common.accent
        case .strong: .Dose.Strong.accent
        case .heavy: .Dose.Heavy.accent
        }
    }

    /// Legible text variant of ``swiftUIColor``. Pure yellow is unreadable as
    /// text on a light surface, so `.common` darkens to amber in light mode
    /// while keeping its yellow identity in dark mode; the other hues read
    /// fine in both schemes.
    var labelColor: Color {
        switch self {
        case .sub: .Dose.Sub.text
        case .threshold: .Dose.Threshold.text
        case .light: .Dose.Light.text
        case .common: .Dose.Common.text
        case .strong: .Dose.Strong.text
        case .heavy: .Dose.Heavy.text
        }
    }
}
