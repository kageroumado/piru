import Foundation
import Testing
@testable import Piru

/// End-to-end gate for ``ToleranceStore/simulate`` — the pure replay wired to the *real* flagship
/// pharmacology data (Vd/Kᵢ/EC₅₀ via `SubstanceStore`), proving tolerance comes out dose-dependent
/// through the whole pipeline (curated DB → resolver → absolute molar PK → Hill occupancy → ODE),
/// and that the class-default Vd fallback lets substances without a graded Vd still resolve.
@Suite("ToleranceStore replay")
@MainActor
struct ToleranceStoreTests {
    static let now = Date(timeIntervalSince1970: 1_700_000_000)

    static func resolve(_ name: String) -> PharmacologyParameters? {
        SubstanceStore.shared.pharmacologyParameters(forSubstanceName: name)
    }

    /// `count` daily doses of `substance`, the most recent ending `lastDoseHoursAgo` before `now`.
    static func dailyDoses(
        _ substance: String, mg: Double, days: Int, lastDoseHoursAgo: Double = 24,
    ) -> [DoseEntry] {
        (0 ..< days).map { d in
            let daysBack = Double(days - 1 - d)
            let ts = now.addingTimeInterval(-daysBack * 86_400 - lastDoseHoursAgo * 3_600)
            return DoseEntry(substance: substance, amount: mg, unit: "mg", route: .oral, timestamp: ts)
        }
    }

    /// `perDay` doses spread evenly across each of `days` days — sustained high occupancy for the
    /// heavy-chronic case that engages the deep layer.
    static func clusteredDoses(
        _ substance: String, mg: Double, days: Int, perDay: Int,
    ) -> [DoseEntry] {
        var entries: [DoseEntry] = []
        for d in 0 ..< days {
            let daysBack = Double(days - 1 - d)
            for k in 0 ..< perDay {
                let hourInDay = Double(k) * (24.0 / Double(perDay))
                let ts = now.addingTimeInterval(-daysBack * 86_400 - (24 - hourInDay) * 3_600)
                entries.append(DoseEntry(substance: substance, amount: mg, unit: "mg", route: .oral, timestamp: ts))
            }
        }
        return entries
    }

    // MARK: - Dose-dependence end-to-end

    @Test
    func `Higher daily caffeine builds a larger adenosine right-shift than a lower dose`() throws {
        let high = ToleranceStore.simulate(
            entries: Self.dailyDoses("Caffeine", mg: 200, days: 10), now: Self.now, weightKg: 70, resolve: Self.resolve,
        )
        let low = ToleranceStore.simulate(
            entries: Self.dailyDoses("Caffeine", mg: 50, days: 10), now: Self.now, weightKg: 70, resolve: Self.resolve,
        )
        let highA2A = try #require(high[.adenosine])
        let lowA2A = try #require(low[.adenosine])

        #expect(highA2A.receptorClass == .adenosine)
        #expect(highA2A.shiftFactor > lowA2A.shiftFactor) // the flaw closed: dose changes tolerance
        #expect(highA2A.shiftFactor > 1) // a real right-shift built
        #expect(highA2A.responseFraction > 0 && highA2A.responseFraction < 1)
    }

    // MARK: - Stimulant: acute tachyphylaxis without a deep shift, end-to-end

    @Test
    func `Therapeutic amphetamine: acute layer engaged, deep layer stays off`() throws {
        // Recent last dose (1 h ago) so the acute layer is engaged at `now`.
        let states = ToleranceStore.simulate(
            entries: Self.dailyDoses("Amphetamine", mg: 10, days: 7, lastDoseHoursAgo: 1),
            now: Self.now, weightKg: 70, resolve: Self.resolve,
        )
        let dat = try #require(states[.catecholamineStimulant])
        #expect(dat.receptorClass == .catecholamineStimulant)
        #expect(dat.sAcute > 0) // a recent dose engages the within-session acute layer
        #expect(dat.sDeep < 0.05) // therapeutic dosing never engages the gated deep layer
        #expect(dat.shiftFactor >= 1)
        #expect(dat.confidence <= .medium) // class-default kinetics cap confidence
    }

    @Test
    func `Heavy clustered stimulant dosing engages the deep layer; occasional dosing does not`() throws {
        // Same substance, different *pattern*: heavy sustained escalation well above the heavy ceiling
        // (Amphetamine's heavy dose is ~50–75 mg, so 250 mg ×4/day is escalation factor ≳ 3–5, opening
        // the dose-relative deep gate) vs a light occasional dose that never escalates.
        let heavy = ToleranceStore.simulate(
            entries: Self.clusteredDoses("Amphetamine", mg: 250, days: 30, perDay: 4),
            now: Self.now, weightKg: 70, resolve: Self.resolve,
        )
        // Occasional: a single 10 mg dose every 4 days — well below the heavy ceiling, so the
        // dose-relative escalation gate stays closed regardless of frequency.
        let occasionalEntries: [DoseEntry] = (0 ..< 8).map { index in
            DoseEntry(
                substance: "Amphetamine", amount: 10, unit: "mg", route: .oral,
                timestamp: Self.now.addingTimeInterval(-Double(index) * 4 * 86_400 - 86_400),
            )
        }
        let occasional = ToleranceStore.simulate(
            entries: occasionalEntries, now: Self.now, weightKg: 70, resolve: Self.resolve,
        )
        let heavyDat = try #require(heavy[.catecholamineStimulant])
        let occasionalDat = try #require(occasional[.catecholamineStimulant])

        #expect(heavyDat.sDeep > 0) // escalation crosses the gate threshold → deep layer entrenches
        #expect(heavyDat.sDeep > occasionalDat.sDeep)
        #expect(occasionalDat.sDeep < 0.05) // occasional dosing keeps the gate closed
        #expect(heavyDat.shiftFactor > occasionalDat.shiftFactor) // heavier pattern → larger total shift
    }

    // MARK: - Class-default Vd fallback

    @Test
    func `Classes with a representative carry a positive class-default Vd`() {
        let classesWithRepresentative: Set<ReceptorClasses.ReceptorClass> = [
            .psychedelic5HT2A, .muOpioid, .catecholamineStimulant,
            .serotonergicReleaser, .gaba, .alpha2Delta,
            .nmdaAntagonist, .cannabinoidCB1,
        ]
        for receptorClass in ReceptorClasses.ReceptorClass.allCases {
            let vd = ReceptorClasses.parameters(for: receptorClass).classDefaultVdLPerKg
            if classesWithRepresentative.contains(receptorClass) {
                #expect(vd != nil && vd! > 0, "\(receptorClass) should have a sourced Vd")
            } else {
                #expect(vd == nil, "\(receptorClass) has no representative — Vd should be nil")
            }
        }
    }

    @Test
    func `LSD resolves a usable Vd so occupancy is computable`() throws {
        // The flagship evidence run left LSD without a Vd; the bundled DB supplies one from another
        // graded source, and failing that the class-default fallback would (flagged unverified). Either
        // way the engine gets a positive Vd to work from.
        let p = try #require(Self.resolve("Lysergic Acid Diethylamide"))
        #expect((p.vdLPerKg ?? 0) > 0)
    }

    @Test
    func `A substance with a graded Vd is unaffected by the fallback`() throws {
        let p = try #require(Self.resolve("Caffeine"))
        #expect(p.vdConfidence == .high) // still its real graded Vd, not the class default
    }

    // MARK: - Empty / no-data

    @Test
    func `Empty log yields no tolerance state`() {
        let states = ToleranceStore.simulate(entries: [], now: Self.now, weightKg: 70, resolve: Self.resolve)
        #expect(states.isEmpty)
    }

    @Test
    func `Doses outside the lookback window are ignored`() {
        let old = [DoseEntry(
            substance: "Caffeine", amount: 200, unit: "mg", route: .oral,
            timestamp: Self.now.addingTimeInterval(-1_000 * 86_400),
        )]
        let states = ToleranceStore.simulate(entries: old, now: Self.now, weightKg: 70, resolve: Self.resolve)
        #expect(states.isEmpty)
    }
}
