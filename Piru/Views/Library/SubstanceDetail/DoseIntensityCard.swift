import SwiftUI

/// The drug.community intensity spectrum as a circular, draggable dose dial.
///
/// The dial reads as a dose slider bent into an arc: drag the thumb across the
/// dose bands (Threshold → Overdose) and the card updates to show what the
/// experience is like at that dose, the effects most reported there, and — on
/// the high bands — a caution/emergency callout. Dose ranges come from Piru's
/// own Dose & Duration data, so the dial extends the science card rather than
/// paralleling it.
struct DoseIntensityCard: View {
    let bands: [SpectrumBand]
    /// band index → localized dose-range text (e.g. "30–60 mg"), from Piru's
    /// dose ladder. Absent bands show the band name alone.
    let bandDoseText: [Int: String]
    let citationSlug: String
    let citationDeepLink: URL?

    @State private var selected: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let bandColors: [Color] = [
        Color(hex: "34C759"), Color(hex: "8ED04A"), Color(hex: "E0B93A"),
        Color(hex: "E8940C"), Color(hex: "E5613D"), Color(hex: "E5484D"),
    ]

    private var current: SpectrumBand {
        bands[min(selected, bands.count - 1)]
    }
    private func color(_ i: Int) -> Color {
        Self.bandColors[min(i, Self.bandColors.count - 1)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BY DOSE", comment: "Intensity dial eyebrow")
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(Theme.secondaryLabel)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)

            gauge
                .frame(height: 200)
                .overlay(centerReadout)
                .padding(.top, 2)

            Label {
                Text("Drag to explore doses", comment: "Intensity dial interaction hint")
            } icon: {
                Image(systemName: "arrow.left.and.right")
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryLabel)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)

            Text(current.summary)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .padding(.vertical, 8)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selected)

            if !current.topEffects.isEmpty {
                mostReported
            }

            SourceAttributionRow(
                slug: citationSlug,
                label: "Intensity spectrum",
                deepLink: citationDeepLink,
            )
            .padding(.top, 6)
        }
        .padding(16)
        .themeCard()
        .sensoryFeedback(.selection, trigger: selected)
        .onAppear { selected = defaultBand }
    }

    /// Open on the "Common" band when present, else the middle band.
    private var defaultBand: Int {
        bands.firstIndex { $0.bandKey == "Common" } ?? (bands.count / 2)
    }

    /// What VoiceOver speaks for the dial's current value: the band name plus its
    /// dose range (e.g. "Common, 75–150 mg"), so an adjust announces something
    /// meaningful rather than "band 3 of 6".
    private var accessibilityValueLabel: String {
        if let dose = bandDoseText[current.bandIndex] {
            return "\(current.localizedBandName), \(dose)"
        }
        return current.localizedBandName
    }

    // MARK: gauge

    private var gauge: some View {
        IntensityGauge(
            bandCount: bands.count,
            selected: selected,
            colors: bands.indices.map(color),
            valueLabel: accessibilityValueLabel,
        ) { newIndex in
            let clamped = max(0, min(bands.count - 1, newIndex))
            guard clamped != selected else { return }
            selected = clamped
        }
    }

    private var centerReadout: some View {
        VStack(spacing: 2) {
            Text(bandDoseText[current.bandIndex] ?? current.localizedBandName)
                .font(.system(size: 27, weight: .heavy, design: .rounded))
                .foregroundStyle(current.isOverdose ? color(current.bandIndex) : .primary)
                .contentTransition(reduceMotion ? .identity : .numericText())
            if bandDoseText[current.bandIndex] != nil {
                Text(current.localizedBandName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color(current.bandIndex))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(current.localizedBandName)
        .accessibilityValue(bandDoseText[current.bandIndex].map { Text($0) } ?? Text(""))
        .offset(y: 10)
    }

    private var mostReported: some View {
        let maxFreq = max(current.topEffects.map(\.frequency).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text("MOST REPORTED AT THIS DOSE", comment: "Intensity dial effects heading")
                .font(.caption2.weight(.bold))
                .tracking(0.4)
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.bottom, 2)
            ForEach(current.topEffects.prefix(3), id: \.name) { eff in
                HStack(spacing: 10) {
                    Text(eff.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    FrequencyBar(fraction: Double(eff.frequency) / Double(maxFreq))
                        .frame(width: 78)
                    Text("\(eff.frequency)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondaryLabel)
                        .frame(width: 30, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 4)
    }
}

/// A thin capsule meter showing a 0…1 proportion. Matches the app's PotencyBars
/// idiom (track + accent fill).
struct FrequencyBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.accent.opacity(0.14))
                Capsule().fill(Theme.accent)
                    .frame(width: max(6, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 7)
    }
}

/// The circular arc gauge: six colored segments that fill up to the selected
/// band, with a draggable thumb. Pure drawing + a drag gesture; selection state
/// is owned by the parent.
private struct IntensityGauge: View {
    let bandCount: Int
    let selected: Int
    let colors: [Color]
    let valueLabel: String
    var onSelect: (Int) -> Void

    // Arc opens at the bottom: sweeps 240° clockwise from 150° (lower-left)
    // through the top to 30° (lower-right); the 120° gap sits at the bottom.
    private let startDeg = 150.0
    private let sweepDeg = 240.0
    private let lineWidth = 17.0
    private let gapDeg = 4.0

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = CGPoint(x: size.width / 2, y: size.height * 0.72)
            let radius = min(size.width / 2, size.height * 0.72) - lineWidth
            Canvas { context, _ in
                draw(in: context, center: center, radius: radius)
            }
            .contentShape(Rectangle())
            // High priority so a touch starting on the dial drives selection
            // instead of being stolen by the enclosing ScrollView's scroll.
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onSelect(band(for: value.location, center: center, radius: radius))
                    },
            )
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Dose intensity", comment: "Dial accessibility label"))
        .accessibilityValue(Text(valueLabel))
        .accessibilityHint(Text("Swipe up or down to change the dose", comment: "Dial accessibility hint"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSelect(min(bandCount - 1, selected + 1))
            case .decrement: onSelect(max(0, selected - 1))
            default: break
            }
        }
    }

    private func draw(in context: GraphicsContext, center: CGPoint, radius: Double) {
        let seg = sweepDeg / Double(bandCount)
        let track = Color.primary.opacity(scheme == .dark ? 0.14 : 0.08)
        for i in 0 ..< bandCount {
            let a0 = startDeg + Double(i) * seg + gapDeg / 2
            let a1 = startDeg + Double(i + 1) * seg - gapDeg / 2
            var path = Path()
            path.addArc(
                center: center, radius: radius,
                startAngle: .degrees(a0), endAngle: .degrees(a1), clockwise: false,
            )
            context.stroke(
                path,
                with: .color(i <= selected ? colors[i] : track),
                style: StrokeStyle(lineWidth: i == selected ? lineWidth + 6 : lineWidth, lineCap: .round),
            )
        }
        let midDeg = startDeg + (Double(selected) + 0.5) * seg
        let thumb = point(center: center, radius: radius, degrees: midDeg)
        context.fill(
            Path(ellipseIn: CGRect(x: thumb.x - 15, y: thumb.y - 15, width: 30, height: 30)),
            with: .color(scheme == .dark ? Color(hex: "1C1C1E") : .white),
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: thumb.x - 12.5, y: thumb.y - 12.5, width: 25, height: 25)),
            with: .color(colors[min(selected, colors.count - 1)]),
            lineWidth: 4,
        )
    }

    private func point(center: CGPoint, radius: Double, degrees: Double) -> CGPoint {
        let r = degrees * .pi / 180
        return CGPoint(x: center.x + radius * cos(r), y: center.y + radius * sin(r))
    }

    /// Map a touch location to a band index. The bottom gap clamps to the nearest end.
    private func band(for location: CGPoint, center: CGPoint, radius _: Double) -> Int {
        var deg = atan2(location.y - center.y, location.x - center.x) * 180 / .pi
        if deg < 0 { deg += 360 }
        var shifted = deg - startDeg
        if shifted < 0 { shifted += 360 }
        if shifted > sweepDeg {
            return shifted > (sweepDeg + (360 - sweepDeg) / 2) ? 0 : bandCount - 1
        }
        let seg = sweepDeg / Double(bandCount)
        return max(0, min(bandCount - 1, Int(shifted / seg)))
    }
}

extension SpectrumBand {
    /// Localized display name for the band key.
    var localizedBandName: String {
        switch bandKey {
        case "Threshold": String(localized: "Threshold", comment: "Dose band")
        case "Light": String(localized: "Light", comment: "Dose band")
        case "Common": String(localized: "Common", comment: "Dose band")
        case "Strong": String(localized: "Strong", comment: "Dose band")
        case "Heavy": String(localized: "Heavy", comment: "Dose band")
        case "Overdose": String(localized: "Overdose", comment: "Dose band")
        default: bandKey
        }
    }
}
