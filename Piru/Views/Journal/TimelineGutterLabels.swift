import CoreGraphics

/// Collision rules for the vertical timeline's label gutter — the "Now" tag,
/// per-dose time capsules, and the hour ruler all share one narrow column, and
/// two of them on the same stretch of axis overprint. Precedence, highest
/// first: Now, then dose capsules, then hour labels. A label yields to any
/// higher-precedence label whose frame it touches.
///
/// Pure geometry over slice-local y coordinates so the rules are testable
/// without a layout.
nonisolated enum TimelineGutterLabels {
    /// Height of an hour-ruler numeral (11 pt tabular) with its halo.
    static let hourLabelHeight: CGFloat = 13
    /// Height of a dose time capsule (hour over minutes, ``TimelineTimeCapsule``).
    static let doseLabelHeight: CGFloat = TimelineGutter.capsuleHeight
    /// Height of the "Now" tag (10 pt semibold) with its halo.
    static let nowLabelHeight: CGFloat = 14
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

        /// `true` when the two frames overlap or come within `gap` of each other.
        func collides(with other: Frame, gap: CGFloat = TimelineGutterLabels.gap) -> Bool {
            minY < other.maxY + gap && other.minY < maxY + gap
        }
    }

    /// Which dose capsules draw, aligned with `doseYs`: a capsule whose frame
    /// touches the Now tag yields to it.
    static func doseLabelsVisible(doseYs: [CGFloat], nowY: CGFloat?) -> [Bool] {
        guard let nowY else { return doseYs.map { _ in true } }
        let now = Frame(center: nowY, height: nowLabelHeight)
        return doseYs.map { !Frame(center: $0, height: doseLabelHeight).collides(with: now) }
    }

    /// Whether an hour label at `y` is clear of every visible dose capsule
    /// and the Now tag.
    static func hourLabelFits(y: CGFloat, doseYs: [CGFloat], nowY: CGFloat?) -> Bool {
        let hour = Frame(center: y, height: hourLabelHeight)
        if let nowY, hour.collides(with: Frame(center: nowY, height: nowLabelHeight)) {
            return false
        }
        return doseYs.allSatisfy { !hour.collides(with: Frame(center: $0, height: doseLabelHeight)) }
    }
}
