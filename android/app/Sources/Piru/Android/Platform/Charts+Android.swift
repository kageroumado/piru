// Swift Charts for Android: the marks, axes and chart modifiers the shared code uses, drawn
// through the Canvas stand-in. Marks record their plotted values and style; `Chart` fits
// them to a plot area with light gridlines and leading/bottom labels. Axis customization
// (AxisMarks contents, value formats) is accepted and drawn in the default style, and chart
// selection is not interactive.
//
// Inside a `Chart { }` body, stage.py renames `ForEach` to `ChartForEach`: SwiftUI's ForEach
// builds chart content there, and SkipFuseUI's builds only views.

import SwiftUI

// MARK: - Values

protocol Plottable {
    var androidPlotted: PlottedValue { get }
}

enum PlottedValue: Hashable {
    case number(Double)
    case date(Date)
    case category(String)
}

extension Double: Plottable { var androidPlotted: PlottedValue { .number(self) } }
extension Float: Plottable { var androidPlotted: PlottedValue { .number(Double(self)) } }
extension Int: Plottable { var androidPlotted: PlottedValue { .number(Double(self)) } }
extension Date: Plottable { var androidPlotted: PlottedValue { .date(self) } }
extension String: Plottable { var androidPlotted: PlottedValue { .category(self) } }

struct PlottableValue<Value: Plottable> {
    let label: String
    let value: Value

    static func value(_: LocalizedStringKey, _ value: Value) -> PlottableValue<Value> {
        PlottableValue(label: "", value: value)
    }

    static func value(_ label: some StringProtocol, _ value: Value) -> PlottableValue<Value> {
        PlottableValue(label: String(label), value: value)
    }

    static func value(_: Text, _ value: Value) -> PlottableValue<Value> {
        PlottableValue(label: "", value: value)
    }
}

extension PlottableValue where Value == Date {
    /// A date binned to `unit`: plotted at the unit's start, as Swift Charts groups it.
    static func value(_ label: some StringProtocol, _ value: Date, unit: Calendar.Component, calendar: Calendar = .current) -> PlottableValue<Date> {
        PlottableValue(label: String(label), value: calendar.dateInterval(of: unit, for: value)?.start ?? value)
    }

    static func value(_: LocalizedStringKey, _ value: Date, unit: Calendar.Component, calendar: Calendar = .current) -> PlottableValue<Date> {
        PlottableValue(label: "", value: calendar.dateInterval(of: unit, for: value)?.start ?? value)
    }
}

enum InterpolationMethod {
    case linear
    case monotone
    case catmullRom
    case cardinal
    case stepStart
    case stepCenter
    case stepEnd
}

enum MarkStackingMethod {
    case standard
    case normalized
    case center
    case unstacked
}

// MARK: - Marks

struct ChartMark {
    enum Kind { case line, area, rule, point, bar, rectangle }

    var kind: Kind
    var x: PlottedValue?
    var y: PlottedValue?
    var xStart: PlottedValue?
    var xEnd: PlottedValue?
    var yStart: PlottedValue?
    var yEnd: PlottedValue?
    var series: String?
    var color: Color?
    var strokeStyle = StrokeStyle(lineWidth: 2)
    var interpolation = InterpolationMethod.linear
    var symbolSize: CGFloat = 30
    var opacity: Double = 1
    /// A bar that stacks on the bars before it at the same x, as Swift Charts stacks
    /// `BarMark(x:y:)` unless it is unstacked or positioned by series.
    var stacks = false
}

extension [ChartMark] {
    /// Stacking bars given their cumulative extents: positive values stack up from zero and
    /// negative ones down, per x, in the order the chart lists them.
    var stacked: [ChartMark] {
        var above: [PlottedValue: Double] = [:]
        var below: [PlottedValue: Double] = [:]
        return map { mark in
            guard mark.kind == .bar, mark.stacks, mark.yStart == nil, mark.yEnd == nil,
                  let x = mark.x, case let .number(value)? = mark.y
            else { return mark }
            var stacked = mark
            if value >= 0 {
                let base = above[x, default: 0]
                above[x] = base + value
                stacked.yStart = .number(base)
                stacked.yEnd = .number(base + value)
            } else {
                let base = below[x, default: 0]
                below[x] = base + value
                stacked.yStart = .number(base)
                stacked.yEnd = .number(base + value)
            }
            return stacked
        }
    }
}

protocol ChartContent {
    var androidMarks: [ChartMark] { get }
}

extension [ChartMark]: ChartContent {
    var androidMarks: [ChartMark] { self }
}

/// The modifiers every mark takes, each returning the mark so chains keep their type.
protocol AndroidMark: ChartContent {
    var mark: ChartMark { get set }
}

extension AndroidMark {
    var androidMarks: [ChartMark] { [mark] }

    private func with(_ change: (inout ChartMark) -> Void) -> Self {
        var copy = self
        change(&copy.mark)
        return copy
    }

    func foregroundStyle(_ style: some ShapeStyle) -> Self {
        with { if let color = style as? Color { $0.color = color } }
    }

    func foregroundStyle(by value: PlottableValue<some Plottable>) -> Self {
        with { $0.series = value.value.androidPlotted.seriesName }
    }

    func lineStyle(_ style: StrokeStyle) -> Self { with { $0.strokeStyle = style } }
    func interpolationMethod(_ method: InterpolationMethod) -> Self { with { $0.interpolation = method } }
    func symbolSize(_ size: CGFloat) -> Self { with { $0.symbolSize = size } }
    func symbolSize(_ size: CGSize) -> Self { with { $0.symbolSize = size.width * size.height } }
    func symbol(_: some Any) -> Self { self }
    func symbol(by _: PlottableValue<some Plottable>) -> Self { self }
    func opacity(_ value: Double) -> Self { with { $0.opacity = value } }
    func cornerRadius(_: CGFloat, style _: RoundedCornerStyle = .continuous) -> Self { self }
    func position(by value: PlottableValue<some Plottable>, axis _: Axis? = nil) -> Self {
        with {
            $0.series = value.value.androidPlotted.seriesName
            $0.stacks = false
        }
    }
    func offset(x _: CGFloat = 0, y _: CGFloat = 0) -> Self { self }
    func zIndex(_: Double) -> Self { self }
    func alignsMarkStylesWithPlotArea(_: Bool = true) -> Self { self }
    func accessibilityLabel(_: Text) -> Self { self }
    func accessibilityLabel(_: String) -> Self { self }
    func accessibilityValue(_: Text) -> Self { self }
    func accessibilityValue(_: String) -> Self { self }
    func accessibilityHidden(_: Bool) -> Self { self }
    func clipShape(_: some Shape) -> Self { self }
    func mask(_: () -> some Any) -> Self { self }
    func annotation(
        position _: AnnotationPosition = .automatic, alignment _: Alignment = .center, spacing _: CGFloat? = nil,
        overflowResolution _: AnnotationOverflowResolution = .automatic,
        @ViewBuilder content _: () -> some View,
    ) -> Self { self }
}

enum AnnotationPosition { case automatic, top, bottom, leading, trailing, overlay, topLeading, topTrailing, bottomLeading, bottomTrailing }

struct AnnotationOverflowResolution {
    static let automatic = AnnotationOverflowResolution()
    init() {}
    init(x _: AnnotationOverflowStrategy = .automatic, y _: AnnotationOverflowStrategy = .automatic) {}
}

struct AnnotationOverflowStrategy {
    static let automatic = AnnotationOverflowStrategy()
    static let fit = AnnotationOverflowStrategy()
    static let disabled = AnnotationOverflowStrategy()
    static func fit(to _: AnnotationBoundary) -> AnnotationOverflowStrategy { AnnotationOverflowStrategy() }
}

enum AnnotationBoundary { case automatic, chart, plot }

private extension PlottedValue {
    var seriesName: String {
        switch self {
        case let .category(name): name
        case let .number(value): String(value)
        case let .date(date): String(date.timeIntervalSince1970)
        }
    }
}

struct LineMark: AndroidMark {
    var mark: ChartMark

    init(x: PlottableValue<some Plottable>, y: PlottableValue<some Plottable>) {
        mark = ChartMark(kind: .line, x: x.value.androidPlotted, y: y.value.androidPlotted)
    }

    init(x: PlottableValue<some Plottable>, y: PlottableValue<some Plottable>, series: PlottableValue<some Plottable>) {
        mark = ChartMark(kind: .line, x: x.value.androidPlotted, y: y.value.androidPlotted, series: series.value.androidPlotted.seriesName)
    }
}

struct AreaMark: AndroidMark {
    var mark: ChartMark

    init(x: PlottableValue<some Plottable>, y: PlottableValue<some Plottable>, stacking _: MarkStackingMethod = .standard) {
        mark = ChartMark(kind: .area, x: x.value.androidPlotted, y: y.value.androidPlotted)
    }

    init<Y: Plottable>(x: PlottableValue<some Plottable>, yStart: PlottableValue<Y>, yEnd: PlottableValue<Y>) {
        mark = ChartMark(kind: .area, x: x.value.androidPlotted, yStart: yStart.value.androidPlotted, yEnd: yEnd.value.androidPlotted)
    }

    init(x: PlottableValue<some Plottable>, y: PlottableValue<some Plottable>, series: PlottableValue<some Plottable>, stacking _: MarkStackingMethod = .standard) {
        mark = ChartMark(kind: .area, x: x.value.androidPlotted, y: y.value.androidPlotted, series: series.value.androidPlotted.seriesName)
    }

    init<Y: Plottable>(x: PlottableValue<some Plottable>, yStart: PlottableValue<Y>, yEnd: PlottableValue<Y>, series: PlottableValue<some Plottable>) {
        mark = ChartMark(
            kind: .area, x: x.value.androidPlotted, yStart: yStart.value.androidPlotted, yEnd: yEnd.value.androidPlotted,
            series: series.value.androidPlotted.seriesName,
        )
    }
}

struct RuleMark: AndroidMark {
    var mark: ChartMark

    init(x: PlottableValue<some Plottable>) {
        mark = ChartMark(kind: .rule, x: x.value.androidPlotted)
    }

    init(y: PlottableValue<some Plottable>) {
        mark = ChartMark(kind: .rule, y: y.value.androidPlotted)
    }

    init<X: Plottable>(xStart: PlottableValue<X>, xEnd: PlottableValue<X>, y: PlottableValue<some Plottable>) {
        mark = ChartMark(kind: .rule, y: y.value.androidPlotted, xStart: xStart.value.androidPlotted, xEnd: xEnd.value.androidPlotted)
    }

    init<Y: Plottable>(x: PlottableValue<some Plottable>, yStart: PlottableValue<Y>, yEnd: PlottableValue<Y>) {
        mark = ChartMark(kind: .rule, x: x.value.androidPlotted, yStart: yStart.value.androidPlotted, yEnd: yEnd.value.androidPlotted)
    }
}

struct PointMark: AndroidMark {
    var mark: ChartMark

    init(x: PlottableValue<some Plottable>, y: PlottableValue<some Plottable>) {
        mark = ChartMark(kind: .point, x: x.value.androidPlotted, y: y.value.androidPlotted)
    }
}

struct BarMark: AndroidMark {
    var mark: ChartMark

    /// `.normalized` and `.center` stack as `.standard` does.
    init(x: PlottableValue<some Plottable>, y: PlottableValue<some Plottable>, width _: MarkDimension = .automatic, stacking: MarkStackingMethod = .standard) {
        mark = ChartMark(kind: .bar, x: x.value.androidPlotted, y: y.value.androidPlotted, stacks: stacking != .unstacked)
    }

    init<Y: Plottable>(x: PlottableValue<some Plottable>, yStart: PlottableValue<Y>, yEnd: PlottableValue<Y>, width _: MarkDimension = .automatic) {
        mark = ChartMark(kind: .bar, x: x.value.androidPlotted, yStart: yStart.value.androidPlotted, yEnd: yEnd.value.androidPlotted)
    }

    init<X: Plottable>(xStart: PlottableValue<X>, xEnd: PlottableValue<X>, y: PlottableValue<some Plottable>, height _: MarkDimension = .automatic) {
        mark = ChartMark(kind: .bar, y: y.value.androidPlotted, xStart: xStart.value.androidPlotted, xEnd: xEnd.value.androidPlotted)
    }
}

struct RectangleMark: AndroidMark {
    var mark: ChartMark

    init<X: Plottable, Y: Plottable>(xStart: PlottableValue<X>, xEnd: PlottableValue<X>, yStart: PlottableValue<Y>, yEnd: PlottableValue<Y>) {
        mark = ChartMark(
            kind: .rectangle,
            xStart: xStart.value.androidPlotted, xEnd: xEnd.value.androidPlotted,
            yStart: yStart.value.androidPlotted, yEnd: yEnd.value.androidPlotted,
        )
    }

    init<Y: Plottable>(x: PlottableValue<some Plottable>, yStart: PlottableValue<Y>, yEnd: PlottableValue<Y>, width _: MarkDimension = .automatic) {
        mark = ChartMark(kind: .rectangle, x: x.value.androidPlotted, yStart: yStart.value.androidPlotted, yEnd: yEnd.value.androidPlotted)
    }

    init<X: Plottable>(xStart: PlottableValue<X>, xEnd: PlottableValue<X>, y: PlottableValue<some Plottable>, height _: MarkDimension = .automatic) {
        mark = ChartMark(kind: .rectangle, y: y.value.androidPlotted, xStart: xStart.value.androidPlotted, xEnd: xEnd.value.androidPlotted)
    }

    /// A band across the whole plot width.
    init<Y: Plottable>(yStart: PlottableValue<Y>, yEnd: PlottableValue<Y>) {
        mark = ChartMark(kind: .rectangle, yStart: yStart.value.androidPlotted, yEnd: yEnd.value.androidPlotted)
    }

    /// A band across the whole plot height.
    init<X: Plottable>(xStart: PlottableValue<X>, xEnd: PlottableValue<X>) {
        mark = ChartMark(kind: .rectangle, xStart: xStart.value.androidPlotted, xEnd: xEnd.value.androidPlotted)
    }
}

struct MarkDimension: ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    static let automatic = MarkDimension()
    static func fixed(_: CGFloat) -> MarkDimension { MarkDimension() }
    static func ratio(_: CGFloat) -> MarkDimension { MarkDimension() }
    init() {}
    init(floatLiteral _: Double) {}
    init(integerLiteral _: Int) {}
}

@resultBuilder
enum ChartContentBuilder {
    static func buildExpression(_ content: some ChartContent) -> [ChartMark] { content.androidMarks }
    static func buildBlock(_ parts: [ChartMark]...) -> [ChartMark] { parts.flatMap(\.self) }
    static func buildOptional(_ part: [ChartMark]?) -> [ChartMark] { part ?? [] }
    static func buildEither(first: [ChartMark]) -> [ChartMark] { first }
    static func buildEither(second: [ChartMark]) -> [ChartMark] { second }
    static func buildArray(_ parts: [[ChartMark]]) -> [ChartMark] { parts.flatMap(\.self) }
    static func buildLimitedAvailability(_ part: [ChartMark]) -> [ChartMark] { part }
}

/// `ForEach` inside a chart body (stage.py renames it there).
struct ChartForEach: ChartContent {
    let androidMarks: [ChartMark]

    init<Data: RandomAccessCollection>(_ data: Data, @ChartContentBuilder content: (Data.Element) -> [ChartMark]) {
        androidMarks = data.flatMap(content)
    }

    init<Data: RandomAccessCollection>(
        _ data: Data, id _: KeyPath<Data.Element, some Hashable>, @ChartContentBuilder content: (Data.Element) -> [ChartMark],
    ) {
        androidMarks = data.flatMap(content)
    }
}

protocol ChartSymbolShape: Shape {}

/// The built-in point symbols; drawn as circles, the one symbol the renderer draws.
struct BasicChartSymbolShape: ChartSymbolShape {
    static let circle = BasicChartSymbolShape()
    static let square = BasicChartSymbolShape()
    static let triangle = BasicChartSymbolShape()
    static let diamond = BasicChartSymbolShape()
    static let pentagon = BasicChartSymbolShape()
    static let plus = BasicChartSymbolShape()
    static let cross = BasicChartSymbolShape()
    static let asterisk = BasicChartSymbolShape()

    nonisolated func path(in rect: CGRect) -> Path {
        Path(ellipseIn: rect)
    }

    func strokeBorder(lineWidth _: CGFloat = 1) -> BasicChartSymbolShape { self }
}

// MARK: - Axes

protocol AxisContent {}

@resultBuilder
enum AxisContentBuilder {
    static func buildExpression(_: some AxisContent) -> AxisGroup { AxisGroup() }
    static func buildBlock(_: AxisGroup...) -> AxisGroup { AxisGroup() }
    static func buildOptional(_: AxisGroup?) -> AxisGroup { AxisGroup() }
    static func buildEither(first: AxisGroup) -> AxisGroup { first }
    static func buildEither(second: AxisGroup) -> AxisGroup { second }
    static func buildArray(_: [AxisGroup]) -> AxisGroup { AxisGroup() }
}

struct AxisGroup: AxisContent {}

struct AxisValue {
    let index: Int
    let count: Int
    private let plotted: PlottedValue

    init(index: Int = 0, count: Int = 0, plotted: PlottedValue = .number(0)) {
        self.index = index
        self.count = count
        self.plotted = plotted
    }

    func `as`<V>(_: V.Type) -> V? {
        switch plotted {
        case let .number(value): (value as? V) ?? (Int(value) as? V)
        case let .date(date): date as? V
        case let .category(name): name as? V
        }
    }
}

struct AxisMarkValues: ExpressibleByArrayLiteral {
    static let automatic = AxisMarkValues()
    static func automatic(desiredCount _: Int? = nil, roundLowerBound _: Bool? = nil, roundUpperBound _: Bool? = nil) -> AxisMarkValues { AxisMarkValues() }
    static func stride(by _: Calendar.Component, count _: Int = 1) -> AxisMarkValues { AxisMarkValues() }
    static func stride(by _: Double) -> AxisMarkValues { AxisMarkValues() }
    init() {}
    init(arrayLiteral _: Double...) {}
    init(_: [some Plottable]) {}
}

enum AxisMarkPosition { case automatic, leading, trailing, top, bottom }
enum AxisMarkPreset { case automatic, extended, aligned, inset }

struct AxisMarks: AxisContent {
    init(preset _: AxisMarkPreset = .automatic, position _: AxisMarkPosition = .automatic, values _: AxisMarkValues = .automatic) {}

    init(
        preset _: AxisMarkPreset = .automatic, position _: AxisMarkPosition = .automatic, values _: AxisMarkValues = .automatic,
        @AxisContentBuilder content _: @escaping (AxisValue) -> AxisGroup,
    ) {}

    init(
        preset _: AxisMarkPreset = .automatic, position _: AxisMarkPosition = .automatic, values _: [some Plottable],
        @AxisContentBuilder content _: @escaping (AxisValue) -> AxisGroup,
    ) {}

    init(preset _: AxisMarkPreset = .automatic, position _: AxisMarkPosition = .automatic, values _: [some Plottable]) {}
}

struct AxisGridLine: AxisContent {
    init(centered _: Bool? = nil, stroke _: StrokeStyle? = nil) {}
    func foregroundStyle(_: some ShapeStyle) -> AxisGridLine { self }
}

struct AxisTick: AxisContent {
    init(centered _: Bool? = nil, length _: CGFloat? = nil, stroke _: StrokeStyle? = nil) {}
    func foregroundStyle(_: some ShapeStyle) -> AxisTick { self }
}

struct AxisValueLabel: AxisContent {
    init() {}
    init(centered _: Bool? = nil, anchor _: UnitPoint? = nil, multiLabelAlignment _: Alignment? = nil, collisionResolution _: AxisValueLabelCollisionResolution = .automatic, offsetsMarks _: Bool? = nil, orientation _: AxisValueLabelOrientation = .automatic, horizontalSpacing _: CGFloat? = nil, verticalSpacing _: CGFloat? = nil) {}
    init(format _: Date.FormatStyle, centered _: Bool? = nil, anchor _: UnitPoint? = nil, collisionResolution _: AxisValueLabelCollisionResolution = .automatic) {}
    init(format _: FloatingPointFormatStyle<Double>, centered _: Bool? = nil, anchor _: UnitPoint? = nil, collisionResolution _: AxisValueLabelCollisionResolution = .automatic) {}
    init(format _: FloatingPointFormatStyle<Double>.Percent, centered _: Bool? = nil, anchor _: UnitPoint? = nil, collisionResolution _: AxisValueLabelCollisionResolution = .automatic) {}
    init(format _: IntegerFormatStyle<Int>, centered _: Bool? = nil, anchor _: UnitPoint? = nil, collisionResolution _: AxisValueLabelCollisionResolution = .automatic) {}
    init(@ViewBuilder content _: () -> some View) {}
    init(centered _: Bool?, anchor _: UnitPoint? = nil, @ViewBuilder content _: () -> some View) {}
    func font(_: Font?) -> AxisValueLabel { self }
    func foregroundStyle(_: some ShapeStyle) -> AxisValueLabel { self }
}

struct AxisValueLabelCollisionResolution {
    static let automatic = AxisValueLabelCollisionResolution()
    static let greedy = AxisValueLabelCollisionResolution()
    static let disabled = AxisValueLabelCollisionResolution()
    static func greedy(priority _: Double = 0, minimumSpacing _: CGFloat = 0) -> AxisValueLabelCollisionResolution { .greedy }
}

enum AxisValueLabelOrientation { case automatic, horizontal, vertical, verticalReversed }

// MARK: - Chart modifiers

struct ChartAxisConfiguration: Equatable {
    var xHidden = false
    var yHidden = false
    var xDomain: ClosedRange<Double>?
    var yDomain: ClosedRange<Double>?
    var seriesColors: [String: Color] = [:]
}

extension EnvironmentValues {
    @Entry var androidChartConfiguration: ChartAxisConfiguration = .init()
}

private extension ClosedRange where Bound: Plottable {
    var androidDomain: ClosedRange<Double>? {
        guard case let .number(low) = lowerBound.androidPlotted.normalized,
              case let .number(high) = upperBound.androidPlotted.normalized, low <= high else { return nil }
        return low ... high
    }
}

private extension PlottedValue {
    var normalized: PlottedValue {
        if case let .date(date) = self { return .number(date.timeIntervalSinceReferenceDate) }
        return self
    }
}

/// Applies one chart modifier to the configuration the enclosing ones already set.
struct ChartConfigured<Content: View>: View {
    let content: Content
    let change: (inout ChartAxisConfiguration) -> Void
    @Environment(\.androidChartConfiguration) var configuration

    var body: some View {
        var changed = configuration
        change(&changed)
        return content.environment(\.androidChartConfiguration, changed)
    }
}

extension View {
    private func configureChart(_ change: @escaping (inout ChartAxisConfiguration) -> Void) -> some View {
        ChartConfigured(content: self, change: change)
    }

    func chartXAxis(_ visibility: Visibility) -> some View {
        configureChart { $0.xHidden = visibility == .hidden }
    }

    func chartYAxis(_ visibility: Visibility) -> some View {
        configureChart { $0.yHidden = visibility == .hidden }
    }

    func chartXAxis(@AxisContentBuilder content _: () -> AxisGroup) -> some View { self }
    func chartYAxis(@AxisContentBuilder content _: () -> AxisGroup) -> some View { self }

    func chartYScale(domain: ClosedRange<some Plottable>, type _: ScaleType? = nil) -> some View {
        let domain = domain.androidDomain
        return configureChart { $0.yDomain = domain }
    }

    func chartXScale(domain: ClosedRange<some Plottable>, type _: ScaleType? = nil) -> some View {
        let domain = domain.androidDomain
        return configureChart { $0.xDomain = domain }
    }

    func chartYScale(range _: ClosedRange<CGFloat>) -> some View { self }
    /// A categorical domain: the renderer orders categories as the data first lists them.
    func chartXScale(domain _: [String]) -> some View { self }
    func chartYScale(domain _: [String]) -> some View { self }
    func chartXScale(range _: ClosedRange<CGFloat>) -> some View { self }

    func chartForegroundStyleScale(_ mapping: KeyValuePairs<String, Color>) -> some View {
        let colors = Dictionary(mapping.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        return configureChart { $0.seriesColors = colors }
    }

    /// A style range the renderer can use only where its entries are plain colors.
    func chartForegroundStyleScale(domain: [some Plottable], range: [some ShapeStyle]) -> some View {
        let names = domain.map { value -> String in
            if case let .category(name) = value.androidPlotted { return name }
            return String(describing: value)
        }
        let colors = Dictionary(zip(names, range).compactMap { name, style in (style as? Color).map { (name, $0) } }, uniquingKeysWith: { first, _ in first })
        return configureChart { $0.seriesColors = colors }
    }

    func chartForegroundStyleScale(domain: [String], range: [Color]) -> some View {
        let colors = Dictionary(zip(domain, range).map { ($0, $1) }, uniquingKeysWith: { first, _ in first })
        return configureChart { $0.seriesColors = colors }
    }

    func chartForegroundStyleScale<V>(_: @escaping (V) -> Color) -> some View { self }

    func chartLegend(_: Visibility) -> some View { self }
    func chartLegend(position _: AnnotationPosition = .automatic, alignment _: Alignment? = nil, spacing _: CGFloat? = nil) -> some View { self }
    func chartYAxisLabel(_: String, position _: AnnotationPosition = .automatic, alignment _: Alignment? = nil, spacing _: CGFloat? = nil) -> some View { self }
    func chartYAxisLabel(_: Text, position _: AnnotationPosition = .automatic, alignment _: Alignment? = nil, spacing _: CGFloat? = nil) -> some View { self }
    func chartXAxisLabel(_: String, position _: AnnotationPosition = .automatic, alignment _: Alignment? = nil, spacing _: CGFloat? = nil) -> some View { self }
    func chartXSelection(value _: Binding<(some Any)?>) -> some View { self }
    func chartXSelection(range _: Binding<ClosedRange<some Any>?>) -> some View { self }
    func chartOverlay(alignment _: Alignment = .center, @ViewBuilder content _: @escaping (ChartProxy) -> some View) -> some View { self }
    func chartBackground(alignment _: Alignment = .center, @ViewBuilder content _: @escaping (ChartProxy) -> some View) -> some View { self }
    func chartPlotStyle(@ViewBuilder content _: @escaping (ChartPlotContent) -> some View) -> some View { self }
    func chartScrollableAxes(_: Axis.Set) -> some View { self }
    func chartXVisibleDomain(length _: some Numeric) -> some View { self }
    func chartScrollPosition(x _: Binding<some Any>) -> some View { self }
    func chartScrollPosition(initialX _: some Any) -> some View { self }
    func chartXScrollWindow(fullLength _: some Any, window _: some Any, initialX _: some Any) -> some View { self }
    func chartGesture(_: @escaping (ChartProxy) -> Void) -> some View { self }
}

enum ScaleType { case linear, log, squareRoot, date, category, symmetricLog }

/// Where the plot sits inside the chart's geometry; the stand-in renderer does not report it.
struct ChartPlotAnchor {}

extension GeometryProxy {
    subscript(_: ChartPlotAnchor) -> CGRect { .zero }
}

struct ChartProxy {
    var plotSize: CGSize { .zero }
    var plotFrame: ChartPlotAnchor? { nil }
    func value<V>(atX _: CGFloat, as _: V.Type) -> V? { nil }
    func position(forX _: some Any) -> CGFloat? { nil }
    func position(forY _: some Any) -> CGFloat? { nil }
}

struct ChartPlotContent: View {
    var body: some View { EmptyView() }
}

// MARK: - Chart

struct Chart: View {
    private let marks: [ChartMark]
    @Environment(\.androidChartConfiguration) var configuration

    init(@ChartContentBuilder content: () -> [ChartMark]) {
        marks = content().stacked
    }

    init<Data: RandomAccessCollection>(_ data: Data, @ChartContentBuilder content: (Data.Element) -> [ChartMark]) {
        marks = data.flatMap(content).stacked
    }

    var body: some View {
        let marks = marks
        let configuration = configuration
        Canvas { context, size in
            ChartRenderer(marks: marks, configuration: configuration, size: size).draw(in: &context)
        }
    }
}

private struct ChartRenderer {
    let marks: [ChartMark]
    let configuration: ChartAxisConfiguration
    let size: CGSize

    private static let palette: [Color] = [.accentColor, .blue, .orange, .green, .purple, .pink, .teal, .red]

    private var categories: [String] {
        var seen: [String] = []
        for mark in marks {
            for value in [mark.x, mark.xStart, mark.xEnd] {
                if case let .category(name)? = value, !seen.contains(name) { seen.append(name) }
            }
        }
        return seen
    }

    private func number(_ value: PlottedValue?, categories: [String]) -> Double? {
        switch value {
        case let .number(n)?: n
        case let .date(d)?: d.timeIntervalSinceReferenceDate
        case let .category(c)?: categories.firstIndex(of: c).map { Double($0) + 0.5 }
        case nil: nil
        }
    }

    func draw(in context: inout GraphicsContext) {
        let categories = categories
        let xs = marks.flatMap { [$0.x, $0.xStart, $0.xEnd] }.compactMap { number($0, categories: categories) }
        let ys = marks.flatMap { [$0.y, $0.yStart, $0.yEnd] }.compactMap { number($0, categories: []) }
        guard !xs.isEmpty || !ys.isEmpty else { return }

        var xDomain = configuration.xDomain ?? ((xs.min() ?? 0) ... (xs.max() ?? 1))
        if !categories.isEmpty, configuration.xDomain == nil { xDomain = 0 ... Double(categories.count) }
        let hasBars = marks.contains { $0.kind == .bar }
        var yDomain = configuration.yDomain ?? (min(hasBars ? 0 : (ys.min() ?? 0), ys.min() ?? 0) ... (ys.max() ?? 1))
        if xDomain.lowerBound == xDomain.upperBound { xDomain = (xDomain.lowerBound - 1) ... (xDomain.upperBound + 1) }
        if yDomain.lowerBound == yDomain.upperBound { yDomain = (yDomain.lowerBound - 1) ... (yDomain.upperBound + 1) }

        let leading: CGFloat = configuration.yHidden ? 0 : 34
        let bottom: CGFloat = configuration.xHidden ? 0 : 18
        let plot = CGRect(x: leading, y: 4, width: max(1, size.width - leading - 4), height: max(1, size.height - bottom - 8))

        func px(_ value: Double) -> CGFloat {
            plot.minX + CGFloat((value - xDomain.lowerBound) / (xDomain.upperBound - xDomain.lowerBound)) * plot.width
        }
        func py(_ value: Double) -> CGFloat {
            plot.maxY - CGFloat((value - yDomain.lowerBound) / (yDomain.upperBound - yDomain.lowerBound)) * plot.height
        }

        drawGrid(&context, plot: plot, yDomain: yDomain, xDomain: xDomain, categories: categories, py: py, px: px)

        let grouped = Dictionary(grouping: marks.enumerated(), by: { "\($0.element.kind)|\($0.element.series ?? "")" })
        for (_, group) in grouped.sorted(by: { $0.value.first!.offset < $1.value.first!.offset }) {
            let series = group.map(\.element)
            guard let first = series.first else { continue }
            let color = first.color ?? first.series.flatMap { configuration.seriesColors[$0] } ?? seriesColor(first.series)
            context.opacity = first.opacity
            switch first.kind {
            case .line:
                let points = series.compactMap { mark -> CGPoint? in
                    guard let x = number(mark.x, categories: categories), let y = number(mark.y, categories: []) else { return nil }
                    return CGPoint(x: px(x), y: py(y))
                }.sorted { $0.x < $1.x }
                context.stroke(Self.path(through: points, smooth: first.interpolation != .linear), with: .color(color), style: first.strokeStyle)
            case .area:
                let points = series.compactMap { mark -> (CGPoint, CGFloat)? in
                    guard let x = number(mark.x, categories: categories) else { return nil }
                    let top = number(mark.yEnd ?? mark.y, categories: []) ?? 0
                    let base = number(mark.yStart, categories: []) ?? max(yDomain.lowerBound, 0)
                    return (CGPoint(x: px(x), y: py(top)), py(base))
                }.sorted { $0.0.x < $1.0.x }
                guard let firstPoint = points.first, let lastPoint = points.last else { continue }
                var path = Self.path(through: points.map(\.0), smooth: first.interpolation != .linear)
                path.addLine(to: CGPoint(x: lastPoint.0.x, y: lastPoint.1))
                for point in points.reversed() { path.addLine(to: CGPoint(x: point.0.x, y: point.1)) }
                path.addLine(to: firstPoint.0)
                path.closeSubpath()
                context.opacity = first.opacity * (first.color == nil ? 0.3 : 1)
                context.fill(path, with: .color(color))
            case .point:
                for mark in series {
                    guard let x = number(mark.x, categories: categories), let y = number(mark.y, categories: []) else { continue }
                    let radius = max(2, sqrt(mark.symbolSize) / 2)
                    context.fill(Path(ellipseIn: CGRect(x: px(x) - radius, y: py(y) - radius, width: radius * 2, height: radius * 2)), with: .color(mark.color ?? color))
                }
            case .rule:
                for mark in series {
                    var path = Path()
                    if let x = number(mark.x, categories: categories) {
                        let top = number(mark.yEnd, categories: []).map(py) ?? plot.minY
                        let base = number(mark.yStart, categories: []).map(py) ?? plot.maxY
                        path.move(to: CGPoint(x: px(x), y: base))
                        path.addLine(to: CGPoint(x: px(x), y: top))
                    } else if let y = number(mark.y, categories: []) {
                        let start = number(mark.xStart, categories: categories).map(px) ?? plot.minX
                        let end = number(mark.xEnd, categories: categories).map(px) ?? plot.maxX
                        path.move(to: CGPoint(x: start, y: py(y)))
                        path.addLine(to: CGPoint(x: end, y: py(y)))
                    }
                    context.stroke(path, with: .color(mark.color ?? color), style: mark.strokeStyle.lineWidth == 2 ? StrokeStyle(lineWidth: 1) : mark.strokeStyle)
                }
            case .bar, .rectangle:
                let slot = categories.isEmpty ? max(2, plot.width / CGFloat(max(series.count, 1)) * 0.7) : plot.width / CGFloat(categories.count) * 0.7
                for mark in series {
                    let rect: CGRect
                    if let xStart = number(mark.xStart, categories: categories), let xEnd = number(mark.xEnd, categories: categories) {
                        let y = number(mark.y, categories: []) ?? 0
                        let height: CGFloat = mark.kind == .bar ? 10 : plot.height / 8
                        let top = number(mark.yEnd, categories: []).map(py)
                        let base = number(mark.yStart, categories: []).map(py)
                        if let top, let base {
                            rect = CGRect(x: px(xStart), y: top, width: px(xEnd) - px(xStart), height: base - top)
                        } else {
                            rect = CGRect(x: px(xStart), y: py(y) - height / 2, width: px(xEnd) - px(xStart), height: height)
                        }
                    } else if mark.kind == .rectangle, mark.x == nil, mark.y == nil,
                              let yStart = number(mark.yStart, categories: []), let yEnd = number(mark.yEnd, categories: []) {
                        rect = CGRect(x: plot.minX, y: py(yEnd), width: plot.width, height: py(yStart) - py(yEnd))
                    } else if let x = number(mark.x, categories: categories) {
                        let top = py(number(mark.yEnd ?? mark.y, categories: []) ?? 0)
                        let base = py(number(mark.yStart, categories: []) ?? max(yDomain.lowerBound, 0))
                        rect = CGRect(x: px(x) - slot / 2, y: min(top, base), width: slot, height: abs(base - top))
                    } else {
                        continue
                    }
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(mark.color ?? color))
                }
            }
        }
        context.opacity = 1
    }

    private func seriesColor(_ series: String?) -> Color {
        guard let series else { return Self.palette[0] }
        let names = Array(Set(marks.compactMap(\.series))).sorted()
        return Self.palette[(names.firstIndex(of: series) ?? 0) % Self.palette.count]
    }

    private func drawGrid(
        _ context: inout GraphicsContext, plot: CGRect, yDomain: ClosedRange<Double>, xDomain: ClosedRange<Double>,
        categories: [String], py: (Double) -> CGFloat, px: (Double) -> CGFloat,
    ) {
        let grid = Color.secondary.opacity(0.25)
        if !configuration.yHidden {
            for value in Self.ticks(yDomain, count: 4) {
                var line = Path()
                line.move(to: CGPoint(x: plot.minX, y: py(value)))
                line.addLine(to: CGPoint(x: plot.maxX, y: py(value)))
                context.stroke(line, with: .color(grid), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                context.draw(
                    Text(Self.format(value, span: yDomain.upperBound - yDomain.lowerBound)).font(.caption2).foregroundStyle(Color.secondary),
                    at: CGPoint(x: plot.minX - 4, y: py(value)), anchor: .trailing,
                )
            }
        }
        guard !configuration.xHidden else { return }
        if !categories.isEmpty {
            for (index, name) in categories.enumerated() where categories.count <= 12 {
                drawXLabel(&context, Text(name).font(.caption2).foregroundStyle(Color.secondary), x: px(Double(index) + 0.5), y: plot.maxY + 9)
            }
        } else if marks.contains(where: { if case .date = $0.x { true } else { false } }) {
            let span = xDomain.upperBound - xDomain.lowerBound
            for value in Self.ticks(xDomain, count: 4) {
                let date = Date(timeIntervalSinceReferenceDate: value)
                let label = span > 3 * 86400 ? date.formatted(.dateTime.month(.abbreviated).day()) : date.formatted(.dateTime.hour())
                drawXLabel(&context, Text(label).font(.caption2).foregroundStyle(Color.secondary), x: px(value), y: plot.maxY + 9)
            }
        } else {
            for value in Self.ticks(xDomain, count: 4) {
                drawXLabel(
                    &context,
                    Text(Self.format(value, span: xDomain.upperBound - xDomain.lowerBound)).font(.caption2).foregroundStyle(Color.secondary),
                    x: px(value), y: plot.maxY + 9,
                )
            }
        }
    }

    /// An x-axis label centered under its value, slid inside the chart when centering it would run
    /// past either edge, as Swift Charts keeps its axis labels in bounds. The anchor moves to the
    /// edge it would cross, so Compose lines the label up with that edge by its measured width.
    private func drawXLabel(_ context: inout GraphicsContext, _ text: Text, x: CGFloat, y: CGFloat) {
        let half = context.resolve(text).measure(in: size).width / 2
        if x - half < 0 {
            context.draw(text, at: CGPoint(x: 0, y: y), anchor: .leading)
        } else if x + half > size.width {
            context.draw(text, at: CGPoint(x: size.width, y: y), anchor: .trailing)
        } else {
            context.draw(text, at: CGPoint(x: x, y: y))
        }
    }

    private static func ticks(_ domain: ClosedRange<Double>, count: Int) -> [Double] {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return [domain.lowerBound] }
        let rough = span / Double(count)
        let magnitude = pow(10, floor(log10(rough)))
        let step = [1, 2, 2.5, 5, 10].map { $0 * magnitude }.first { $0 >= rough } ?? rough
        var value = ceil(domain.lowerBound / step) * step
        var out: [Double] = []
        while value <= domain.upperBound + step * 1e-9, out.count < 12 {
            out.append(value)
            value += step
        }
        return out
    }

    private static func format(_ value: Double, span: Double) -> String {
        span < 10 ? value.formatted(.number.precision(.fractionLength(0 ... 1))) : value.formatted(.number.precision(.fractionLength(0)))
    }

    private static func path(through points: [CGPoint], smooth: Bool) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard smooth, points.count > 2 else {
            for point in points.dropFirst() { path.addLine(to: point) }
            return path
        }
        for index in 1 ..< points.count {
            let previous = points[index - 1]
            let current = points[index]
            let mid = (current.x - previous.x) / 2
            path.addCurve(
                to: current,
                control1: CGPoint(x: previous.x + mid, y: previous.y),
                control2: CGPoint(x: current.x - mid, y: current.y),
            )
        }
        return path
    }
}
