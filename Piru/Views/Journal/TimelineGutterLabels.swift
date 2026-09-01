import CoreGraphics

/// Collision rules for the vertical timeline's label gutter — the "Now" tag,
/// per-dose timestamps, and the hour ruler all share one narrow column, and
/// two of them on the same stretch of axis overprint. Precedence, highest
/// first: Now, then dose timestamps, then hour labels. A label yields to any
/// higher-precedence label whose frame it touches.
///
/// Pure geometry over slice-local y coordinates so the rules are testable
/// without a layout.
nonisolated enum TimelineGutterLabels {
    /// Cap height of an hour-ruler label (9 pt rounded digits).
    static let hourLabelHeight: CGFloat = 11
    /// Cap height of a dose timestamp (10 pt medium).
    static let doseLabelHeight: CGFloat = 12
    /// Cap height of the "Now" tag (10 pt semibold).
    static let nowLabelHeight: CGFloat = 12
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

    /// Which dose timestamps draw, aligned with `doseYs`: a timestamp whose
    /// frame touches the Now tag yields to it.
    static func doseLabelsVisible(doseYs: [CGFloat], nowY: CGFloat?) -> [Bool] {
        guard let nowY else { return doseYs.map { _ in true } }
        let now = Frame(center: nowY, height: nowLabelHeight)
        return doseYs.map { !Frame(center: $0, height: doseLabelHeight).collides(with: now) }
    }

    /// Whether an hour label at `y` is clear of every visible dose timestamp
    /// and the Now tag.
    static func hourLabelFits(y: CGFloat, doseYs: [CGFloat], nowY: CGFloat?) -> Bool {
        let hour = Frame(center: y, height: hourLabelHeight)
        if let nowY, hour.collides(with: Frame(center: nowY, height: nowLabelHeight)) {
            return false
        }
        return doseYs.allSatisfy { !hour.collides(with: Frame(center: $0, height: doseLabelHeight)) }
    }
}
