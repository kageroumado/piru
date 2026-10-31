// SwiftUI API that SkipFuseUI does not provide, each with its nearest Compose behavior.
// Modifiers that only tune an Apple-specific affordance (hit shapes, border shapes, scroll
// edge effects, layout priority) apply nothing: Compose lays the view out the same way
// without them. Views are rebuilt from the primitives Skip does bridge.

import SwiftUI

// MARK: - Modifiers with no Compose counterpart

struct ContentShapeKinds: OptionSet {
    let rawValue: Int
    static let interaction = ContentShapeKinds(rawValue: 1)
    static let dragPreview = ContentShapeKinds(rawValue: 2)
    static let contextMenuPreview = ContentShapeKinds(rawValue: 4)
    static let hoverEffect = ContentShapeKinds(rawValue: 8)
    static let focusEffect = ContentShapeKinds(rawValue: 16)
    static let accessibility = ContentShapeKinds(rawValue: 32)
}

struct ButtonBorderShape {
    static let automatic = ButtonBorderShape()
    static let capsule = ButtonBorderShape()
    static let circle = ButtonBorderShape()
    static let roundedRectangle = ButtonBorderShape()
    static func roundedRectangle(radius _: CGFloat) -> ButtonBorderShape { ButtonBorderShape() }
}

extension View {
    /// Compose hit-tests a view by its bounds, which is what most of these shapes describe.
    func contentShape(_: some Shape, eoFill _: Bool = false) -> some View { self }
    func contentShape(_: ContentShapeKinds, _: some Shape, eoFill _: Bool = false) -> some View { self }

    func buttonBorderShape(_: ButtonBorderShape) -> some View { self }
    func layoutPriority(_: Double) -> some View { self }
    func alignmentGuide(_: HorizontalAlignment, computeValue _: @escaping (ViewDimensions) -> CGFloat) -> some View { self }
    func alignmentGuide(_: VerticalAlignment, computeValue _: @escaping (ViewDimensions) -> CGFloat) -> some View { self }
    func gridColumnAlignment(_: HorizontalAlignment) -> some View { self }
    func gridCellColumns(_: Int) -> some View { self }
    func gridCellUnsizedAxes(_: Axis.Set) -> some View { self }
    func gridCellAnchor(_: UnitPoint) -> some View { self }
    func accessibilitySortPriority(_: Double) -> some View { self }
    func persistentSystemOverlays(_: Visibility) -> some View { self }
    func matchedGeometryEffect(
        id _: some Hashable, in _: AndroidNamespaceID, properties _: MatchedGeometryProperties = .frame,
        anchor _: UnitPoint = .center, isSource _: Bool = true,
    ) -> some View { self }

    func onScrollPhaseChange(_: @escaping (ScrollPhase, ScrollPhase) -> Void) -> some View { self }

    /// The bar stacked at the edge it names. SkipFuseUI has no safe-area inset, so the bar takes
    /// its own space instead of floating over the content's edge.
    func safeAreaBar(
        edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
        @ViewBuilder content: () -> some View,
    ) -> some View {
        let bar = content()
        // The flexible frame is a Compose weight: a scroll view above the bar would otherwise
        // take the whole height and push the bar out of its container.
        return VStack(alignment: alignment, spacing: spacing ?? 0) {
            if edge == .top { bar }
            frame(maxHeight: .infinity)
            if edge == .bottom { bar }
        }
        // Flexible itself too, or a parent stack measures it unbounded and the weight inside
        // has nothing to divide (both upstream uses sit on scroll views that fill).
        .frame(maxHeight: .infinity)
    }

    /// Shows the first phase: the cycle is an iOS flourish, and the resting frame reads the same.
    func phaseAnimator<Phase: Equatable>(
        _ phases: some Sequence<Phase>, trigger _: some Equatable = 0,
        @ViewBuilder content: @escaping (PlaceholderContentView<Self>, Phase) -> some View,
        animation _: @escaping (Phase) -> Animation? = { _ in .default },
    ) -> some View {
        Group {
            if let first = Array(phases).first {
                content(PlaceholderContentView(content: self), first)
            } else {
                self
            }
        }
    }
}

struct AndroidNamespaceID: Hashable, Sendable {}

struct MatchedGeometryProperties: OptionSet {
    let rawValue: Int
    static let position = MatchedGeometryProperties(rawValue: 1)
    static let size = MatchedGeometryProperties(rawValue: 2)
    static let frame: MatchedGeometryProperties = [.position, .size]
}

struct PlaceholderContentView<Content: View>: View {
    let content: Content
    var body: some View { content }
}

struct ViewDimensions {
    let width: CGFloat
    let height: CGFloat

    subscript(_: HorizontalAlignment) -> CGFloat { 0 }
    subscript(_: VerticalAlignment) -> CGFloat { 0 }
}

// MARK: - Modifiers SkipFuseUI declares unavailable

// substitutions.txt renames each call to its `android` twin here: redeclaring the unavailable
// signature would be ambiguous with SkipFuseUI's.

enum AndroidAccessibilityChildBehavior {
    case ignore
    case combine
    case contain
}

enum AndroidImageScale {
    case small
    case medium
    case large
}

extension View {
    /// TalkBack groups by Compose semantics; there is no per-view grouping to request.
    func androidAccessibilityElement(children _: AndroidAccessibilityChildBehavior = .ignore) -> some View { self }
    func androidAccessibilityHint(_: Text, isEnabled _: Bool = true) -> some View { self }
    func androidAccessibilityHint(_: LocalizedStringKey, isEnabled _: Bool = true) -> some View { self }
    func androidAccessibilityHint(_: String, isEnabled _: Bool = true) -> some View { self }
    func androidAccessibilityInputLabels(_: [Text], isEnabled _: Bool = true) -> some View { self }
    func androidAccessibilityInputLabels(_: [LocalizedStringKey], isEnabled _: Bool = true) -> some View { self }
    func androidAccessibilityInputLabels(_: [String], isEnabled _: Bool = true) -> some View { self }
    func androidMonospacedDigit() -> some View { self }
    func androidKerning(_: CGFloat) -> some View { self }
    func androidListRowInsets(_: EdgeInsets?) -> some View { self }
    func androidImageScale(_: AndroidImageScale) -> some View { self }
    func androidScrollEdgeEffectStyle(_: ScrollEdgeEffectStyle?, for _: Edge.Set) -> some View { self }
}

enum AndroidControlSize {
    case mini
    case small
    case regular
    case large
    case extraLarge
}

extension View {
    func androidControlSize(_: AndroidControlSize) -> some View { self }
    func androidTruncationMode(_: Text.TruncationMode) -> some View { self }

    /// Liquid Glass is Apple's; on Android the same surface is a quiet translucent fill.
    func androidGlassEffect(_: Glass = .regular, in shape: some Shape, isEnabled _: Bool = true) -> some View {
        background(shape.fill(Color.platformSecondarySystemBackground))
    }

    func androidGlassEffect(_: Glass = .regular, isEnabled _: Bool = true) -> some View {
        background(Capsule().fill(Color.platformSecondarySystemBackground))
    }
}

/// Groups glass shapes on iOS so they blend; with no glass to blend, it only holds them.
struct AndroidGlassEffectContainer<Content: View>: View {
    private let content: Content

    init(spacing _: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View { content }
}

extension ShapeStyle where Self == Color {
    /// The hierarchical levels SkipFuseUI marks unavailable, as the system draws them.
    static var androidTertiary: Color { Color.secondary.opacity(0.6) }
    static var androidQuaternary: Color { Color.secondary.opacity(0.35) }
    static var androidFillTertiary: Color { Color.platformTertiarySystemFill }
    static var androidFillSecondary: Color { Color.platformSecondarySystemFill }
    static var androidFillPrimary: Color { Color.platformSecondarySystemFill.opacity(1.3) }
    static var androidFillQuaternary: Color { Color.platformTertiarySystemFill.opacity(0.7) }
    static var separator: Color { Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.29) }
}

extension Text {
    func androidMonospacedDigit() -> Text { self }
    func androidKerning(_: CGFloat) -> Text { self }
}

extension Font {
    /// Nonisolated as SwiftUI's `Font.monospacedDigit()` is: renderers build fonts off the main actor.
    nonisolated func androidMonospacedDigit() -> Font { self }
}

extension Image {
    func androidImageScale(_: AndroidImageScale) -> some View { self }
}

// MARK: - Popover

extension View {
    /// A popover is a sheet on a phone-sized screen, which is what iOS shows there too.
    func popover(
        isPresented: Binding<Bool>, attachmentAnchor _: PopoverAttachmentAnchor = .rect(.bounds),
        arrowEdge _: Edge? = nil, @ViewBuilder content: @escaping () -> some View,
    ) -> some View {
        sheet(isPresented: isPresented, content: content)
    }
}

enum AndroidPresentationAdaptation {
    case automatic
    case none
    case popover
    case sheet
    case fullScreenCover
}

extension View {
    /// Presentations already adapt to the one size class a phone has.
    func androidPresentationCompactAdaptation(_: AndroidPresentationAdaptation) -> some View { self }
    func androidPresentationBackground(_: some ShapeStyle) -> some View { self }
    func androidPresentationBackground(alignment _: Alignment = .center, @ViewBuilder content _: () -> some View) -> some View { self }
    func androidListSectionSpacing(_: CGFloat) -> some View { self }
    func androidListSectionSpacing(_: AndroidListSectionSpacing) -> some View { self }
    func androidScrollBounceBehavior(_: AndroidScrollBounceBehavior, axes _: Axis.Set = [.vertical]) -> some View { self }
    func androidContentTransition(_: AndroidContentTransition) -> some View { self }
    func androidTextSelection(_: AndroidTextSelectability) -> some View { self }
    func androidAccessibilityAction(named _: Text, _: @escaping () -> Void) -> some View { self }
    func androidAccessibilityAction(named _: LocalizedStringKey, _: @escaping () -> Void) -> some View { self }
    func androidAccessibilityAction(_: AndroidAccessibilityActionKind = .default, _: @escaping () -> Void) -> some View { self }
    func androidScrollClipDisabled(_: Bool = true) -> some View { self }
    func androidSymbolEffect(_: AndroidSymbolEffect, options _: Any? = nil, value _: some Equatable) -> some View { self }
    func androidSymbolEffect(_: AndroidSymbolEffect, options _: Any? = nil, isActive _: Bool = true) -> some View { self }
    func androidTransaction(value _: some Equatable, _: @escaping (inout Transaction) -> Void) -> some View { self }

    /// The sheet's detents without a selection binding, which SkipFuseUI's sheet does not take.
    func androidPresentationDetents(_ detents: Set<PresentationDetent>, selection _: Binding<PresentationDetent>) -> some View {
        presentationDetents(detents)
    }

    func androidPresentationBackgroundInteraction(_: AndroidPresentationBackgroundInteraction) -> some View { self }
    func androidPresentationContentInteraction(_: AndroidPresentationContentInteraction) -> some View { self }
    func androidTransaction(_: @escaping (inout Transaction) -> Void) -> some View { self }
    func androidDynamicTypeSize(_: some Any) -> some View { self }
    func androidAccessibilityRepresentation(@ViewBuilder representation _: () -> some View) -> some View { self }
    /// Gesture locations are already in the view's own space on Compose.
    func androidCoordinateSpace(_: NamedCoordinateSpace) -> some View { self }
    func androidScrollPosition(id _: Binding<(some Hashable)?>, anchor _: UnitPoint? = nil) -> some View { self }

    func onScrollGeometryChange<T: Equatable>(
        for _: T.Type, of _: @escaping (ScrollGeometry) -> T, action _: @escaping (T, T) -> Void,
    ) -> some View { self }

    func accessibilityLabel(_ label: some StringProtocol) -> some View {
        accessibilityLabel(Text(String(label)))
    }

    func accessibilityValue(_ value: some StringProtocol) -> some View {
        accessibilityValue(Text(String(value)))
    }

    func lineLimit(_ limit: ClosedRange<Int>) -> some View {
        lineLimit(limit.upperBound)
    }

    func lineLimit(_: PartialRangeFrom<Int>) -> some View {
        lineLimit(nil)
    }
}

enum AndroidSymbolEffect {
    case replace
    case bounce
    case pulse
    case variableColor
    case scale
    case appear
    case disappear
    case wiggle
    case rotate
    case breathe
}

struct AndroidPresentationBackgroundInteraction {
    static let automatic = AndroidPresentationBackgroundInteraction()
    static let disabled = AndroidPresentationBackgroundInteraction()
    static let enabled = AndroidPresentationBackgroundInteraction()
    static func enabled(upThrough _: PresentationDetent) -> AndroidPresentationBackgroundInteraction { .enabled }
}

enum AndroidPresentationContentInteraction { case automatic, resizes, scrolls }

enum AndroidListSectionSpacing { case `default`, compact, custom(CGFloat) }
enum AndroidScrollBounceBehavior { case automatic, always, basedOnSize }
enum AndroidTextSelectability { case enabled, disabled }
enum AndroidAccessibilityActionKind { case `default`, escape, magicTap, delete, showMenu }

/// Content transitions are an iOS animation between two renders; Compose recomposes directly.
struct AndroidContentTransition {
    static let identity = AndroidContentTransition()
    static let opacity = AndroidContentTransition()
    static let interpolate = AndroidContentTransition()
    static func numericText(countsDown _: Bool = false) -> AndroidContentTransition { AndroidContentTransition() }
    static func numericText(value _: Double) -> AndroidContentTransition { AndroidContentTransition() }
    static func androidSymbolEffect(_: AndroidSymbolEffect, options _: Any? = nil) -> AndroidContentTransition { AndroidContentTransition() }
    static var androidSymbolEffect: AndroidContentTransition { AndroidContentTransition() }
}

enum PopoverAttachmentAnchor {
    case rect(Anchor)
    case point(UnitPoint)

    enum Anchor { case bounds }
}

// MARK: - Formatters

/// Foundation's ListFormatter, for the English-shaped lists the app joins: "a, b and c".
enum ListFormatter {
    static func localizedString(byJoining strings: [String]) -> String {
        guard strings.count > 1, let last = strings.last else { return strings.first ?? "" }
        return strings.dropLast().joined(separator: ", ") + " " + String(localized: "and") + " " + last
    }
}

extension DatePicker where Label == Text {
    /// A date up to a bound (`in: ...Date.now`), which SkipFuseUI marks unavailable: the closed
    /// range from the distant past, the same set of pickable dates.
    init(_ titleKey: LocalizedStringKey, selection: Binding<Date>, in range: PartialRangeThrough<Date>) {
        self.init(titleKey, selection: selection, in: Date.distantPast ... range.upperBound)
    }
}

extension Shape {
    /// A concrete-Color overload, so `strokeBorder(color.opacity(x))` has one reading.
    func strokeBorder(_ color: Color, lineWidth: CGFloat = 1, antialiased _: Bool = true) -> some View {
        stroke(color, lineWidth: lineWidth)
    }
}

extension Text {
    /// `Text(date, style: .relative)`, which Compose text cannot keep updating: the offset at render.
    init(androidRelative date: Date) {
        let seconds = Int(Date().timeIntervalSince(date))
        let magnitude = abs(seconds)
        let amount = switch magnitude {
        case ..<60: String(localized: "\(magnitude) sec")
        case ..<3600: String(localized: "\(magnitude / 60) min")
        case ..<86400: String(localized: "\(magnitude / 3600) hr")
        default: String(localized: "\(magnitude / 86400) days")
        }
        self.init(verbatim: amount)
    }
}

// MARK: - ContentUnavailableView

struct ContentUnavailableView<Label: View, Description: View, Actions: View>: View {
    private let label: Label
    private let description: Description
    private let actions: Actions

    init(@ViewBuilder label: () -> Label, @ViewBuilder description: () -> Description = { EmptyView() }, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.label = label()
        self.description = description()
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 12) {
            label
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            description
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            actions
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension ContentUnavailableView where Label == SwiftUI.Label<Text, Image>, Description == Text?, Actions == EmptyView {
    init(_ title: LocalizedStringKey, systemImage name: String, description: Text? = nil) {
        self.init(label: { SwiftUI.Label(title, systemImage: name) }, description: { description })
    }

    init(_ title: some StringProtocol, systemImage name: String, description: Text? = nil) {
        self.init(label: { SwiftUI.Label(String(title), systemImage: name) }, description: { description })
    }

    static var search: ContentUnavailableView {
        ContentUnavailableView("No Results", systemImage: "magnifyingglass")
    }

    static func search(text _: String) -> ContentUnavailableView {
        ContentUnavailableView(
            "No Results", systemImage: "magnifyingglass",
            description: Text("Check the spelling or try a new search."),
        )
    }
}

// MARK: - Grid

/// Rows of cells: columns align as far as each row's cells share widths, which holds for the
/// app's label-value grids.
struct Grid<Content: View>: View {
    private let alignment: Alignment
    private let verticalSpacing: CGFloat?
    private let content: Content

    init(alignment: Alignment = .center, horizontalSpacing _: CGFloat? = nil, verticalSpacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.verticalSpacing = verticalSpacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: alignment.horizontal, spacing: verticalSpacing) { content }
    }
}

struct GridRow<Content: View>: View {
    private let alignment: VerticalAlignment
    private let content: Content

    init(alignment: VerticalAlignment? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment ?? .center
        self.content = content()
    }

    var body: some View {
        HStack(alignment: alignment) { content }
    }
}

// MARK: - AnyLayout

protocol AndroidStackLayout {
    var anyLayout: AnyLayout { get }
}

struct HStackLayout: AndroidStackLayout {
    var alignment: VerticalAlignment = .center
    var spacing: CGFloat?
    var anyLayout: AnyLayout { AnyLayout(axis: .horizontal, horizontal: .center, vertical: alignment, spacing: spacing) }
}

struct VStackLayout: AndroidStackLayout {
    var alignment: HorizontalAlignment = .center
    var spacing: CGFloat?
    var anyLayout: AnyLayout { AnyLayout(axis: .vertical, horizontal: alignment, vertical: .center, spacing: spacing) }
}

struct ZStackLayout: AndroidStackLayout {
    var alignment: Alignment = .center
    var anyLayout: AnyLayout { AnyLayout(axis: nil, horizontal: alignment.horizontal, vertical: alignment.vertical, spacing: nil) }
}

/// A stack whose axis is a value, which is all the app switches between.
struct AnyLayout {
    fileprivate let axis: Axis?
    fileprivate let horizontal: HorizontalAlignment
    fileprivate let vertical: VerticalAlignment
    fileprivate let spacing: CGFloat?

    fileprivate init(axis: Axis?, horizontal: HorizontalAlignment, vertical: VerticalAlignment, spacing: CGFloat?) {
        self.axis = axis
        self.horizontal = horizontal
        self.vertical = vertical
        self.spacing = spacing
    }

    init(_ layout: some AndroidStackLayout) {
        self = layout.anyLayout
    }

    @ViewBuilder
    func callAsFunction(@ViewBuilder _ content: () -> some View) -> some View {
        switch axis {
        case .horizontal: HStack(alignment: vertical, spacing: spacing) { content() }
        case .vertical: VStack(alignment: horizontal, spacing: spacing) { content() }
        case nil: ZStack { content() }
        }
    }
}

// MARK: - TimelineView

protocol TimelineSchedule {
    /// Seconds between redraws.
    var androidInterval: TimeInterval { get }
}

struct PeriodicTimelineSchedule: TimelineSchedule {
    let androidInterval: TimeInterval
}

struct EveryMinuteTimelineSchedule: TimelineSchedule {
    var androidInterval: TimeInterval { 60 }
}

struct AnimationTimelineSchedule: TimelineSchedule {
    let androidInterval: TimeInterval
    let paused: Bool
}

extension TimelineSchedule where Self == PeriodicTimelineSchedule {
    static func periodic(from _: Date, by interval: TimeInterval) -> PeriodicTimelineSchedule {
        PeriodicTimelineSchedule(androidInterval: max(interval, 1.0 / 30))
    }
}

extension TimelineSchedule where Self == EveryMinuteTimelineSchedule {
    static var everyMinute: EveryMinuteTimelineSchedule { EveryMinuteTimelineSchedule() }
}

extension TimelineSchedule where Self == AnimationTimelineSchedule {
    static var animation: AnimationTimelineSchedule { AnimationTimelineSchedule(androidInterval: 1.0 / 30, paused: false) }

    static func animation(minimumInterval: Double? = nil, paused: Bool = false) -> AnimationTimelineSchedule {
        AnimationTimelineSchedule(androidInterval: minimumInterval ?? 1.0 / 30, paused: paused)
    }
}

struct TimelineViewDefaultContext {
    let date: Date
    let cadence: Cadence = .live

    enum Cadence: Comparable { case live, seconds, minutes }
}

/// Redraws its content on the schedule's interval from a task, which is what the schedule
/// asks of SwiftUI.
struct TimelineView<Schedule: TimelineSchedule, Content: View>: View {
    private let schedule: Schedule
    private let content: (TimelineViewDefaultContext) -> Content
    @State private var date = Date()

    init(_ schedule: Schedule, @ViewBuilder content: @escaping (TimelineViewDefaultContext) -> Content) {
        self.schedule = schedule
        self.content = content
    }

    var body: some View {
        content(TimelineViewDefaultContext(date: date))
            .task {
                if let animation = schedule as? AnimationTimelineSchedule, animation.paused { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(schedule.androidInterval))
                    date = Date()
                }
            }
    }
}

// MARK: - Shapes

/// A rounded rectangle; Android has no display corners to be concentric with, so the
/// minimum radius the shape asks for is its radius.
nonisolated struct ConcentricRectangle: Shape {
    var cornerRadius: CGFloat = 20

    init() {}

    init(corners: ConcentricCorners, isUniform _: Bool = false) {
        cornerRadius = corners.radius
    }

    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: cornerRadius)
    }
}

struct ConcentricCorners {
    let radius: CGFloat

    static func concentric(minimum: ConcentricMinimum = .fixed(20)) -> ConcentricCorners {
        ConcentricCorners(radius: minimum.radius)
    }

    static func fixed(_ radius: CGFloat) -> ConcentricCorners {
        ConcentricCorners(radius: radius)
    }
}

struct ConcentricMinimum: ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
    let radius: CGFloat

    init(radius: CGFloat) {
        self.radius = radius
    }

    init(integerLiteral value: Int) {
        radius = CGFloat(value)
    }

    init(floatLiteral value: Double) {
        radius = CGFloat(value)
    }

    static func fixed(_ radius: CGFloat) -> ConcentricMinimum {
        ConcentricMinimum(radius: radius)
    }
}

/// An image tiled as a fill. SkipFuseUI bridges only its own shape styles, so the texture is
/// dropped and the fill is clear, leaving the surface's own color.
typealias ImagePaint = Color

extension Color {
    init(image _: Image, sourceRect _: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), scale _: CGFloat = 1) {
        self = .clear
    }
}

// MARK: - ImageRenderer

/// Android has no offscreen SwiftUI rendering here, so an image is never produced and the
/// share paths that need one fall back to sharing text.
@Observable
final class ImageRenderer<Content: View> {
    var content: Content
    var scale: CGFloat = 1
    var proposedSize: ProposedViewSize = .unspecified
    var isOpaque = false

    init(content: Content) {
        self.content = content
    }
}

struct ProposedViewSize {
    var width: CGFloat?
    var height: CGFloat?

    static let unspecified = ProposedViewSize(width: nil, height: nil)
    static let zero = ProposedViewSize(width: 0, height: 0)
    static let infinity = ProposedViewSize(width: .infinity, height: .infinity)

    init(width: CGFloat?, height: CGFloat?) {
        self.width = width
        self.height = height
    }

    init(_ size: CGSize) {
        self.init(width: size.width, height: size.height)
    }
}

enum SearchScopeActivation {
    case automatic
    case onTextEntry
    case onSearchPresentation
}

extension View {
    /// Compose's search bar has no scope row; the Search tab's scope stays where it was seeded.
    func searchScopes(
        _: Binding<some Hashable>, activation _: SearchScopeActivation = .automatic, @ViewBuilder scopes _: () -> some View,
    ) -> some View { self }
}

extension View {
    /// SkipFuseUI has no safeAreaInset: the inset content is stacked against the view's edge,
    /// which shrinks the view by the content's height as the inset would. The flexible frame
    /// becomes a Compose weight, so a view that fills (a NavigationStack) leaves the inset room.
    func androidSafeAreaInset(
        edge: VerticalEdge, spacing: CGFloat? = nil, @ViewBuilder content: () -> some View,
    ) -> some View {
        VStack(spacing: spacing ?? 0) {
            if edge == .top {
                content()
                frame(maxHeight: .infinity)
            } else {
                frame(maxHeight: .infinity)
                content()
            }
        }
    }
}

extension Binding {
    /// SkipFuseUI marks `Binding.animation(_:)` unavailable. The same thing written out: a
    /// binding whose writes run inside `withAnimation`.
    func androidAnimation(_ animation: Animation? = .default) -> Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: { newValue in withAnimation(animation) { wrappedValue = newValue } },
        )
    }
}

extension LocalizedStringKey.StringInterpolation {
    /// SkipFuseUI's interpolation takes any value by its description, which for an
    /// AttributedString is its runs with their attribute braces. Its characters are the text.
    mutating func appendInterpolation(_ value: AttributedString) {
        appendInterpolation(String(value.characters))
    }
}

extension AttributedString {
    /// SkipUI draws an AttributedString's text without its SwiftUI attributes, so a run's
    /// underline has nowhere to go: setting one is accepted and the text draws plain.
    var underlineStyle: Text.LineStyle? {
        get { nil }
        set {}
    }
}
