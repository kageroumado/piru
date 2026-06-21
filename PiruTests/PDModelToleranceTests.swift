import Foundation
import Testing
@testable import Piru

/// Pure-model gate for the tolerance engine (Stage 1 of the pharmacology axis). These exercise
/// ``PDModel`` in isolation — no store, no DB — so the dynamics are proven before any wiring:
/// clustered dosing suppresses availability while spacing recovers it (the psychedelic tachyphylaxis
/// shape), and the acute pool moves within a session while the slow allostatic axis does not (the
/// stimulant "tachyphylaxis-only, no allostatic tolerance" requirement).
@Suite("PDModel tolerance dynamics")
struct PDModelToleranceTests {
    /// A uniformly-sampled occupancy series: `days` days at `dtMinutes`, each dosing day a flat
    /// `peak`-occupancy pulse for the first `activeHours`, then zero; dosing every `everyDays` days.
    static func occupancySeries(
        days: Int, dtMinutes: Double, peak: Double, activeHours: Double, everyDays: Int,
    ) -> [Double] {
        let stepsPerDay = Int((24 * 60) / dtMinutes)
        let activeSteps = Int((activeHours * 60) / dtMinutes)
        var series: [Double] = []
        series.reserveCapacity(days * stepsPerDay)
        for day in 0 ..< days {
            let dosing = day % everyDays == 0
            for step in 0 ..< stepsPerDay {
                series.append(dosing && step < activeSteps ? peak : 0)
            }
        }
        return series
    }

    // MARK: - stepAvailability

    @Test
    func `Recovers toward 1 with no occupancy`() {
        let a = PDModel.stepAvailability(availability: 0.5, occupancy: 0, dtMinutes: 1_440, kappa: 0.002, tauMinutes: 1_440)
        #expect(a > 0.5)
        #expect(a < 1)
    }

    @Test
    func `Occupancy depresses availability`() {
        let a = PDModel.stepAvailability(availability: 1, occupancy: 0.5, dtMinutes: 600, kappa: 0.003, tauMinutes: 5_040)
        #expect(a < 1)
        #expect(a > 0)
    }

    @Test
    func `Never falls below the occupancy-pinned steady state`() {
        // dA/dt = a − (a+b)A → A_ss = a/(a+b); a single step can't undershoot it.
        let kappa = 0.01, occ = 1.0, tau = 5_040.0
        let recovery = 1.0 / tau
        let aSS = recovery / (recovery + kappa * occ)
        let a = PDModel.stepAvailability(availability: 1, occupancy: occ, dtMinutes: 1_000_000, kappa: kappa, tauMinutes: tau)
        #expect(a >= aSS - 1e-9)
        #expect(abs(a - aSS) < 1e-6) // a huge step converges to steady state
    }

    @Test
    func `Guards: non-positive dt or tau is a no-op`() {
        #expect(PDModel.stepAvailability(availability: 0.7, occupancy: 1, dtMinutes: 0, kappa: 0.01, tauMinutes: 100) == 0.7)
        #expect(PDModel.stepAvailability(availability: 0.7, occupancy: 1, dtMinutes: 30, kappa: 0.01, tauMinutes: 0) == 0.7)
    }

    // MARK: - Gate 1: psychedelic daily-vs-weekly tachyphylaxis

    @Test
    func `Daily psychedelic dosing suppresses 5-HT2A availability; weekly recovers between doses`() throws {
        let dt = 30.0
        let p = ReceptorClasses.parameters(for: .psychedelic5HT2A)
        // LSD-like sub-saturation occupancy (~0.3) over a ~10 h active window.
        let daily = Self.occupancySeries(days: 14, dtMinutes: dt, peak: 0.3, activeHours: 10, everyDays: 1)
        let weekly = Self.occupancySeries(days: 14, dtMinutes: dt, peak: 0.3, activeHours: 10, everyDays: 7)

        let dailyTrace = PDModel.availabilityTrace(occupancy: daily, dtMinutes: dt, kappa: p.kappaSlow, tauMinutes: p.tauSlowMinutes)
        let weeklyTrace = PDModel.availabilityTrace(occupancy: weekly, dtMinutes: dt, kappa: p.kappaSlow, tauMinutes: p.tauSlowMinutes)

        let dailyEnd = try #require(dailyTrace.last)
        let weeklyEnd = try #require(weeklyTrace.last)

        #expect(dailyEnd < 0.6) // clustered dosing leaves it substantially tolerant
        #expect(weeklyEnd > 0.85) // a week is enough to recover toward naïve
        #expect(dailyEnd < weeklyEnd)

        // Accumulation: availability after one day is higher than after two weeks of daily dosing.
        let stepsPerDay = Int((24 * 60) / dt)
        #expect(dailyTrace[stepsPerDay] > dailyEnd)
    }

    // MARK: - Gate 2: stimulant tachyphylaxis-only, no allostatic tolerance

    @Test
    func `Therapeutic stimulant: acute pool depletes & recovers overnight, slow axis stays naïve`() throws {
        let dt = 30.0
        let p = ReceptorClasses.parameters(for: .catecholamineStimulant)
        // Therapeutic stimulant saturates the transporter (~0.9) for a ~10 h day, dosed daily.
        let occ = Self.occupancySeries(days: 7, dtMinutes: dt, peak: 0.9, activeHours: 10, everyDays: 1)

        let acute = PDModel.availabilityTrace(occupancy: occ, dtMinutes: dt, kappa: p.kappaAcute, tauMinutes: p.tauAcuteMinutes)
        let slow = PDModel.availabilityTrace(occupancy: occ, dtMinutes: dt, kappa: p.kappaSlow, tauMinutes: p.tauSlowMinutes)

        let activeSteps = Int((10 * 60) / dt)
        let stepsPerDay = Int((24 * 60) / dt)

        // Acute tachyphylaxis: the pool is depleted by the end of the first active window…
        #expect(acute[activeSteps] < 0.3)
        // …and recovers overnight before the next day's dose.
        #expect(acute[stepsPerDay] > 0.55)
        // The slow allostatic axis barely moves → no allostatic tolerance from therapeutic dosing.
        #expect(try #require(slow.last) > 0.95)
    }

    @Test
    func `Allostatic load is dose/frequency-dependent and bounded`() {
        let dt = 30.0
        let p = ReceptorClasses.parameters(for: .catecholamineStimulant)
        func loadEnd(_ occ: [Double]) -> Double {
            var load = 0.0
            for o in occ {
                load = PDModel.stepLoad(load: load, occupancy: o, dtMinutes: dt, tauMinutes: p.tauLoadMinutes, gain: p.loadGain)
            }
            return load
        }
        let chronic = loadEnd(Self.occupancySeries(days: 30, dtMinutes: dt, peak: 0.9, activeHours: 12, everyDays: 1))
        let occasional = loadEnd(Self.occupancySeries(days: 30, dtMinutes: dt, peak: 0.9, activeHours: 12, everyDays: 7))

        #expect(chronic > occasional)
        #expect(chronic > occasional * 2) // meaningfully more, not marginal
        #expect(occasional < 0.1) // occasional use barely accrues against a months-τ integrator
        #expect(chronic <= 1.0) // bounded recovery-state indicator
    }

    // MARK: - combinedOccupancy / stepLoad units

    @Test
    func `Combined occupancy is the probabilistic union`() {
        #expect(PDModel.combinedOccupancy([]) == 0)
        #expect(abs(PDModel.combinedOccupancy([0.5]) - 0.5) < 1e-9)
        #expect(abs(PDModel.combinedOccupancy([0.5, 0.5]) - 0.75) < 1e-9)
        // Order-independent and clamped.
        #expect(abs(PDModel.combinedOccupancy([0.5, 0.5]) - PDModel.combinedOccupancy([0.5, 0.5])) < 1e-9)
        #expect(PDModel.combinedOccupancy([1.0, 0.5]) == 1.0)
        #expect(PDModel.combinedOccupancy([2.0]) == 1.0) // over-unity input clamped
    }

    @Test
    func `Load relaxes toward occupancy and decays to zero`() {
        // Rises toward occupancy.
        let up = PDModel.stepLoad(load: 0, occupancy: 0.8, dtMinutes: 100_000, tauMinutes: 1_000, gain: 1)
        #expect(abs(up - 0.8) < 1e-3)
        // Decays toward zero with no occupancy.
        let down = PDModel.stepLoad(load: 0.8, occupancy: 0, dtMinutes: 100_000, tauMinutes: 1_000, gain: 1)
        #expect(down < 1e-3)
    }
}
