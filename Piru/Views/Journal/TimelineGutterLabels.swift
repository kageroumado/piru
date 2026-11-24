import CoreGraphics

/// Collision rules for the vertical timeline's label gutter — the day tag,
/// the "Now" tag, per-dose time capsules, and the hour ruler all share one
/// narrow column, and two of them on the same stretch of axis overprint.
/// Precedence, highest first: the day tag, Now, then dose capsules, then hour
/// labels. A label yields to any higher-precedence label whose frame it
/// touches.
///
/// Pure geometry over slice-local y coordinates so the rules are testable
/// without a layout. Every mark is one ``TimelineGutterMark`` recipe, so the
/// one-line marks share a height.
nonisolated enum TimelineGutterLabels {
    /// Height of an hour-ruler pill.
    static let hourLabelHeight: CGFloat = 22
    /// Height of a dose time capsule.
    static let doseLabelHeight: CGFloat = 22
    /// Height of the "Now" tag.
    static let nowLabelHeight: CGFloat = 22
    /// Height of the two-line day tag.
    static let dayTagHeight: CGFloat = 40
    /// Breathing room two labels keep between their frames.
    static let gap: CGFloat = 6

    /// A label's vertical extent, centered on its anchor.
    struct Frame: Equatable {
        let minY: CGFloat
        let maxY: CGFloat

        init(center: CGFloat, height: CGFloat) {
            minY = center - height / 2
            maxY = center + height / 2
        }

        init(minY: CGFloat, maxY: CGFloat) {
            self.minY = minY
            self.maxY = maxY
        }

        /// `true` when the two frames overlap or come within `gap` of each other.
        func collides(with other: Frame, gap: CGFloat = TimelineGutterLabels.gap) -> Bool {
            minY < other.maxY + gap && other.minY < maxY + gap
        }
    }

    /// Clear space between two stacked dose capsules.
    static let doseStackGap: CGFloat = 2
    /// How far below its dose a capsule may be pushed: half its height, so the
    /// dot on the axis still lies within the capsule's extent.
    static let maximumDoseLabelDrift: CGFloat = doseLabelHeight / 2

    /// Where each dose capsule's center goes, aligned with `doseYs` (ascending,
    /// newest first), or `nil` for a capsule left off. Capsules are stacked
    /// newest first: a capsule that would overlap the one above it, or the Now
    /// tag, is pushed down until clear, by at most ``maximumDoseLabelDrift``;
    /// past that it is left off and takes no room. A capsule above Now (a dose
    /// logged ahead) that touches the Now tag yields to it.
    static func doseLabelCenters(doseYs: [CGFloat], nowY: CGFloat?) -> [CGFloat?] {
        let half = doseLabelHeight / 2
        var lowestBottom = -CGFloat.infinity
        var passedNow = false
        let now = nowY.map { Frame(center: $0, height: nowLabelHeight) }
        return doseYs.map { y in
            if let now, let nowY, y >= nowY, !passedNow {
                passedNow = true
                lowestBottom = max(lowestBottom, now.maxY + gap - doseStackGap)
            }
            let center = max(y, lowestBottom + doseStackGap + half)
            guard center - y <= maximumDoseLabelDrift else { return nil }
            if let now, let nowY, y < nowY, Frame(center: center, height: doseLabelHeight).collides(with: now) {
                return nil
            }
            lowestBottom = center + half
            return center
        }
    }

    /// Whether an hour label at `y` is clear of every visible dose capsule,
    /// the Now tag, and the day tag occupying `reservedTop` from the slice's
    /// top edge.
    static func hourLabelFits(y: CGFloat, doseYs: [CGFloat], nowY: CGFloat?, reservedTop: CGFloat = 0) -> Bool {
        let hour = Frame(center: y, height: hourLabelHeight)
        if reservedTop > 0, hour.collides(with: Frame(minY: -.infinity, maxY: reservedTop)) {
            return false
        }
        if let nowY, hour.collides(with: Frame(center: nowY, height: nowLabelHeight)) {
            return false
        }
        return doseYs.allSatisfy { !hour.collides(with: Frame(center: $0, height: doseLabelHeight)) }
    }
}
