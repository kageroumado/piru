import Testing
@testable import Piru

@Suite("DurationProfile")
struct DurationProfileTests {

    // MARK: - Estimated total minutes

    @Test("Uses total when provided")
    func totalOverridesPhases() {
        let profile = DurationProfile(
            onset: DurationRange(min: 10, max: 20),
            comeup: DurationRange(min: 15, max: 25),
            peak: DurationRange(min: 60, max: 120),
            offset: DurationRange(min: 30, max: 60),
            afterglow: nil,
            total: DurationRange(min: 180, max: 300)
        )
        #expect(profile.estimatedTotalMinutes == 240) // (180+300)/2
    }

    @Test("Sums phase midpoints when no total")
    func sumsPhases() {
        let profile = DurationProfile(
            onset: DurationRange(min: 10, max: 20),     // midpoint 15
            comeup: DurationRange(min: 20, max: 30),    // midpoint 25
            peak: DurationRange(min: 60, max: 120),     // midpoint 90
            offset: DurationRange(min: 30, max: 60),    // midpoint 45
            afterglow: DurationRange(min: 60, max: 120),
            total: nil
        )
        #expect(profile.estimatedTotalMinutes == 175) // 15+25+90+45
    }

    @Test("Afterglow is not included in estimated total")
    func afterglowExcluded() {
        let profile = DurationProfile(
            onset: DurationRange(min: 10, max: 10),      // 10
            comeup: DurationRange(min: 10, max: 10),     // 10
            peak: DurationRange(min: 10, max: 10),       // 10
            offset: DurationRange(min: 10, max: 10),     // 10
            afterglow: DurationRange(min: 1000, max: 2000),
            total: nil
        )
        #expect(profile.estimatedTotalMinutes == 40)
    }

    @Test("Some phases nil")
    func somePhasesNil() {
        let profile = DurationProfile(
            onset: DurationRange(min: 10, max: 20),     // midpoint 15
            comeup: nil,
            peak: DurationRange(min: 60, max: 120),     // midpoint 90
            offset: nil,
            afterglow: nil,
            total: nil
        )
        #expect(profile.estimatedTotalMinutes == 105) // 15+90
    }

    @Test("All phases nil returns zero")
    func allPhasesNil() {
        let profile = DurationProfile(
            onset: nil, comeup: nil, peak: nil,
            offset: nil, afterglow: nil, total: nil
        )
        #expect(profile.estimatedTotalMinutes == 0)
    }

    // MARK: - Phase boundaries

    @Test("Phase boundaries accumulate correctly")
    func phaseBoundaries() {
        let profile = DurationProfile(
            onset: DurationRange(min: 10, max: 20),     // midpoint 15
            comeup: DurationRange(min: 20, max: 30),    // midpoint 25
            peak: DurationRange(min: 60, max: 120),     // midpoint 90
            offset: DurationRange(min: 30, max: 60),    // midpoint 45
            afterglow: DurationRange(min: 60, max: 120), // midpoint 90
            total: nil
        )
        let b = profile.phaseBoundaries
        #expect(b.onsetEnd == 15)
        #expect(b.comeupEnd == 40)
        #expect(b.peakEnd == 130)
        #expect(b.offsetEnd == 175)
        #expect(b.afterglowEnd == 265)
    }

    @Test("Phase boundaries with nil phases")
    func phaseBoundariesNilPhases() {
        let profile = DurationProfile(
            onset: nil,
            comeup: nil,
            peak: DurationRange(min: 60, max: 120),     // midpoint 90
            offset: nil,
            afterglow: nil,
            total: nil
        )
        let b = profile.phaseBoundaries
        #expect(b.onsetEnd == 0)
        #expect(b.comeupEnd == 0)
        #expect(b.peakEnd == 90)
        #expect(b.offsetEnd == 90)
        #expect(b.afterglowEnd == 90)
    }

    @Test("All nil phases produce zero boundaries")
    func allNilBoundaries() {
        let profile = DurationProfile(
            onset: nil, comeup: nil, peak: nil,
            offset: nil, afterglow: nil, total: nil
        )
        let b = profile.phaseBoundaries
        #expect(b.onsetEnd == 0)
        #expect(b.comeupEnd == 0)
        #expect(b.peakEnd == 0)
        #expect(b.offsetEnd == 0)
        #expect(b.afterglowEnd == 0)
    }
}
