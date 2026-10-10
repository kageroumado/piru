// SwiftUI's Canvas for Android, where SkipFuseUI has none. The renderer runs against a
// GraphicsContext that records each fill, stroke and draw with the transform, opacity and
// clip in force at the time; the recording is then laid out as Compose shapes and text
// inside a canvas-sized frame. Every Canvas in the shared code draws through this unchanged.
//
// Text is placed by an estimated size (Compose measures it only at layout), so an anchor
// other than the center lands approximately.

import SwiftUI

struct Canvas<Symbols: View>: View {
    private let renderer: (inout GraphicsContext, CGSize) -> Void

    init(
        opaque _: Bool = false,
        rendersAsynchronously _: Bool = false,
        renderer: @escaping (inout GraphicsContext, CGSize) -> Void,
    ) where Symbols == EmptyView {
        self.renderer = renderer
    }

    var body: some View {
        GeometryReader { proxy in
            let items = GraphicsContext.record(size: proxy.size, renderer)
            ZStack(alignment: .topLeading) {
                ForEach(0 ..< items.count, id: \.self) { index in
                    CanvasItemView(item: items[index], size: proxy.size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }
}

/// Nonisolated like SwiftUI's: renderers draw from nonisolated helpers.
nonisolated struct GraphicsContext {
    final class Recording {
        var items: [CanvasItem] = []
    }

    enum Shading {
        case color(Color)
        case linear(Gradient, startPoint: CGPoint, endPoint: CGPoint)
        case radial(Gradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat)
        case conic(Gradient, center: CGPoint, angle: Angle)
        case foreground

        /// A tiled image (skin grain); Compose shapes take no image fill, so it draws nothing.
        static func tiledImage(_: Image, origin _: CGPoint = .zero, sourceRect _: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), scale _: CGFloat = 1) -> Shading {
            .color(.clear)
        }

        static func conicGradient(_ gradient: Gradient, center: CGPoint, angle: Angle = .zero, options _: GradientOptions = []) -> Shading {
            .conic(gradient, center: center, angle: angle)
        }

        static func style(_ style: some ShapeStyle) -> Shading {
            if let color = style as? Color { return .color(color) }
            return .foreground
        }

        static func linearGradient(_ gradient: Gradient, startPoint: CGPoint, endPoint: CGPoint, options _: GradientOptions = []) -> Shading {
            .linear(gradient, startPoint: startPoint, endPoint: endPoint)
        }

        static func radialGradient(
            _ gradient: Gradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat, options _: GradientOptions = [],
        ) -> Shading {
            .radial(gradient, center: center, startRadius: startRadius, endRadius: endRadius)
        }
    }

    struct GradientOptions: OptionSet {
        let rawValue: Int
        static let `repeat` = GradientOptions(rawValue: 1)
        static let mirror = GradientOptions(rawValue: 2)
        static let linearColor = GradientOptions(rawValue: 4)
    }

    struct BlendMode: Equatable {
        let name: String
        static let normal = BlendMode(name: "normal")
        static let multiply = BlendMode(name: "multiply")
        static let screen = BlendMode(name: "screen")
        static let overlay = BlendMode(name: "overlay")
        static let darken = BlendMode(name: "darken")
        static let lighten = BlendMode(name: "lighten")
        static let plusLighter = BlendMode(name: "plusLighter")
        static let plusDarker = BlendMode(name: "plusDarker")
        static let softLight = BlendMode(name: "softLight")
        static let hardLight = BlendMode(name: "hardLight")
        static let colorDodge = BlendMode(name: "colorDodge")
        static let colorBurn = BlendMode(name: "colorBurn")
        static let color = BlendMode(name: "color")
        static let difference = BlendMode(name: "difference")
        static let destinationOut = BlendMode(name: "destinationOut")
        static let destinationIn = BlendMode(name: "destinationIn")
        static let sourceAtop = BlendMode(name: "sourceAtop")
        static let destinationOver = BlendMode(name: "destinationOver")
    }

    struct ClipOptions: OptionSet {
        let rawValue: Int
        static let inverse = ClipOptions(rawValue: 1)
    }

    struct ResolvedText {
        let text: Text
        var shading: Shading = .foreground

        /// An estimate: Compose measures text only at layout, after the renderer has run.
        func measure(in size: CGSize) -> CGSize {
            CGSize(width: min(size.width, CGFloat(text.estimatedLength) * 7), height: min(size.height, 16))
        }

        func firstBaseline(in _: CGSize) -> CGFloat { 12 }
        func lastBaseline(in _: CGSize) -> CGFloat { 12 }
    }

    struct ResolvedImage {
        let image: Image
        var shading: Shading = .foreground
        var size: CGSize { CGSize(width: 24, height: 24) }
        var baseline: CGFloat { 24 }
    }

    let recording: Recording
    /// A default environment: the renderer runs outside any view's.
    var environment: EnvironmentValues { EnvironmentValues() }
    var transform: CGAffineTransform = .identity
    var opacity: Double = 1
    var blendMode: BlendMode = .normal
    private var clip: Path?

    static func record(size: CGSize, _ renderer: (inout GraphicsContext, CGSize) -> Void) -> [CanvasItem] {
        var context = GraphicsContext(recording: Recording())
        renderer(&context, size)
        return context.recording.items
    }

    private init(recording: Recording) {
        self.recording = recording
    }

    // MARK: Transform and state

    mutating func translateBy(x: CGFloat, y: CGFloat) {
        transform = CGAffineTransform(translationX: x, y: y).concatenating(transform)
    }

    mutating func scaleBy(x: CGFloat, y: CGFloat) {
        transform = CGAffineTransform(scaleX: x, y: y).concatenating(transform)
    }

    mutating func rotate(by angle: Angle) {
        transform = CGAffineTransform(rotationAngle: CGFloat(angle.radians)).concatenating(transform)
    }

    mutating func clip(to path: Path, style _: FillStyle = FillStyle(), options: ClipOptions = []) {
        guard !options.contains(.inverse) else { return }
        clip = path.applying(transform)
    }

    func drawLayer(content: (inout GraphicsContext) throws -> Void) rethrows {
        var layer = self
        try content(&layer)
    }

    // MARK: Drawing

    func fill(_ path: Path, with shading: Shading, style _: FillStyle = FillStyle()) {
        append(.fill(path.applying(transform), shading))
    }

    func stroke(_ path: Path, with shading: Shading, lineWidth: CGFloat = 1) {
        stroke(path, with: shading, style: StrokeStyle(lineWidth: lineWidth))
    }

    func stroke(_ path: Path, with shading: Shading, style: StrokeStyle) {
        let scale = sqrt(abs(transform.a * transform.d - transform.b * transform.c))
        var scaled = style
        scaled.lineWidth = style.lineWidth * (scale == 0 ? 1 : scale)
        append(.stroke(path.applying(transform), shading, scaled))
    }

    func resolve(_ text: Text) -> ResolvedText {
        ResolvedText(text: text)
    }

    func resolve(_ image: Image) -> ResolvedImage {
        ResolvedImage(image: image)
    }

    func draw(_ text: Text, at point: CGPoint, anchor: UnitPoint = .center) {
        draw(resolve(text), at: point, anchor: anchor)
    }

    func draw(_ text: ResolvedText, at point: CGPoint, anchor: UnitPoint = .center) {
        let size = text.measure(in: CGSize(width: 10_000, height: 10_000))
        let center = CGPoint(x: point.x + (0.5 - anchor.x) * size.width, y: point.y + (0.5 - anchor.y) * size.height)
        append(.text(text.text, text.shading, center.applying(transform), rotation))
    }

    func draw(_ text: ResolvedText, in rect: CGRect) {
        draw(text, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
    }

    func draw(_ image: Image, in rect: CGRect, style _: FillStyle = FillStyle()) {
        append(.image(image, .foreground, rect.applying(transform)))
    }

    func draw(_ image: ResolvedImage, in rect: CGRect, style _: FillStyle = FillStyle()) {
        append(.image(image.image, image.shading, rect.applying(transform)))
    }

    func draw(_ image: Image, at point: CGPoint, anchor: UnitPoint = .center) {
        draw(resolve(image), at: point, anchor: anchor)
    }

    func draw(_ image: ResolvedImage, at point: CGPoint, anchor: UnitPoint = .center) {
        let size = image.size
        let origin = CGPoint(x: point.x - anchor.x * size.width, y: point.y - anchor.y * size.height)
        draw(image, in: CGRect(origin: origin, size: size))
    }

    private var rotation: Angle {
        .radians(Double(atan2(transform.b, transform.a)))
    }

    private func append(_ kind: CanvasItem.Kind) {
        // An erase (a fade cut into what is already drawn) has no shape to lay out: each item
        // is its own Compose node, composited only over the page.
        guard blendMode != .destinationOut else { return }
        recording.items.append(CanvasItem(kind: kind, opacity: opacity, clip: clip))
    }
}

nonisolated struct CanvasItem {
    enum Kind {
        case fill(Path, GraphicsContext.Shading)
        case stroke(Path, GraphicsContext.Shading, StrokeStyle)
        case text(Text, GraphicsContext.Shading, CGPoint, Angle)
        case image(Image, GraphicsContext.Shading, CGRect)
    }

    let kind: Kind
    let opacity: Double
    let clip: Path?
}

private struct CanvasItemView: View {
    let item: CanvasItem
    let size: CGSize

    var body: some View {
        content
            .opacity(item.opacity)
            .clipShape(item.clip ?? Path(CGRect(origin: .zero, size: size)))
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case let .fill(path, shading):
            filled(path, shading)
        case let .stroke(path, shading, style):
            stroked(path, shading, style)
        case let .text(text, shading, center, rotation):
            textView(text, shading)
                .fixedSize()
                .rotationEffect(rotation)
                .position(x: center.x, y: center.y)
        case let .image(image, shading, rect):
            imageView(image, shading)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    @ViewBuilder
    private func filled(_ path: Path, _ shading: GraphicsContext.Shading) -> some View {
        switch shading {
        case let .color(color): path.fill(color)
        case let .linear(gradient, start, end):
            path.fill(LinearGradient(gradient: gradient, startPoint: unit(start), endPoint: unit(end)))
        case let .radial(gradient, center, startRadius, endRadius):
            path.fill(RadialGradient(gradient: gradient, center: unit(center), startRadius: startRadius, endRadius: endRadius))
        case let .conic(gradient, center, angle):
            path.fill(AngularGradient(gradient: gradient, center: unit(center), startAngle: angle, endAngle: .degrees(angle.degrees + 360)))
        case .foreground: path.fill(Color.primary)
        }
    }

    @ViewBuilder
    private func stroked(_ path: Path, _ shading: GraphicsContext.Shading, _ style: StrokeStyle) -> some View {
        switch shading {
        case let .color(color): path.stroke(color, style: style)
        case let .linear(gradient, start, end):
            path.stroke(LinearGradient(gradient: gradient, startPoint: unit(start), endPoint: unit(end)), style: style)
        case let .radial(gradient, _, _, _), let .conic(gradient, _, _): path.stroke(gradient.stops.first?.color ?? .primary, style: style)
        case .foreground: path.stroke(Color.primary, style: style)
        }
    }

    @ViewBuilder
    private func textView(_ text: Text, _ shading: GraphicsContext.Shading) -> some View {
        if case let .color(color) = shading { text.foregroundStyle(color) } else { text }
    }

    @ViewBuilder
    private func imageView(_ image: Image, _ shading: GraphicsContext.Shading) -> some View {
        if case let .color(color) = shading {
            image.resizable().foregroundStyle(color)
        } else {
            image.resizable()
        }
    }

    private func unit(_ point: CGPoint) -> UnitPoint {
        UnitPoint(x: size.width == 0 ? 0 : point.x / size.width, y: size.height == 0 ? 0 : point.y / size.height)
    }
}

private nonisolated extension Text {
    /// A rough glyph count for placing drawn text: the rendered string is only known to Compose.
    var estimatedLength: Int {
        max(1, String(describing: self).count / 3)
    }
}
