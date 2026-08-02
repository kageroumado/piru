import SwiftUI

/// Draws the stretch of a dose timeline's axis that sits at or above the
/// substance's published heavy-dose bound.
///
/// A **reference mark, not a warning**: "heavy" is the sources' own top tier —
/// the same word the dose ladder and the entry chip use — and this says where on
/// this graph that tier begins, in the tier's own color, behind the curve like
/// the phase bands beside it. It is not advice, and it does not appear because
/// anything is wrong; it appears because the graph can locate a line somebody
/// published.
///
/// Whether it may be drawn at all, and at what height, is decided upstream by
/// ``TimelineCurveModel/heavyThresholdHeight(substances:stackedGroups:stackRedoses:yNormalization:)``
/// — which answers `nil` for every graph whose normalized axis can't carry the
/// claim. This type only renders the answer, so it lives apart from both the
/// view and the math.
enum HeavyThresholdBand {
    /// Same headroom factor every curve point is drawn with, so the rule lands
    /// exactly where the curve crosses it.
    static let headroom: CGFloat = 0.93

    /// - Parameters:
    ///   - height: normalized `0...1` height of the bound, from
    ///     ``TimelineCurveModel/heavyThresholdHeight(substances:stackedGroups:stackRedoses:yNormalization:)``.
    ///   - squareCorners: true inside the bordered-chart host, whose frame is
    ///     square; elsewhere the band rounds to sit concentric with the card.
    static func draw(
        in context: GraphicsContext,
        height: Double,
        size: CGSize,
        graphTop: CGFloat,
        graphHeight: CGFloat,
        graphInset: CGFloat,
        squareCorners: Bool,
    ) {
        let graphWidth = size.width - graphInset * 2
        guard graphWidth > 0, graphHeight > 0 else { return }
        let y = graphTop + graphHeight - CGFloat(height) * graphHeight * headroom
        guard y > graphTop else { return }

        let plotRect = CGRect(x: graphInset, y: graphTop, width: graphWidth, height: graphHeight)
        context.drawLayer { layer in
            layer.clip(to: Path(roundedRect: plotRect, cornerRadius: squareCorners ? 0 : 10, style: .continuous))
            layer.fill(
                Path(CGRect(x: graphInset, y: graphTop, width: graphWidth, height: y - graphTop)),
                with: .color(.Dose.Heavy.accent.opacity(0.10)),
            )
            var rule = Path()
            rule.move(to: CGPoint(x: graphInset, y: y))
            rule.addLine(to: CGPoint(x: graphInset + graphWidth, y: y))
            layer.stroke(
                rule,
                with: .color(.Dose.Heavy.accent.opacity(0.55)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3]),
            )
        }

        // Named, or the band is an unexplained stripe. Just under the rule at the
        // trailing edge — the top-left is where the crest and dose markers live.
        let label = context.resolve(
            Text("heavy")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.Dose.Heavy.text),
        )
        let labelSize = label.measure(in: CGSize(width: graphWidth, height: graphHeight))
        let labelY = min(y + labelSize.height / 2 + 2, graphTop + graphHeight - labelSize.height / 2)
        context.draw(label, at: CGPoint(x: graphInset + graphWidth - 4, y: labelY), anchor: .trailing)
    }
}
