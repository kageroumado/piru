import Testing
@testable import Piru

@Suite("DurationRange")
struct TimeRangeTests {
    // MARK: - Midpoint

    @Test
    func `Midpoint of symmetric range`() {
        let range = DurationRange(min: 10, max: 30)
        #expect(range.midpoint == 20)
    }

    @Test
    func `Midpoint of equal values`() {
        let range = DurationRange(min: 15, max: 15)
        #expect(range.midpoint == 15)
    }

    @Test
    func `Midpoint produces decimal`() {
        let range = DurationRange(min: 10, max: 25)
        #expect(range.midpoint == 17.5)
    }

    // MARK: - Display string (minutes)

    //
    // The test plan pins the locale to en-US so `String(localized: …)` in
    // DurationRange.displayString resolves to the English source strings.

    @Test
    func `Display string in minutes when max < 120`() {
        let range = DurationRange(min: 15, max: 45)
        #expect(range.displayString == "~15 – 45 minutes")
    }

    @Test
    func `Display string in minutes at boundary (max = 119)`() {
        let range = DurationRange(min: 60, max: 119)
        #expect(range.displayString == "~60 – 119 minutes")
    }

    // MARK: - Display string (hours)

    @Test
    func `Display string in hours when max >= 120`() {
        let range = DurationRange(min: 120, max: 360)
        #expect(range.displayString == "~2 – 6 hours")
    }

    @Test
    func `Display string in hours at boundary (max = 120)`() {
        let range = DurationRange(min: 60, max: 120)
        #expect(range.displayString == "~1 – 2 hours")
    }

    @Test
    func `Display string in hours with decimals`() {
        let range = DurationRange(min: 90, max: 210)
        #expect(range.displayString == "~1.5 – 3.5 hours")
    }

    // MARK: - Formatting

    @Test
    func `Whole numbers formatted without decimal`() {
        let range = DurationRange(min: 30, max: 60)
        #expect(range.displayString == "~30 – 60 minutes")
    }

    @Test
    func `Decimal numbers rounded to whole minutes`() {
        let range = DurationRange(min: 15.5, max: 45.5)
        #expect(range.displayString == "~16 – 46 minutes")
    }
}
