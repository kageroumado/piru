import Foundation
import Testing
@testable import Piru

@Suite("TimelineCurvePalette")
struct TimelineCurvePaletteTests {
    /// A dose whose phases end at 30 / 60 / 120 / 180 minutes, running 240.
    private func state(at start: Date) -> ActiveSubstanceState {
        ActiveSubstanceState(
            substanceName: "Testine",
            colorHex: "8394ff",
            doseTimestamp: start,
            amount: 100,
            unit: "mg",
            route: "oral",
            onsetEndMinutes: 15,
            comeupEndMinutes: 30,
            peakEndMinutes: 60,
            offsetEndMinutes: 120,
            afterglowEndMinutes: 180,
            totalMinutes: 240,
        )
    }

    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: - Phase boundaries

    @Test
    func `Each phase covers its own stretch of the dose's arc`() {
        let s = state(at: start)
        #expect(TimelineCurvePhase.phase(minutes: 0, of: s) == .onset)
        #expect(TimelineCurvePhase.phase(minutes: 29, of: s) == .onset)
        #expect(TimelineCurvePhase.phase(minutes: 30, of: s) == .peak)
        #expect(TimelineCurvePhase.phase(minutes: 59, of: s) == .peak)
        #expect(TimelineCurvePhase.phase(minutes: 60, of: s) == .offset)
        #expect(TimelineCurvePhase.phase(minutes: 119, of: s) == .offset)
        #expect(TimelineCurvePhase.phase(minutes: 120, of: s) == .after)
        #expect(TimelineCurvePhase.phase(minutes: 240, of: s) == .after)
    }

    @Test
    func `Outside the modeled window a point carries no phase`() {
        let s = state(at: start)
        #expect(TimelineCurvePhase.phase(minutes: -1, of: s) == nil)
        #expect(TimelineCurvePhase.phase(minutes: 241, of: s) == nil)
    }

    @Test
    func `A redose restarts the arc: the newest dose owns the point`() {
        let first = state(at: start)
        let second = state(at: start.addingTimeInterval(90 * 60))
        // 100 minutes in, the first dose is in its offset and the second is
        // ten minutes into its come-up: the line turns light again.
        let t = start.addingTimeInterval(100 * 60)
        #expect(TimelineCurvePhase.phase(at: t, states: [first, second]) == .onset)
        #expect(TimelineCurvePhase.phase(at: t, states: [first]) == .offset)
    }

    @Test
    func `A moment no dose covers has no phase`() {
        let s = state(at: start)
        #expect(TimelineCurvePhase.phase(at: start.addingTimeInterval(-60), states: [s]) == nil)
    }

    // MARK: - Splitting a curve into runs

    @Test
    func `Consecutive points in one phase become one segment`() {
        let segments = TimelineCurveSegment.segments(of: [.onset, .onset, .peak, .peak, .offset])
        #expect(segments.count == 3)
        #expect(segments[0] == TimelineCurveSegment(range: 0 ... 2, phase: .onset))
        #expect(segments[1] == TimelineCurveSegment(range: 2 ... 4, phase: .peak))
        #expect(segments[2] == TimelineCurveSegment(range: 4 ... 4, phase: .offset))
    }

    @Test
    func `Neighboring segments share their boundary point so the strokes meet`() {
        let segments = TimelineCurveSegment.segments(of: [.peak, .peak, .offset, .offset])
        for (a, b) in zip(segments, segments.dropFirst()) {
            #expect(a.range.upperBound == b.range.lowerBound)
        }
    }

    @Test
    func `A phaseless curve is one segment`() {
        let segments = TimelineCurveSegment.segments(of: [nil, nil, nil])
        #expect(segments == [TimelineCurveSegment(range: 0 ... 2, phase: nil)])
    }

    @Test
    func `An empty curve has no segments`() {
        #expect(TimelineCurveSegment.segments(of: []).isEmpty)
    }

    // MARK: - Oklch shifts

    /// A mid-lightness blue, the shape of a substance color.
    private let base = Oklch(l: 0.62, c: 0.16, h: 265)

    @Test
    func `Onset lightens, peak is the color itself, offset deepens and warms`() {
        #expect(abs(TimelineCurvePhase.onset.shifted(base).l - 0.74) < 0.0001)
        #expect(TimelineCurvePhase.peak.shifted(base) == base)

        let offset = TimelineCurvePhase.offset.shifted(base)
        #expect(abs(offset.l - 0.56) < 0.0001)
        #expect(abs(offset.h - 280) < 0.0001)
        #expect(abs(offset.c - base.c) < 0.0001)
    }

    @Test
    func `The afterglow keeps half the chroma at the same lightness and hue`() {
        let after = TimelineCurvePhase.after.shifted(base)
        #expect(abs(after.c - base.c / 2) < 0.0001)
        #expect(after.l == base.l)
        #expect(after.h == base.h)
    }

    @Test
    func `A hue shift past the circle wraps rather than running off`() {
        #expect(abs(Oklch(l: 0.6, c: 0.1, h: 350).shifted(hue: 15).h - 5) < 0.0001)
        #expect(abs(Oklch(l: 0.6, c: 0.1, h: 5).shifted(hue: -15).h - 350) < 0.0001)
    }

    @Test
    func `Lightness clamps at the ends and chroma never goes negative`() {
        #expect(Oklch(l: 0.95, c: 0.1, h: 30).shifted(lightness: 0.2).l == 1)
        #expect(Oklch(l: 0.05, c: 0.1, h: 30).shifted(lightness: -0.2).l == 0)
        #expect(Oklch(l: 0.5, c: 0.1, h: 30).shifted(chromaScale: -1).c == 0)
    }

    // MARK: - Oklch round trip

    @Test
    func `Linear sRGB survives the round trip through Oklch`() {
        for (r, g, b) in [(0.2, 0.35, 0.9), (0.8, 0.1, 0.3), (0.05, 0.6, 0.4), (0.5, 0.5, 0.5)] {
            let back = Oklch(linearRed: r, green: g, blue: b).linearRGB
            #expect(abs(back.red - r) < 0.001)
            #expect(abs(back.green - g) < 0.001)
            #expect(abs(back.blue - b) < 0.001)
        }
    }

    @Test
    func `A gray has no chroma and full white is lightness one`() {
        #expect(Oklch(linearRed: 0.5, green: 0.5, blue: 0.5).c < 0.001)
        #expect(abs(Oklch(linearRed: 1, green: 1, blue: 1).l - 1) < 0.001)
    }
}
