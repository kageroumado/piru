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
            segs.append(Segment(label: "\(threshold.doseFormatted)", level: .threshold, range: threshold...lightLow))
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
            segs.append(Segment(label: "\(heavy.doseFormatted)+", level: .heavy, range: heavy...upper))
        }
        return segs
    }

    @ViewBuilder
    private func segmentView(_ segment: Segment, index: Int) -> some View {
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

                if doseRange.requiresVolumetricDosing(unit: unit) {
                    VolumetricDosingDisclaimer()
                }
            }
        }
    }

    @ViewBuilder
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

// MARK: - Duration Timeline Bar

struct DurationTimelineBar: View {
    let duration: DurationProfile

    private struct Phase {
        let label: LocalizedStringResource
        let minutes: Double
        let color: Color
    }

    private var phases: [Phase] {
        var result: [Phase] = []
        if let onset = duration.onset {
            result.append(Phase(label: "Onset", minutes: onset.midpoint, color: .blue.opacity(0.5)))
        }
        if let comeup = duration.comeup {
            result.append(Phase(label: "Come-up", minutes: comeup.midpoint, color: .cyan))
        }
        if let peak = duration.peak {
            result.append(Phase(label: "Peak", minutes: peak.midpoint, color: .orange))
        }
        if let offset = duration.offset {
            result.append(Phase(label: "Offset", minutes: offset.midpoint, color: .purple.opacity(0.7)))
        }
        if let afterglow = duration.afterglow {
            result.append(Phase(label: "Afterglow", minutes: afterglow.midpoint, color: .gray.opacity(0.4)))
        }
        return result
    }

    private var totalMinutes: Double {
        phases.reduce(0) { $0 + $1.minutes }
    }

    var body: some View {
        if !phases.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(Array(phases.enumerated()), id: \.offset) { _, phase in
                            let fraction = totalMinutes > 0 ? phase.minutes / totalMinutes : 1.0 / Double(phases.count)
                            Rectangle()
                                .fill(phase.color)
                                .frame(width: geo.size.width * fraction)
                        }
                    }
                }
                .frame(height: 6)
                .clipShape(Capsule())

                HStack(spacing: 4) {
                    ForEach(Array(phases.enumerated()), id: \.offset) { _, phase in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(phase.color)
                                .frame(width: 5, height: 5)
                            Text(phase.label)
                                .font(.system(size: 8))
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Duration Info View

struct DurationInfoView: View {
    let duration: DurationProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DurationTimelineBar(duration: duration)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                if let onset = duration.onset {
                    GridRow {
                        phaseLabel("Onset", color: .blue.opacity(0.5))
                        Text(onset.displayString)
                            .font(.caption.monospacedDigit())
                    }
                }
                if let comeup = duration.comeup {
                    GridRow {
                        phaseLabel("Come-up", color: .cyan)
                        Text(comeup.displayString)
                            .font(.caption.monospacedDigit())
                    }
                }
                if let peak = duration.peak {
                    GridRow {
                        phaseLabel("Peak", color: .orange)
                        Text(peak.displayString)
                            .font(.caption.monospacedDigit())
                    }
                }
                if let offset = duration.offset {
                    GridRow {
                        phaseLabel("Offset", color: .purple.opacity(0.7))
                        Text(offset.displayString)
                            .font(.caption.monospacedDigit())
                    }
                }
                if let afterglow = duration.afterglow {
                    GridRow {
                        phaseLabel("Afterglow", color: .gray.opacity(0.4))
                        Text(afterglow.displayString)
                            .font(.caption.monospacedDigit())
                    }
                }
                if let total = duration.total {
                    GridRow {
                        phaseLabel("Total", color: .primary.opacity(0.6))
                        Text(total.displayString)
                            .font(.caption.weight(.medium).monospacedDigit())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func phaseLabel(_ label: LocalizedStringResource, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
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
}
