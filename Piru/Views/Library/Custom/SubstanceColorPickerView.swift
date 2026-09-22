import SwiftData
import SwiftUI

/// Picks a substance's color in Oklch, inside the Display P3 gamut: a
/// lightness × chroma plane for the current hue, a hue rail, and the way back
/// to the substance's class color.
///
/// The picker writes the result itself when the user confirms; the caller owns
/// dismissal through `onDone`, so it composes with a local `.sheet` and with
/// the navigator alike. Swiping the sheet away discards the edit.
struct SubstanceColorPickerView: View {
    let substanceName: String
    var onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var substanceColors: [SubstanceColor]
    @State private var model: OklchPickerModel?
    @State private var siblings: [Oklch] = []
    @State private var contentHeight: CGFloat = 560
    @State private var safeAreaBottom: CGFloat = 34

    /// The sheet's inline navigation bar, which sits above the measured content.
    private static let chromeAllowance: CGFloat = 64

    var body: some View {
        NavigationStack {
            ScrollView {
                if let model {
                    VStack(spacing: Spacing.xxl) {
                        PickerPreviewHeader(substanceName: substanceName, model: model)
                        OklchPlaneView(model: model, siblings: siblings)
                        OklchHueRail(model: model)
                        OklchReadout(color: model.color)
                        ClassColorButton(model: model)
                    }
                    .padding(.horizontal)
                    .padding(.top, Spacing.xl)
                    .padding(.bottom, Spacing.xxl)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .skinBackdrop()
            .navigationTitle("Choose Color")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if let model {
                            SubstanceColorStore.apply(model.choice, to: substanceName, in: modelContext)
                        }
                        onDone()
                    } label: {
                        Image(systemName: "checkmark").fontWeight(.semibold)
                    }
                    .accessibilityLabel("Done")
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { safeAreaBottom = max(0, $0) }
        }
        .presentationDetents([.height(contentHeight + Self.chromeAllowance + safeAreaBottom)])
        .task { load() }
    }

    private func load() {
        guard model == nil else { return }
        let key = substanceName.lowercased()
        let row = substanceColors.first { $0.substance.lowercased() == key }
        let defaultTint = SubstanceColorStore.defaultTint(for: substanceName)
        model = OklchPickerModel(
            current: row?.tint ?? defaultTint,
            usesDefault: row.map { $0.usesDefault && !$0.isLegacy } ?? true,
            defaultTint: defaultTint,
        )
        guard let category = SubstanceLibrary.lookup(substanceName)?.category else { return }
        siblings = substanceColors
            .filter { $0.substance.lowercased() != key && SubstanceLibrary.lookup($0.substance)?.category == category }
            .map { Oklch(displayP3: $0.tint) }
    }
}

// MARK: - Header

private struct PickerPreviewHeader: View {
    let substanceName: String
    let model: OklchPickerModel

    var body: some View {
        HStack(spacing: Spacing.xl) {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.tiny)
                .fill(model.tint.color)
                .frame(width: 5, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(CustomSubstanceStore.shared.displayName(for: substanceName))
                    .screenTitle()
                Text(model.usesDefault ? "Class color" : "Custom color")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer()
            Circle()
                .fill(model.tint.color)
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Plane

/// Lightness runs left to right, chroma bottom to top. The colored region is
/// what Display P3 can show at this hue; the hollow dots are the other
/// substances of the same class, so a distinct color is one you can see.
private struct OklchPlaneView: View {
    let model: OklchPickerModel
    let siblings: [Oklch]

    @State private var image: CGImage?
    @State private var ceilings: [Double] = []

    private enum Metrics {
        static let aspectRatio = 4.0 / 3.0
        static let outlineColumns = 96
        static let thumb = 28.0
        static let siblingDot = 10.0
        /// Siblings further than this from the current hue sit on a different
        /// plane and would mislead here.
        static let siblingHueWindow = 30.0
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(.quaternary)
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .clipShape(GamutShape(ceilings: ceilings))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                }
                ForEach(Array(visibleSiblings.enumerated()), id: \.offset) { _, sibling in
                    Circle()
                        .strokeBorder(.white, lineWidth: 1.5)
                        .shadow(radius: 1)
                        .frame(width: Metrics.siblingDot, height: Metrics.siblingDot)
                        .position(point(for: sibling, in: size))
                }
                PickerThumb(color: model.tint.color, diameter: Metrics.thumb)
                    .position(point(for: model.color, in: size))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    let plane = OklchPickerModel.Plane.self
                    let x = min(max(value.location.x / size.width, 0), 1)
                    let y = min(max(value.location.y / size.height, 0), 1)
                    model.setPlane(
                        lightness: plane.lightness.lowerBound + (plane.lightness.upperBound - plane.lightness.lowerBound) * x,
                        chroma: plane.chroma.upperBound * (1 - y),
                    )
                },
            )
        }
        .aspectRatio(Metrics.aspectRatio, contentMode: .fit)
        .onChange(of: model.color.h, initial: true) {
            image = OklchPickerRenderer.plane(hue: model.color.h)
            ceilings = OklchPickerRenderer.gamutCeilings(hue: model.color.h, columns: Metrics.outlineColumns)
        }
        .accessibilityRepresentation {
            VStack {
                Slider(
                    value: Binding(get: { model.color.l }, set: { model.setPlane(lightness: $0, chroma: model.color.c) }),
                    in: OklchPickerModel.Plane.lightness,
                ) { Text("Lightness") }
                Slider(
                    value: Binding(get: { model.color.c }, set: { model.setPlane(lightness: model.color.l, chroma: $0) }),
                    in: OklchPickerModel.Plane.chroma,
                ) { Text("Chroma") }
            }
        }
    }

    private var visibleSiblings: [Oklch] {
        siblings.filter { sibling in
            let delta = abs(sibling.h - model.color.h).truncatingRemainder(dividingBy: 360)
            return min(delta, 360 - delta) <= Metrics.siblingHueWindow
                && OklchPickerModel.Plane.lightness.contains(sibling.l)
        }
    }

    private func point(for color: Oklch, in size: CGSize) -> CGPoint {
        let plane = OklchPickerModel.Plane.self
        let x = (color.l - plane.lightness.lowerBound) / (plane.lightness.upperBound - plane.lightness.lowerBound)
        let y = 1 - color.c / plane.chroma.upperBound
        return CGPoint(x: min(max(x, 0), 1) * size.width, y: min(max(y, 0), 1) * size.height)
    }
}

/// The region of the plane Display P3 can show: under the chroma ceiling of
/// each lightness column.
private nonisolated struct GamutShape: Shape {
    let ceilings: [Double]

    func path(in rect: CGRect) -> Path {
        guard ceilings.count > 1 else { return Path() }
        let top = OklchPickerModel.Plane.chroma.upperBound
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for (index, ceiling) in ceilings.enumerated() {
            let x = rect.minX + rect.width * (Double(index) + 0.5) / Double(ceilings.count)
            let y = rect.minY + rect.height * (1 - min(ceiling, top) / top)
            if index == 0 { path.addLine(to: CGPoint(x: rect.minX, y: y)) }
            path.addLine(to: CGPoint(x: x, y: y))
            if index == ceilings.count - 1 { path.addLine(to: CGPoint(x: rect.maxX, y: y)) }
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Hue rail

private struct OklchHueRail: View {
    let model: OklchPickerModel

    @State private var image: CGImage?

    private enum Metrics {
        static let height = 32.0
        static let thumb = 28.0
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .clipShape(Capsule())
                }
                PickerThumb(color: model.tint.color, diameter: Metrics.thumb)
                    .position(x: model.color.h / 360 * width, y: Metrics.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    // Stops a hair short of 360°, which normalizes to 0° and
                    // would throw the thumb to the other end of the rail.
                    model.setHue(min(max(value.location.x / width, 0), 0.9999) * 360)
                },
            )
        }
        .frame(height: Metrics.height)
        .onChange(of: RailInputs(l: model.color.l, c: model.color.c), initial: true) {
            image = OklchPickerRenderer.hueRail(lightness: model.color.l, chroma: model.color.c)
        }
        .accessibilityRepresentation {
            Slider(value: Binding(get: { model.color.h }, set: { model.setHue($0) }), in: 0 ... 359) { Text("Hue") }
        }
    }

    private struct RailInputs: Equatable {
        let l: Double
        let c: Double
    }
}

// MARK: - Pieces

private struct PickerThumb: View {
    let color: Color
    let diameter: Double

    var body: some View {
        Circle()
            .fill(color)
            .overlay { Circle().strokeBorder(.white, lineWidth: 3) }
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}

private struct OklchReadout: View {
    let color: Oklch

    var body: some View {
        HStack(spacing: Spacing.xxl) {
            value("L", color.l.formatted(.number.precision(.fractionLength(2))))
            value("C", color.c.formatted(.number.precision(.fractionLength(3))))
            value("H", "\(color.h.formatted(.number.precision(.fractionLength(0))))°")
        }
        .font(.system(.footnote, design: .monospaced))
        .foregroundStyle(Theme.secondaryLabel)
        .accessibilityHidden(true)
    }

    private func value(_ label: String, _ number: String) -> some View {
        Text(verbatim: "\(label) \(number)")
    }
}

private struct ClassColorButton: View {
    let model: OklchPickerModel

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { model.restoreDefault() }
        } label: {
            HStack(spacing: Spacing.md) {
                Circle()
                    .fill(model.defaultColor.displayP3.color)
                    .frame(width: IconSize.iconCompact, height: IconSize.iconCompact)
                    .accessibilityHidden(true)
                Text("Use Class Color")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        }
        .buttonStyle(.plain)
        .disabled(model.usesDefault)
    }
}
