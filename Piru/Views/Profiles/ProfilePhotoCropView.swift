import SwiftUI

/// Move and scale a picked photo inside the avatar's circle. It opens framed
/// on the largest face, or centered when there is none.
struct ProfilePhotoCropView: View {
    let source: ProfilePhotoSource
    /// The chosen square, in the source's pixels with a top-left origin.
    let onChoose: (CGRect) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var frame = CropFrame.centered
    @State private var diameter: CGFloat = 300

    var body: some View {
        NavigationStack {
            let layout = CropLayout(imageSize: source.size, diameter: diameter)
            CropCanvas(source: source, layout: layout, frame: $frame)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    min(proxy.size.width - 48, proxy.size.height - 48, 340)
                } action: { resize(to: max($0, 120)) }
                .background(.black)
                .navigationTitle("Move and Scale")
                .inlineNavigationTitle()
            #if os(iOS)
                .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Choose") {
                            onChoose(layout.crop(for: frame))
                            dismiss()
                        }
                    }
                }
        }
        // Dark for this screen only: `preferredColorScheme` would carry over to
        // the editor sheet beneath it and stay after this one closes.
        .environment(\.colorScheme, .dark)
    }

    /// Frames the face on the first size, and keeps the same part of the
    /// photo under the circle on every later one.
    private func resize(to new: CGFloat) {
        let layout = CropLayout(imageSize: source.size, diameter: new)
        if frame.isInitial {
            frame = layout.framing(face: source.face)
        } else {
            let ratio = new / diameter
            frame = layout.clamped(CropFrame(
                zoom: frame.zoom,
                offset: CGSize(width: frame.offset.width * ratio, height: frame.offset.height * ratio),
            ))
        }
        diameter = new
    }
}

/// Where the photo sits under the circle: its zoom over "just covers the
/// circle", and its center's offset from the circle's center, in points.
struct CropFrame: Equatable {
    var zoom: CGFloat
    var offset: CGSize
    var isInitial = false

    static let centered = CropFrame(zoom: 1, offset: .zero, isInitial: true)
    static let maxZoom: CGFloat = 5
}

/// The geometry between a source photo and the circle it fills.
struct CropLayout {
    let imageSize: CGSize
    let diameter: CGFloat

    /// Points per pixel at zoom 1, where the short side spans the circle.
    private var baseScale: CGFloat {
        diameter / max(1, min(imageSize.width, imageSize.height))
    }

    func scale(for frame: CropFrame) -> CGFloat {
        baseScale * frame.zoom
    }

    /// `frame` with the zoom in range and the photo still covering the circle.
    func clamped(_ frame: CropFrame) -> CropFrame {
        let zoom = min(max(frame.zoom, 1), CropFrame.maxZoom)
        let scale = baseScale * zoom
        let slackX = max(0, (imageSize.width * scale - diameter) / 2)
        let slackY = max(0, (imageSize.height * scale - diameter) / 2)
        return CropFrame(
            zoom: zoom,
            offset: CGSize(
                width: min(max(frame.offset.width, -slackX), slackX),
                height: min(max(frame.offset.height, -slackY), slackY),
            ),
        )
    }

    /// The face a little under half the circle, a touch above center; the
    /// whole photo when there is no face.
    func framing(face: CGRect?) -> CropFrame {
        guard let face, face.width > 0 else { return clamped(CropFrame(zoom: 1, offset: .zero)) }
        let zoom = 0.45 * diameter / (max(face.width, face.height) * baseScale)
        let scale = baseScale * min(max(zoom, 1), CropFrame.maxZoom)
        let lift = face.height * 0.1
        return clamped(CropFrame(
            zoom: zoom,
            offset: CGSize(
                width: (imageSize.width / 2 - face.midX) * scale,
                height: (imageSize.height / 2 - (face.midY - lift)) * scale,
            ),
        ))
    }

    /// The square of source pixels the circle shows under `frame`.
    func crop(for frame: CropFrame) -> CGRect {
        let scale = scale(for: frame)
        let side = diameter / scale
        let centerX = imageSize.width / 2 - frame.offset.width / scale
        let centerY = imageSize.height / 2 - frame.offset.height / scale
        return CGRect(x: centerX - side / 2, y: centerY - side / 2, width: side, height: side)
    }
}

/// The photo under a circular window, dimmed outside it, with drag to move
/// and pinch to scale.
private struct CropCanvas: View {
    let source: ProfilePhotoSource
    let layout: CropLayout
    @Binding var frame: CropFrame

    @State private var dragStart: CGSize?
    @State private var zoomStart: CGFloat?

    var body: some View {
        let scale = layout.scale(for: frame)
        ZStack {
            Image(decorative: source.image, scale: 1)
                .resizable()
                .frame(width: source.size.width * scale, height: source.size.height * scale)
                .offset(frame.offset)
            CircleHole(diameter: layout.diameter)
                .fill(.black.opacity(0.6), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
            Circle()
                .strokeBorder(.white.opacity(0.8), lineWidth: 1)
                .frame(width: layout.diameter, height: layout.diameter)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .clipped()
        .gesture(drag.simultaneously(with: magnify))
        .accessibilityElement()
        .accessibilityLabel(Text("Photo"))
        .accessibilityHint(Text("Drag to move it, pinch to scale it."))
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStart ?? frame.offset
                dragStart = start
                var next = frame
                next.offset = CGSize(
                    width: start.width + value.translation.width,
                    height: start.height + value.translation.height,
                )
                frame = layout.clamped(next)
            }
            .onEnded { _ in dragStart = nil }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomStart ?? frame.zoom
                zoomStart = start
                var next = frame
                next.zoom = start * value.magnification
                // Scale about the circle's center: the offset grows with the zoom.
                let ratio = layout.clamped(next).zoom / max(frame.zoom, 0.001)
                next.offset = CGSize(width: frame.offset.width * ratio, height: frame.offset.height * ratio)
                frame = layout.clamped(next)
            }
            .onEnded { _ in zoomStart = nil }
    }
}

/// Everything but a centered circle, for the dimming around the crop.
private nonisolated struct CircleHole: Shape {
    let diameter: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addEllipse(in: CGRect(
            x: rect.midX - diameter / 2, y: rect.midY - diameter / 2, width: diameter, height: diameter,
        ))
        return path
    }
}
