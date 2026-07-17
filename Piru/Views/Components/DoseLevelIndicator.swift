import SwiftUI

struct DoseLevelIndicator: View {
    let doseRange: DoseRange
    let currentDose: Double?
    /// Unit spoken in the VoiceOver summary ("Common range, 25 mg").
    var unit: String?

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
        let amount = unit.map { "\(currentDose.doseFormatted) \($0)" } ?? currentDose.doseFormatted
        return Text("\(level.displayName) range, \(amount)")
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

/// Visual identity (label + color) for each phase of an acute experience.
/// Centralised so the timeline bar and the phase rows stay in lock-step — the
/// bar is the overview, the rows the detail, and they must agree on hue.
///
/// The palette traces the arc of an experience: cool and quiet before it
/// begins (blue), rising (teal), warm at the height (orange), cooling on the
/// way down (purple), then neutral residue (gray).
enum ExperiencePhase: CaseIterable {
    case onset
    case comeup
    case peak
    case offset
    case afterglow

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
