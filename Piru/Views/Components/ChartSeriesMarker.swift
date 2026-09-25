import Charts
import SwiftUI

/// A chart series' identity in shape rather than hue: a dash pattern for its
/// line and a symbol for its points and legend key. Charts that tell series
/// apart by color apply it when Differentiate Without Color is on, so every
/// line stays nameable in grayscale or to a color-blind reader.
///
/// Five dashes and five symbols pair up so the first 25 series each get a
/// distinct combination; the pairing rotates the symbol every five series
/// rather than repeating the first five.
nonisolated struct ChartSeriesMarker: Hashable {
    let dashIndex: Int
    let symbolIndex: Int

    private static let variants = 5

    /// The marker for the series at `index` in a chart's stable series order.
    init(index: Int) {
        let i = max(0, index)
        dashIndex = i % Self.variants
        symbolIndex = (i % Self.variants + i / Self.variants) % Self.variants
    }

    /// The stroke dash, empty for a solid line.
    var dash: [CGFloat] {
        switch dashIndex {
        case 0: []
        case 1: [7, 4]
        case 2: [1, 4]
        case 3: [8, 3, 1, 3]
        default: [14, 5]
        }
    }

    /// The Swift Charts point symbol.
    var chartSymbol: BasicChartSymbolShape {
        switch symbolIndex {
        case 0: .circle
        case 1: .square
        case 2: .triangle
        case 3: .diamond
        default: .pentagon
        }
    }

    /// The SF Symbol that draws the same shape in a legend key.
    var systemImage: String {
        switch symbolIndex {
        case 0: "circle.fill"
        case 1: "square.fill"
        case 2: "triangle.fill"
        case 3: "diamond.fill"
        default: "pentagon.fill"
        }
    }

    /// A line stroke of `lineWidth`, dashed with this marker when
    /// `differentiate` is on and solid otherwise.
    func stroke(lineWidth: CGFloat, differentiate: Bool) -> StrokeStyle {
        StrokeStyle(
            lineWidth: lineWidth,
            lineCap: .round,
            lineJoin: .round,
            dash: differentiate ? dash : [],
        )
    }

    /// Where along a line to place its symbols: its peaks and its last point,
    /// highest first, each at least `window / slots` from any symbol already
    /// placed. Points under `floor` get none: a line hugging zero overlaps
    /// every other line there, so a symbol on it would name nothing.
    ///
    /// Returns indices into `dates`/`values`, which must be the same length
    /// and in date order.
    static func symbolIndices(
        dates: [Date],
        values: [Double],
        window: TimeInterval,
        slots: Int = 16,
        floor: Double = 0,
    ) -> [Int] {
        guard dates.count == values.count, !values.isEmpty, slots > 0, window > 0 else { return [] }
        let spacing = window / Double(slots)
        let last = values.count - 1
        var candidates = (0 ..< values.count).filter { i in
            let rises = i == 0 || values[i] >= values[i - 1]
            let falls = i == last || values[i] > values[i + 1]
            return rises && falls
        }
        if candidates.last != last { candidates.append(last) }
        var placed: [Int] = []
        for i in candidates.filter({ values[$0] > floor }).sorted(by: { values[$0] > values[$1] }) {
            let clear = placed.allSatisfy { abs(dates[$0].timeIntervalSince(dates[i])) >= spacing }
            if clear { placed.append(i) }
        }
        return placed.sorted()
    }
}

// MARK: - Legend key

/// A legend's key for one series: the plain color dot normally, and under
/// Differentiate Without Color a short line in the series' dash with its
/// symbol on it — the same two marks the chart draws.
struct ChartSeriesKey: View {
    let color: Color
    let marker: ChartSeriesMarker
    var size: LegendDot.Size = .regular

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    var body: some View {
        if differentiate {
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 4.5))
                    path.addLine(to: CGPoint(x: Self.lineLength, y: 4.5))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: marker.dash.map { $0 * 0.6 }))
                .frame(width: Self.lineLength, height: 9)
                Image(systemName: marker.systemImage)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(color)
            }
            .accessibilityHidden(true)
        } else {
            LegendDot(color: color, size: size)
        }
    }

    private static let lineLength: CGFloat = 18
}
