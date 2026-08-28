import Foundation
import Testing
@testable import Piru

/// Gates the benzodiazepine discontinuation reference's two tables. Individual bands are not
/// restated here — the DB row is the value, and the pipeline's `test_withdrawal_*` checks the rows
/// against what the cited review does and does not say. What these gate is the structure a rebuild
/// can silently break: intervals that stop tiling, an ordering that stops agreeing with the
/// half-lives, a floor that stops holding, and the example lists in Swift drifting away from the
/// rows they name.
@Suite("Withdrawal reference")
@MainActor
struct WithdrawalReferenceTests {
    let reference: WithdrawalReference

    init() {
        reference = SubstanceStore.shared.withdrawalReference()
    }

    /// Every acting class the app can produce must have a band to render, or a user whose drug lands
    /// in that class gets a screen with nothing on it.
    @Test
    func `Every acting class has a band`() {
        #expect(!reference.bands.isEmpty, "no withdrawal_timing_bands rows in the bundled DB")
        for actingClass in WithdrawalActingClass.allCases {
            #expect(reference.band(for: actingClass) != nil, "no band for \(actingClass.rawValue)")
        }
    }

    /// The intervals must tile the half-life line: start at zero, meet edge to edge, and end
    /// unbounded. A gap would leave a half-life that classifies as nothing; an overlap would make
    /// the classification depend on row order.
    @Test
    func `Half-life intervals tile without gaps or overlaps`() {
        let ascending = reference.bands.sorted { $0.minHalfLifeMinutes < $1.minHalfLifeMinutes }
        #expect(ascending.first?.minHalfLifeMinutes == 0)
        #expect(ascending.last?.maxHalfLifeMinutes == nil)
        for (lower, upper) in zip(ascending, ascending.dropFirst()) {
            #expect(
                lower.maxHalfLifeMinutes == upper.minHalfLifeMinutes,
                "\(lower.actingClass.rawValue) does not meet \(upper.actingClass.rawValue)",
            )
        }
        // Sampled across the range, including each boundary, every value lands somewhere.
        for minutes in [0.0, 1, 719, 720, 2_399, 2_400, 100_000] {
            #expect(reference.band(forMinutes: minutes) != nil, "\(minutes) min falls in no band")
        }
    }

    /// `rank` is the vocabulary's own ordering and the half-life intervals are the data's; they must
    /// say the same thing, or "the longer-acting of two bands" picks the wrong one.
    @Test
    func `Rank ordering agrees with the half-life intervals`() {
        let byHalfLife = reference.bands.sorted { $0.minHalfLifeMinutes < $1.minHalfLifeMinutes }
        let byRank = reference.bands.sorted { $0.actingClass.rank < $1.actingClass.rank }
        #expect(byHalfLife.map(\.actingClass) == byRank.map(\.actingClass))
    }

    /// Every window that ships must run forward — an inverted pair renders as "7–2 days" and would
    /// otherwise ship. A band may carry no window: Rickels measured a short and a long arm, and the
    /// intermediate band has no middle one to take a peak from.
    @Test
    func `Every shipped window runs forward, and at least two exist`() {
        var windowed = 0
        for band in reference.bands {
            guard let peak = band.peakHours else { continue }
            windowed += 1
            #expect(peak.lowerBound <= peak.upperBound, "\(band.actingClass.rawValue) runs backwards")
        }
        #expect(windowed >= 2, "no band carries a peak window — the loader dropped them")
    }

    /// Longer-acting bands must peak later. This is the whole claim the section makes — "longer-acting
    /// drugs peak later because the drug is still leaving your system" — so a reordering that broke it
    /// would contradict the footer on the same screen. Bands with no window sit out.
    @Test
    func `Longer-acting bands peak later`() {
        let ascending = reference.bands
            .sorted { $0.actingClass.rank < $1.actingClass.rank }
            .compactMap { band in band.peakHours.map { (band, $0) } }
        for ((_, shorter), (_, longer)) in zip(ascending, ascending.dropFirst()) {
            #expect(shorter.lowerBound < longer.lowerBound)
        }
    }

    /// The floor holds: chlordiazepoxide's parent half-life is ~10 h, which the intervals read as
    /// short, and only the clinical row keeps it in the long band where its nordazepam tail puts it.
    /// This is the row whose loss would be invisible on screen and wrong in the model.
    @Test
    func `Clinical floor outranks a shorter half-life`() {
        #expect(reference.classify(name: "chlordiazepoxide", effectiveHalfLifeMinutes: nil) == .long)
        #expect(reference.classify(name: "chlordiazepoxide", effectiveHalfLifeMinutes: 600) == .long)
    }

    /// Metabolite data only ever lengthens the band. A short effective half-life must not pull a
    /// drug below its floor, and a long one must lift an un-floored drug above what its parent says.
    @Test
    func `Metabolite half-life lengthens but never shortens`() {
        #expect(reference.classify(name: "diazepam", effectiveHalfLifeMinutes: 60) == .long)
        let unfloored = "__synthetic_prodrug_benzo__"
        #expect(reference.classify(name: unfloored, effectiveHalfLifeMinutes: 300) == .short)
        #expect(reference.classify(name: unfloored, effectiveHalfLifeMinutes: 4_200) == .long)
    }

    @Test
    func `Classification is case and whitespace insensitive`() {
        let plain = reference.classify(name: "diazepam", effectiveHalfLifeMinutes: nil)
        #expect(reference.classify(name: "  Diazepam ", effectiveHalfLifeMinutes: nil) == plain)
        #expect(reference.classify(name: "DIAZEPAM", effectiveHalfLifeMinutes: nil) == plain)
    }

    /// The windows are stored as hours and the phrase picks days or hours for itself, so the phrase
    /// is a lossy rendering that could silently round. Read the numbers back out and require them to
    /// reconstruct the window exactly — in whichever unit the phrase chose.
    @Test
    func `Window phrases reconstruct the window they came from`() {
        for band in reference.bands {
            guard let window = band.peakHours, let phrase = band.peakPhrase else { continue }
            let numbers = phrase.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            // A window whose bounds coincide states one figure, not two.
            let expected = window.lowerBound == window.upperBound ? 1 : 2
            #expect(numbers.count == expected, "\(phrase) does not state \(expected) bound(s)")
            guard numbers.count == expected else { continue }
            let scale = Double(numbers[numbers.count - 1]) == window.upperBound ? 1.0 : 24.0
            #expect(Double(numbers[0]) * scale == window.lowerBound, "\(phrase) rounds its start")
            #expect(
                Double(numbers[numbers.count - 1]) * scale == window.upperBound,
                "\(phrase) rounds its end",
            )
        }
    }

    /// The example names beside each band are copy (they are translated), so they are the one place
    /// this data is forked. Gate the fork: the English list must name exactly the drugs the rows put
    /// in that band, so a reclassified or removed row cannot leave a stale example behind.
    @Test
    func `Band examples name exactly the drugs the rows classify there`() {
        var expected: [WithdrawalActingClass: Set<String>] = [:]
        for (name, actingClass) in reference.floors {
            expected[actingClass, default: []].insert(name)
        }
        #expect(
            expected.count == WithdrawalActingClass.allCases.count,
            "some band has no floored drug to use as an example",
        )
        for (actingClass, names) in expected {
            let listed = Set(
                String(localized: actingClass.examples)
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() },
            )
            #expect(listed == names, "\(actingClass.rawValue) examples \(listed) vs rows \(names)")
        }
    }
}
