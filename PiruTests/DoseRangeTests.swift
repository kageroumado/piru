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
        #expect(range.mgLevel(for: 5) == .sub)
    }

    @Test
    func `Threshold dose`() {
        #expect(range.mgLevel(for: 10) == .threshold)
    }

    @Test
    func `Light dose`() {
        #expect(range.mgLevel(for: 20) == .light)
    }

    @Test
    func `Common dose`() {
        #expect(range.mgLevel(for: 45) == .common)
    }

    @Test
    func `Strong dose`() {
        #expect(range.mgLevel(for: 80) == .strong)
    }

    @Test
    func `Heavy dose`() {
        #expect(range.mgLevel(for: 120) == .heavy)
    }

    @Test
    func `Very heavy dose still classifies as heavy`() {
        #expect(range.mgLevel(for: 250) == .heavy)
    }

    // MARK: - Boundary values

    @Test
    func `Exact threshold boundary`() {
        #expect(range.mgLevel(for: 10) == .threshold)
    }

    @Test
    func `Exact heavy boundary`() {
        #expect(range.mgLevel(for: 100) == .heavy)
    }

    @Test
    func `Well above heavy is still heavy`() {
        #expect(range.mgLevel(for: 200) == .heavy)
    }

    @Test
    func `Just below threshold`() {
        #expect(range.mgLevel(for: 9.9) == .sub)
    }

    @Test
    func `Light lower bound`() {
        #expect(range.mgLevel(for: 15) == .light)
    }

    @Test
    func `Light upper bound`() {
        #expect(range.mgLevel(for: 30) == .common)
    }

    // MARK: - Edge cases

    @Test
    func `All nil ranges place nothing`() {
        // A ladder with no tiers cannot say where a dose sits. Never answer
        // `.sub` here: it labels a custom substance logged with no dose data
        // "sub-threshold", a claim about the dose made from the absence of one.
        let empty = DoseRange(threshold: nil, light: nil, common: nil, strong: nil, heavy: nil)
        #expect(empty.mgLevel(for: 1_000) == nil)
    }

    @Test
    func `Only threshold set`() {
        let partial = DoseRange(threshold: 5, light: nil, common: nil, strong: nil, heavy: nil)
        #expect(partial.mgLevel(for: 3) == .sub)
        #expect(partial.mgLevel(for: 5) == .threshold)
        #expect(partial.mgLevel(for: 100) == .threshold)
    }

    @Test
    func `Only heavy set`() {
        let partial = DoseRange(threshold: nil, light: nil, common: nil, strong: nil, heavy: 50)
        #expect(partial.mgLevel(for: 30) == .sub)
        #expect(partial.mgLevel(for: 50) == .heavy)
    }

    @Test
    func `Zero dose`() {
        #expect(range.mgLevel(for: 0) == .sub)
    }

    @Test
    func `Negative dose`() {
        #expect(range.mgLevel(for: -5) == .sub)
    }

    @Test
    func `Band dose text keys each tier the ladder has by its dial band`() {
        let ladder = DoseRange(threshold: 30, light: 40 ... 75, common: nil, strong: 125 ... 175, heavy: 175)
        #expect(ladder.bandDoseText(unit: "mg") == [
            0: "30 mg", 1: "40–75 mg", 3: "125–175 mg", 4: "175+ mg",
        ])
    }
}

// MARK: - DoseLevel

@Suite("DoseLevel")
struct DoseLevelTests {
    @Test
    func `Raw values are display strings`() {
        #expect(DoseLevel.sub.rawValue == "Sub-threshold")
        #expect(DoseLevel.heavy.rawValue == "Heavy")
    }
}

extension DoseRange {
    /// Where `amount` sits on this range read as a milligram ladder — the tier
    /// logic alone, through the one public placement path.
    func mgLevel(for amount: Double) -> DoseLevel? {
        DoseLadder(range: self, unit: "mg").level(of: DoseQuantity(amount, unit: "mg"))
    }
}
