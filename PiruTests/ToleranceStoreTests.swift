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

    // MARK: - Dose-dependence end-to-end

    @Test
    func `Higher daily caffeine builds more adenosine tolerance than a lower dose`() throws {
        let high = ToleranceStore.simulate(
            entries: Self.dailyDoses("Caffeine", mg: 200, days: 10), now: Self.now, weightKg: 70, resolve: Self.resolve,
        )
        let low = ToleranceStore.simulate(
            entries: Self.dailyDoses("Caffeine", mg: 50, days: 10), now: Self.now, weightKg: 70, resolve: Self.resolve,
        )
        let highA2A = try #require(high["Adenosine A2A"])
        let lowA2A = try #require(low["Adenosine A2A"])

        #expect(highA2A.receptorClass == .adenosine)
        #expect(highA2A.availability < lowA2A.availability) // the flaw closed: dose changes tolerance
        #expect(highA2A.availability > 0 && highA2A.availability < 1)
    }

    // MARK: - Stimulant: tachyphylaxis without allostatic tolerance, end-to-end

    @Test
    func `Therapeutic amphetamine: acute pool depleted near a dose, slow axis stays naïve`() throws {
        // Recent last dose (1 h ago) so the acute pool is depleted at `now`.
        let states = ToleranceStore.simulate(
            entries: Self.dailyDoses("Amphetamine", mg: 10, days: 7, lastDoseHoursAgo: 1),
            now: Self.now, weightKg: 70, resolve: Self.resolve,
        )
        let dat = try #require(states["DAT"])
        #expect(dat.receptorClass == .catecholamineStimulant)
        #expect(dat.availability > 0.9) // no allostatic tolerance from therapeutic dosing
        #expect(dat.acute < dat.availability) // acute pool is the moving axis
        #expect(dat.load >= 0 && dat.load <= 1) // bounded recovery-state indicator
        #expect(dat.confidence <= .medium) // class-default kinetics cap confidence
    }

    // MARK: - Class-default Vd fallback

    @Test
    func `Every receptor class exposes a positive class-default Vd for the fallback`() {
        for receptorClass in ReceptorClasses.ReceptorClass.allCases {
            #expect(ReceptorClasses.parameters(for: receptorClass).classDefaultVdLPerKg > 0)
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
