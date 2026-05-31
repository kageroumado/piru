import Testing
@testable import Piru

@Suite("DoseRange")
struct DoseRangeTests {
    let range = DoseRange(
        threshold: 10,
        light: 15 ... 30,
        common: 30 ... 60,
        strong: 60 ... 100,
        heavy: 100,
    )

    // MARK: - Level classification

    @Test
    func `Sub-threshold dose`() {
        #expect(range.level(for: 5) == .sub)
    }

    @Test
    func `Threshold dose`() {
        #expect(range.level(for: 10) == .threshold)
    }

    @Test
    func `Light dose`() {
        #expect(range.level(for: 20) == .light)
    }

    @Test
    func `Common dose`() {
        #expect(range.level(for: 45) == .common)
    }

    @Test
    func `Strong dose`() {
        #expect(range.level(for: 80) == .strong)
    }

    @Test
    func `Heavy dose`() {
        #expect(range.level(for: 120) == .heavy)
    }

    @Test
    func `Very heavy dose still classifies as heavy`() {
        #expect(range.level(for: 250) == .heavy)
    }

    // MARK: - Boundary values

    @Test
    func `Exact threshold boundary`() {
        #expect(range.level(for: 10) == .threshold)
    }

    @Test
    func `Exact heavy boundary`() {
        #expect(range.level(for: 100) == .heavy)
    }

    @Test
    func `Well above heavy is still heavy`() {
        #expect(range.level(for: 200) == .heavy)
    }

    @Test
    func `Just below threshold`() {
        #expect(range.level(for: 9.9) == .sub)
    }

    @Test
    func `Light lower bound`() {
        #expect(range.level(for: 15) == .light)
    }

    @Test
    func `Light upper bound`() {
        #expect(range.level(for: 30) == .common)
    }

    // MARK: - Edge cases

    @Test
    func `All nil ranges returns sub`() {
        let empty = DoseRange(threshold: nil, light: nil, common: nil, strong: nil, heavy: nil)
        #expect(empty.level(for: 1_000) == .sub)
    }

    @Test
    func `Only threshold set`() {
        let partial = DoseRange(threshold: 5, light: nil, common: nil, strong: nil, heavy: nil)
        #expect(partial.level(for: 3) == .sub)
        #expect(partial.level(for: 5) == .threshold)
        #expect(partial.level(for: 100) == .threshold)
    }

    @Test
    func `Only heavy set`() {
        let partial = DoseRange(threshold: nil, light: nil, common: nil, strong: nil, heavy: 50)
        #expect(partial.level(for: 30) == .sub)
        #expect(partial.level(for: 50) == .heavy)
    }

    @Test
    func `Zero dose`() {
        #expect(range.level(for: 0) == .sub)
    }

    @Test
    func `Negative dose`() {
        #expect(range.level(for: -5) == .sub)
    }
}

// MARK: - DoseLevel

@Suite("DoseLevel")
struct DoseLevelTests {
    @Test
    func `All dose levels have colors`() {
        for level in DoseLevel.allCases {
            #expect(!level.color.isEmpty)
        }
    }

    @Test
    func `Color mapping is correct`() {
        #expect(DoseLevel.sub.color == "gray")
        #expect(DoseLevel.threshold.color == "blue")
        #expect(DoseLevel.light.color == "green")
        #expect(DoseLevel.common.color == "yellow")
        #expect(DoseLevel.strong.color == "orange")
        #expect(DoseLevel.heavy.color == "red")
    }

    @Test
    func `Raw values are display strings`() {
        #expect(DoseLevel.sub.rawValue == "Sub-threshold")
        #expect(DoseLevel.heavy.rawValue == "Heavy")
    }
}
