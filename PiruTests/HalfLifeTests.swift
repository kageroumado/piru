import Foundation
import Testing
@testable import Piru

@Suite("HalfLife")
struct HalfLifeTests {
    // MARK: - The representative number

    @Test
    func `A range's representative is its geometric mean`() {
        let halfLife = HalfLife(rangeMinutes: 240 ... 1560)
        #expect(halfLife.representative == (240.0 * 1560.0).squareRoot())
        // Which is nearer the low end than an arithmetic mean would be, because elimination
        // runs on the log scale: 612 min, not 900.
        #expect(abs(halfLife.representative - 611.9) < 0.1)
    }

    @Test
    func `The geometric mean sits the same number of half-lives from each end`() {
        let range = 7.0 * 60 ... 10.0 * 60
        let mean = HalfLife.geometricMean(of: range)
        #expect(abs((mean / range.lowerBound) - (range.upperBound / mean)) < 1e-9)
    }

    @Test
    func `A value the source states wins over the range's mean`() {
        // Clozapine: "4–26 hours (mean value 14.2 hours in steady state conditions)".
        let halfLife = HalfLife(minutes: 852, rangeMinutes: 240 ... 1560)
        #expect(halfLife.representative == 852)
        #expect(halfLife.rangeMinutes == 240 ... 1560)
    }

    @Test
    func `With no range the single value is the representative`() {
        let halfLife = HalfLife(minutes: 360)
        #expect(halfLife.representative == 360)
        #expect(halfLife.rangeMinutes == nil)
        #expect(halfLife.isRange == false)
    }

    // MARK: - Building from the database's columns

    @Test
    func `Three columns build a range, a point value, or nothing`() {
        #expect(HalfLife(minutes: 1_440, lower: 1_080, upper: 1_980)?.rangeMinutes == 1_080 ... 1_980)
        #expect(HalfLife(minutes: 360, lower: nil, upper: nil)?.representative == 360)
        #expect(HalfLife(minutes: nil, lower: nil, upper: nil) == nil)
    }

    @Test
    func `A half range or an inverted one is dropped, never guessed at`() {
        #expect(HalfLife(minutes: 600, lower: 400, upper: nil)?.rangeMinutes == nil)
        #expect(HalfLife(minutes: 600, lower: 900, upper: 400)?.rangeMinutes == nil)
        #expect(HalfLife(minutes: nil, lower: 900, upper: 400) == nil)
        // A range with no point value still builds, deriving the one number.
        #expect(HalfLife(minutes: nil, lower: 420, upper: 600)?.representative
            == (420.0 * 600.0).squareRoot())
    }

    // MARK: - What a surface shows

    @Test
    func `A range reads as a range, in one unit`() {
        #expect(HalfLife(rangeMinutes: 1_080 ... 1_980).displayText == "18–33 h")
        #expect(HalfLife(rangeMinutes: 20 ... 45).displayText == "20–45 min")
        #expect(HalfLife(rangeMinutes: 240 ... 1_560).displayText == "4–26 h")
    }

    @Test
    func `Both ends share one unit, the one the low end asks for`() {
        // 72–210 min would read "72 min–3.5 h" if each end chose for itself.
        #expect(HalfLife(rangeMinutes: 72 ... 210).displayText == "1.2–3.5 h")
        // Norflurazepam, 47–150 h. Choosing days off the top end would flatten the low end
        // to "2 days"; the low end's own unit keeps both ends legible.
        #expect(HalfLife(rangeMinutes: 2_820 ... 9_000).displayText == "47–150 h")
    }

    @Test
    func `A point value reads as one number`() {
        #expect(HalfLife(minutes: 360).displayText == "6 h")
        #expect(HalfLife(minutes: 45).displayText == "45 min")
        #expect(HalfLife(minutes: 318).displayText == "5.3 h")
    }

    @Test
    func `A clean value keeps its clean form`() {
        #expect(HalfLife.scalarText(1_260) == "21 h")
        #expect(HalfLife.scalarText(3_960) == "2.8 days")
    }

    // MARK: - The substance's own accessor

    @Test
    func `Substance exposes the range and one number to compute with`() {
        let ranged = Substance(
            name: "Ranged", aliases: [], category: .other, defaultRoute: .oral, routes: [],
            effects: [], halfLifeMinutes: 1_440, halfLifeRangeMinutes: 1_080 ... 1_980,
        )
        #expect(ranged.halfLife?.displayText == "18–33 h")
        #expect(ranged.halfLife?.representative == 1_440)
        #expect(ranged.halfLifeMinutes == 1_440)

        let point = Substance(
            name: "Point", aliases: [], category: .other, defaultRoute: .oral, routes: [],
            effects: [], halfLifeMinutes: 360,
        )
        #expect(point.halfLife?.isRange == false)
        #expect(point.halfLife?.displayText == "6 h")

        let unknown = Substance(
            name: "Unknown", aliases: [], category: .other, defaultRoute: .oral, routes: [],
            effects: [],
        )
        #expect(unknown.halfLife == nil)
    }

    @Test
    func `A range survives a Codable round trip`() throws {
        let original = Substance(
            name: "Ranged", aliases: [], category: .other, defaultRoute: .oral, routes: [],
            effects: [], halfLifeMinutes: 852, halfLifeRangeMinutes: 240 ... 1_560,
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Substance.self, from: data)
        #expect(decoded.halfLifeRangeMinutes == 240 ... 1_560)
        #expect(decoded.halfLifeMinutes == 852)
    }
}
