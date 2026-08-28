import SwiftUI

/// The **two-target balance** — psychedelics on 5-HT2A ↔ 5-HT1A.
///
/// 5-HT2A gates the visual, perceptual arm; 5-HT1A gates the warm, bodily one. One ratio is why
/// 5-MeO-DMT produces an overwhelming, largely non-visual whole-body state where DMT draws intricate
/// scenery — and it is a *ratio*, which is precisely why both values have to come from one
/// experiment. When they don't, the arc is not drawn and the card shows 5-HT2A alone — no note in
/// its place: a sentence about a missing rendering is still a row asking to be read.
struct TargetBalanceView: View {
    let model: TargetBalanceModel
    let accent: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let focus = model.focus {
                if dynamicTypeSize.isAccessibilitySize {
                    BalanceReadout(model: model, accent: accent)
                } else {
                    BalanceArc(model: model, focus: focus, accent: accent)
                }
                poles
            } else {
                BalanceReadout(model: model, accent: accent)
            }

            if let provenance = model.provenance {
                SignatureCaption(provenance: provenance, isGated: model.focus != nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Pole labels sit in an `HStack`, so they mirror with the layout direction for free — the arc
    /// itself is mirrored explicitly in ``BalanceArc``.
    private var poles: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.leadingPole).font(.caption2.weight(.bold)).foregroundStyle(accent)
                Text("perception", comment: "What the 5-HT2A pole of the balance arc governs")
                    .font(.caption2).foregroundStyle(Theme.secondaryLabel)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(model.trailingPole).font(.caption2.weight(.bold)).foregroundStyle(Theme.secondaryLabel)
                Text("body", comment: "What the 5-HT1A pole of the balance arc governs")
                    .font(.caption2).foregroundStyle(Theme.secondaryLabel)
            }
        }
        .lineLimit(2)
        .multilineTextAlignment(.leading)
    }
}

// MARK: - The arc

private struct BalanceArc: View {
    let model: TargetBalanceModel
    let focus: TargetBalanceModel.Tick
    let accent: Color

    @Environment(\.layoutDirection) private var layoutDirection

    /// Tall enough that a tick label at the arc's apex still clears the top edge: the labels sit at
    /// `radius + 24`, so the frame has to be the radius plus that ring plus a line of text.
    private static let height: CGFloat = 148
    private static let labelWidth: CGFloat = 84

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let radius = min(size.width / 2 - 30, size.height - 44)
            let center = CGPoint(x: size.width / 2, y: size.height - 4)
            ZStack(alignment: .topLeading) {
                ArcShape(radius: radius)
                    .stroke(
                        LinearGradient(
                            colors: [accent.opacity(0.92), accent.opacity(0.20)],
                            startPoint: layoutDirection == .rightToLeft ? .trailing : .leading,
                            endPoint: layoutDirection == .rightToLeft ? .leading : .trailing,
                        ),
                        style: StrokeStyle(lineWidth: 15, lineCap: .round),
                    )
                    .frame(width: size.width, height: size.height)

                ForEach(model.ticks) { tick in
                    tickMark(tick, center: center, radius: radius, width: size.width)
                }

                handle(center: center, radius: radius, width: size.width)

                VStack(spacing: 1) {
                    Text(model.ratioText)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(model.valueText)
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: max(60, radius * 1.5))
                .offset(x: center.x - max(60, radius * 1.5) / 2, y: center.y - 62)
            }
            .signaturePlotPinnedToLTR()
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(
                "\(model.leadingPole) to \(model.trailingPole) balance",
                comment: "Accessibility label for the two-target balance arc",
            ),
        )
        .accessibilityValue(Text(spokenValue))
    }

    /// Assembled as a plain `String` so it resolves to `Text`'s `StringProtocol` overload rather than
    /// minting a `"%@, %@"` catalog key.
    private var spokenValue: String {
        model.ratioText + ", " + model.valueText
    }

    private func tickMark(
        _ tick: TargetBalanceModel.Tick,
        center: CGPoint,
        radius: CGFloat,
        width: CGFloat,
    ) -> some View {
        let angle = self.angle(tick.position)
        let inner = point(center: center, radius: radius - 10, angle: angle)
        let outer = point(center: center, radius: radius + 10, angle: angle)
        let labelAt = point(center: center, radius: radius + 24, angle: angle)
        let clamped = min(max(labelAt.x, Self.labelWidth / 2), width - Self.labelWidth / 2)
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: inner)
                path.addLine(to: outer)
            }
            .stroke(Theme.secondaryLabel.opacity(tick.isGated ? 0.7 : 0.35), lineWidth: 1.4)
            Text(tick.name)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .frame(width: Self.labelWidth)
                .offset(x: clamped - Self.labelWidth / 2, y: labelAt.y - 6)
        }
    }

    private func handle(center: CGPoint, radius: CGFloat, width _: CGFloat) -> some View {
        let position = point(center: center, radius: radius, angle: angle(focus.position))
        return Circle()
            .fill(Color(.systemBackground))
            .overlay(Circle().strokeBorder(accent, lineWidth: 4))
            .frame(width: 22, height: 22)
            .offset(x: position.x - 11, y: position.y - 11)
    }

    /// 180° (leading pole) → 360° (trailing pole), mirrored under RTL so the 5-HT1A end stays on the
    /// reading-order side its label is on.
    private func angle(_ position: Double) -> Double {
        let fraction = layoutDirection == .rightToLeft ? 1 - position : position
        return 180 + fraction * 180
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
    }

    private struct ArcShape: Shape {
        let radius: CGFloat

        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.addArc(
                center: CGPoint(x: rect.midX, y: rect.maxY - 4),
                radius: radius,
                startAngle: .degrees(180),
                endAngle: .degrees(360),
                clockwise: false,
            )
            return path
        }
    }
}

// MARK: - Degraded form

/// The readout the arc degrades to: at accessibility text sizes (where tick labels cannot clear the
/// arc), and whenever no single study measured both receptors.
private struct BalanceReadout: View {
    let model: TargetBalanceModel
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if model.focus != nil, !model.ratioText.isEmpty {
                Text(model.ratioText)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(accent)
            }
            Text(model.valueText)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(model.focus == nil ? accent : Theme.secondaryLabel)
            if !model.ticks.isEmpty {
                ForEach(model.ticks) { tick in
                    HStack(spacing: 8) {
                        Text(tick.name).font(.caption)
                        Spacer(minLength: 6)
                        Text(Self.leanText(tick.ratio))
                            .font(.caption.monospacedDigit())
                    }
                    .foregroundStyle(Theme.secondaryLabel)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "12× 1A" / "3× 2A" — the receptor names are proper nouns, so only the multiplier is composed
    /// here; built as a plain `String` to keep it off the string catalog.
    private static func leanText(_ ratio: Double) -> String {
        let scale = ratio >= 1 ? ratio : 1 / ratio
        let rounded = scale.formatted(.number.precision(.fractionLength(0 ... 0)))
        return ratio >= 1 ? "\(rounded)× 1A" : "\(rounded)× 2A"
    }
}
