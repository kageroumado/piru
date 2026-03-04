import Testing
@testable import Piru

@Suite("DoseRange")
struct DoseRangeTests {

    let range = DoseRange(
        threshold: 10,
        light: 15...30,
        common: 30...60,
        strong: 60...100,
        heavy: 100
    )

    // MARK: - Level classification

    @Test("Sub-threshold dose")
    func subThreshold() {
        #expect(range.level(for: 5) == .sub)
    }

    @Test("Threshold dose")
    func threshold() {
        #expect(range.level(for: 10) == .threshold)
    }

    @Test("Light dose")
    func light() {
        #expect(range.level(for: 20) == .light)
    }

    @Test("Common dose")
    func common() {
        #expect(range.level(for: 45) == .common)
    }

    @Test("Strong dose")
    func strong() {
        #expect(range.level(for: 80) == .strong)
    }

    @Test("Heavy dose")
    func heavy() {
        #expect(range.level(for: 120) == .heavy)
    }

    @Test("Very heavy dose still classifies as heavy")
    func veryHeavy() {
        #expect(range.level(for: 250) == .heavy)
    }

    // MARK: - Boundary values

    @Test("Exact threshold boundary")
    func exactThreshold() {
        #expect(range.level(for: 10) == .threshold)
    }

    @Test("Exact heavy boundary")
    func exactHeavy() {
        #expect(range.level(for: 100) == .heavy)
    }

    @Test("Well above heavy is still heavy")
    func wellAboveHeavy() {
        #expect(range.level(for: 200) == .heavy)
    }

    @Test("Just below threshold")
    func belowThreshold() {
        #expect(range.level(for: 9.9) == .sub)
    }

    @Test("Light lower bound")
    func lightLowerBound() {
        #expect(range.level(for: 15) == .light)
    }

    @Test("Light upper bound")
    func lightUpperBound() {
        #expect(range.level(for: 30) == .common)
    }

    // MARK: - Edge cases

    @Test("All nil ranges returns sub")
    func allNil() {
        let empty = DoseRange(threshold: nil, light: nil, common: nil, strong: nil, heavy: nil)
        #expect(empty.level(for: 1000) == .sub)
    }

    @Test("Only threshold set")
    func onlyThreshold() {
        let partial = DoseRange(threshold: 5, light: nil, common: nil, strong: nil, heavy: nil)
        #expect(partial.level(for: 3) == .sub)
        #expect(partial.level(for: 5) == .threshold)
        #expect(partial.level(for: 100) == .threshold)
    }

    @Test("Only heavy set")
    func onlyHeavy() {
        let partial = DoseRange(threshold: nil, light: nil, common: nil, strong: nil, heavy: 50)
        #expect(partial.level(for: 30) == .sub)
        #expect(partial.level(for: 50) == .heavy)
    }

    @Test("Zero dose")
    func zeroDose() {
        #expect(range.level(for: 0) == .sub)
    }

    @Test("Negative dose")
    func negativeDose() {
        #expect(range.level(for: -5) == .sub)
    }
}

// MARK: - DoseLevel

@Suite("DoseLevel")
struct DoseLevelTests {

    @Test("All dose levels have colors")
    func allLevelsHaveColors() {
        for level in DoseLevel.allCases {
            #expect(!level.color.isEmpty)
        }
    }

    @Test("Color mapping is correct")
    func colorMapping() {
        #expect(DoseLevel.sub.color == "gray")
        #expect(DoseLevel.threshold.color == "blue")
        #expect(DoseLevel.light.color == "green")
        #expect(DoseLevel.common.color == "yellow")
        #expect(DoseLevel.strong.color == "orange")
        #expect(DoseLevel.heavy.color == "red")
    }

    @Test("Raw values are display strings")
    func rawValues() {
        #expect(DoseLevel.sub.rawValue == "Sub-threshold")
        #expect(DoseLevel.heavy.rawValue == "Heavy")
    }
}
