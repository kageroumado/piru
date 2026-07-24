import SwiftUI

/// The effect-over-time curve for the redesigned Dose & Duration card: an
/// accent-tinted, theme-aware area curve of idealized intensity vs time for the
/// selected route, derived from the ``DurationProfile``'s phase boundaries
/// (rise · plateau · fall), with hour gridlines and faint phase bands.
///
/// Shares its curve math (``EffectCurveShape``) with the share card's monochrome
/// `MonochromeDoseGraph` so the two never drift; this is the in-app color version
/// that reads on the light detail background. Renders nothing meaningful when the
/// route has only a total and no phases — callers gate on ``canRender(_:)`` and
/// keep the onset/peak/total trio instead.
struct DurationCurveView: View {
    let boundaries: PhaseBoundaries
    var accent: Color = Theme.accent

    /// True when the profile has a shaped curve worth drawing — i.e. the phases
    /// span more than roughly the onset alone. A total-only route collapses to a
    /// spike and should show the trio without the curve.
    static func canRender(_ boundaries: PhaseBoundaries) -> Bool {
        boundaries.offsetEnd > boundaries.onsetEnd + 1
    }

    private struct Band: Identifiable {
        let id: Int
        let start: Double
        let end: Double
        let opacity: Double
    }

    private var bands: [Band] {
        [
            Band(id: 0, start: 0, end: boundaries.onsetEnd, opacity: 0.28),
            Band(id: 1, start: boundaries.onsetEnd, end: boundaries.comeupEnd, opacity: 0.40),
            Band(id: 2, start: boundaries.comeupEnd, end: boundaries.peakEnd, opacity: 0.60),
            Band(id: 3, start: boundaries.peakEnd, end: boundaries.offsetEnd, opacity: 0.34),
        ]
    }

    var body: some View {
        GeometryReader { geo in
            let total = max(boundaries.offsetEnd, 1)
            let width = geo.size.width
            let plotTop: CGFloat = 14
            let plotH = max(geo.size.height - plotTop, 1)
            let xf: (Double) -> CGFloat = { CGFloat($0 / total) * width }

            ZStack(alignment: .topLeading) {
                // Faint phase bands — deepen toward the peak so the plateau reads.
                // Masked to the area *under* the curve: drawn to the full plot
                // height they put tint above the line, which reads as the fill
                // bleeding out of the chart rather than as phase shading.
                ZStack(alignment: .topLeading) {
                    ForEach(bands) { band in
                        Rectangle().fill(accent.opacity(band.opacity * 0.20))
                            .frame(width: max(xf(band.end) - xf(band.start), 0), height: plotH)
                            .offset(x: xf(band.start), y: plotTop)
                    }
                }
                .frame(width: width, height: geo.size.height, alignment: .topLeading)
                .mask(alignment: .topLeading) {
                    EffectCurveShape(boundaries: boundaries)
                        .frame(width: width, height: plotH)
                        .offset(y: plotTop)
                }
                // Hour gridlines + labels.
                ForEach(hourMarks(total), id: \.self) { hour in
                    let hx = xf(Double(hour) * 60)
                    Rectangle().fill(Color.primary.opacity(0.08))
                        .frame(width: 1, height: plotH).offset(x: hx, y: plotTop)
                    Text(verbatim: "\(hour)h")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.secondaryLabel)
                        .offset(x: hx + 3, y: plotTop + plotH - 12)
                }
                // Filled area under the curve.
                EffectCurveShape(boundaries: boundaries)
                    .fill(LinearGradient(
                        colors: [accent.opacity(0.20), accent.opacity(0.0)],
                        startPoint: .top, endPoint: .bottom,
                    ))
                    .frame(height: plotH).offset(y: plotTop)
                // The intensity line itself.
                EffectCurveShape(boundaries: boundaries, strokeOnly: true)
                    .stroke(accent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .frame(height: plotH).offset(y: plotTop)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Effect over time: rises over the come-up, plateaus at peak, then falls.")
    }

    private func hourMarks(_ total: Double) -> [Int] {
        var out: [Int] = []
        var hour = 1
        while Double(hour) * 60 < total {
            out.append(hour)
            hour += 1
        }
        return out
    }
}

/// A stylized effect-over-time curve derived from a duration profile's phase
/// boundaries: an S-rise across come-up, a plateau across peak, a fall across
/// offset. The x-axis stops at `offsetEnd` (the acute end). `strokeOnly` traces
/// just the top line; otherwise it closes to the baseline for a fill.
///
/// Shared by ``DurationCurveView`` (in-app, accent) and the share card's
/// `MonochromeDoseGraph` (plate, monochrome) so both read on one curve.
struct EffectCurveShape: Shape {
    let boundaries: PhaseBoundaries
    var strokeOnly: Bool = false

    func path(in rect: CGRect) -> Path {
        let total = max(boundaries.offsetEnd, 1)
        let steps = 96
        var path = Path()
        if !strokeOnly { path.move(to: CGPoint(x: rect.minX, y: rect.maxY)) }
        for i in 0 ... steps {
            let f = Double(i) / Double(steps)
            let x = rect.minX + rect.width * CGFloat(f)
            let y = rect.maxY - rect.height * CGFloat(intensity(at: f * total))
            if i == 0, strokeOnly {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        if !strokeOnly {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }

    private func intensity(at t: Double) -> Double {
        let comeupEnd = max(boundaries.comeupEnd, boundaries.onsetEnd + 1)
        let peakEnd = max(boundaries.peakEnd, comeupEnd + 1)
        let offsetEnd = max(boundaries.offsetEnd, peakEnd + 1)
        func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
            guard b > a else { return x >= b ? 1 : 0 }
            let u = min(max((x - a) / (b - a), 0), 1)
            return u * u * (3 - 2 * u)
        }
        if t <= comeupEnd { return 0.06 + 0.94 * smooth(0, comeupEnd, t) }
        if t <= peakEnd { return 1 }
        return 0.06 + 0.94 * (1 - smooth(peakEnd, offsetEnd, t))
    }
}
