import Testing
@testable import Piru

@Suite("DurationProfile")
struct DurationProfileTests {
    // MARK: - Estimated total minutes

    @Test
    func `Uses total when provided`() {
        let profile = DurationProfile(
            onset: DurationRange(min: 10, max: 20),
            comeup: DurationRange(min: 15, max: 25),
            peak: DurationRange(min: 60, max: 120),
            offset: DurationRange(min: 30, max: 60),
            afterglow: nil,
            total: DurationRange(min: 180, max: 300),
        )
        #expect(profile.estimatedTotalMinutes == 240) // (180+300)/2
    }

    @Test
    func `Sums phase midpoints when no total`() {
        let profile = DurationProfile(
            onset: DurationRange(min: 10, max: 20), // midpoint 15
            comeup: DurationRange(min: 20, max: 30), // midpoint 25
            peak: DurationRange(min: 60, max: 120), // midpoint 90
            offset: DurationRange(min: 30, max: 60), // midpoint 45
            afterglow: DurationRange(min: 60, max: 120),
            total: nil,
        )
        #expect(profile.estimatedTotalMinutes == 175) // 15+25+90+45
    }

    @Test
    func `Afterglow is not included in estimated total`() {
        let profile = DurationProfile(
            onset: DurationRange(min: 10, max: 10), // 10
            comeup: DurationRange(min: 10, max: 10), // 10
            peak: DurationRange(min: 10, max: 10), // 10
            offset: DurationRange(min: 10, max: 10), // 10
            afterglow: DurationRange(min: 1_000, max: 2_000),
            total: nil,
        )
        #expect(profile.estimatedTotalMinutes == 40)
    }

    @Test
    func `Some phases nil`() {
        let profile = DurationProfile(
            onset: DurationRange(min: 10, max: 20), // midpoint 15
            comeup: nil,
            peak: DurationRange(min: 60, max: 120), // midpoint 90
            offset: nil,
            afterglow: nil,
            total: nil,
        )
        #expect(profile.estimatedTotalMinutes == 105) // 15+90
    }

    @Test
    func `All phases nil returns zero`() {
        let profile = DurationProfile(
            onset: nil, comeup: nil, peak: nil,
            offset: nil, afterglow: nil, total: nil,
        )
        #expect(profile.estimatedTotalMinutes == 0)
    }

    // MARK: - Phase boundaries

    @Test
    func `Phase boundaries accumulate correctly`() {
        let profile = DurationProfile(
            onset: DurationRange(min: 10, max: 20), // midpoint 15
            comeup: DurationRange(min: 20, max: 30), // midpoint 25
            peak: DurationRange(min: 60, max: 120), // midpoint 90
            offset: DurationRange(min: 30, max: 60), // midpoint 45
            afterglow: DurationRange(min: 60, max: 120), // midpoint 90
            total: nil,
        )
        let b = profile.phaseBoundaries
        #expect(b.onsetEnd == 15)
        #expect(b.comeupEnd == 40)
        #expect(b.peakEnd == 130)
        #expect(b.offsetEnd == 175)
        #expect(b.afterglowEnd == 265)
    }

    @Test
    func `Phase boundaries with nil phases`() {
        let profile = DurationProfile(
            onset: nil,
            comeup: nil,
            peak: DurationRange(min: 60, max: 120), // midpoint 90
            offset: nil,
            afterglow: nil,
            total: nil,
        )
        let b = profile.phaseBoundaries
        #expect(b.onsetEnd == 0)
        #expect(b.comeupEnd == 0)
        #expect(b.peakEnd == 90)
        #expect(b.offsetEnd == 90)
        #expect(b.afterglowEnd == 90)
    }

    @Test
    func `All nil phases produce zero boundaries`() {
        let profile = DurationProfile(
            onset: nil, comeup: nil, peak: nil,
            offset: nil, afterglow: nil, total: nil,
        )
        let b = profile.phaseBoundaries
        #expect(b.onsetEnd == 0)
        #expect(b.comeupEnd == 0)
        #expect(b.peakEnd == 0)
        #expect(b.offsetEnd == 0)
        #expect(b.afterglowEnd == 0)
    }

    // MARK: - Filling missing phases (endpoint-only data → renderable curve)

    /// The LSD-oral case: onset + total + afterglow, no come-up/peak/offset.
    /// Raw, the curve collapses to ~onset length; filled, it spans the total.
    @Test
    func `Endpoint-only profile is filled to span the total`() {
        let raw = DurationProfile(
            onset: DurationRange(min: 45, max: 90), // midpoint 67.5
            comeup: nil, peak: nil, offset: nil,
            afterglow: DurationRange(min: 720, max: 1_440),
            total: DurationRange(min: 540, max: 840), // midpoint 690
        )
        // Raw collapses: offsetEnd ≈ onset length, discarding the 690-min total.
        #expect(raw.phaseBoundaries.offsetEnd < 100)

        let filled = raw.fillingMissingPhases(for: .psychedelic)
        // Filled curve ends (offsetEnd) right at the stated total.
        #expect(abs(filled.phaseBoundaries.offsetEnd - 690) < 1)
        // Onset is preserved, afterglow untouched, all shapers now present.
        #expect(filled.onset?.midpoint == 67.5)
        #expect(filled.comeup != nil)
        #expect(filled.peak != nil)
        #expect(filled.offset != nil)
        #expect(filled.afterglow?.midpoint == raw.afterglow?.midpoint)
    }

    @Test
    func `Complete profile is left unchanged`() {
        let complete = DurationProfile(
            onset: DurationRange(min: 15, max: 30),
            comeup: DurationRange(min: 45, max: 90),
            peak: DurationRange(min: 180, max: 300),
            offset: DurationRange(min: 180, max: 300),
            afterglow: DurationRange(min: 720, max: 1_440),
            total: DurationRange(min: 480, max: 720),
        )
        let filled = complete.fillingMissingPhases(for: .psychedelic)
        #expect(filled.comeup?.midpoint == complete.comeup?.midpoint)
        #expect(filled.peak?.midpoint == complete.peak?.midpoint)
        #expect(filled.offset?.midpoint == complete.offset?.midpoint)
    }

    @Test
    func `Profile without a total is left unchanged`() {
        let raw = DurationProfile(
            onset: DurationRange(min: 15, max: 90), // midpoint 52.5
            comeup: nil, peak: nil, offset: nil,
            afterglow: DurationRange(min: 60, max: 360),
            total: nil,
        )
        let filled = raw.fillingMissingPhases(for: .antidepressant)
        // No total to anchor the span → no synthesis (half-life path handles it).
        #expect(filled.comeup == nil)
        #expect(filled.peak == nil)
        #expect(filled.offset == nil)
    }

    @Test
    func `Partial profile preserves real phases and fills the gaps`() {
        let raw = DurationProfile(
            onset: DurationRange(min: 10, max: 10), // 10
            comeup: nil,
            peak: DurationRange(min: 60, max: 60), // real peak, 60
            offset: nil,
            afterglow: nil,
            total: DurationRange(min: 240, max: 240),
        )
        let filled = raw.fillingMissingPhases(for: .stimulant)
        // The genuine peak is preserved; the missing come-up/offset are synthesized.
        #expect(filled.peak?.midpoint == 60)
        #expect(filled.comeup != nil)
        #expect(filled.offset != nil)
        #expect(abs(filled.phaseBoundaries.offsetEnd - 240) < 1)
    }
}
