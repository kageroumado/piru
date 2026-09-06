import Foundation

// MARK: - Depot (oil/IM) PK — injectable hormone esters

extension PKModel {
    /// Three-compartment linear depot chain: injection depot → serum ester → serum hormone.
    ///
    /// `E₂(t) = d·k₁·k₂·[ e^{−k₁t}/((k₁−k₂)(k₁−k₃)) − e^{−k₂t}/((k₁−k₂)(k₂−k₃)) + e^{−k₃t}/((k₁−k₃)(k₂−k₃)) ]`
    ///
    /// All rates are **per day** — depot kinetics run on a days-to-weeks timescale, and the primary
    /// literature reports in days. `d` folds F/Vd into a single amplitude (population value from the
    /// ester table, then user-calibrated). Output is a serum concentration in the analyte's canonical
    /// unit (pg/mL for estradiol, ng/dL for testosterone) once `d` is set to that unit's scale.
    ///
    /// This is the exact solution of a two-stage first-order cascade feeding a first-order clearance,
    /// so it is closed-form at every point — no numerical integration. The one-compartment oral model
    /// is a special case (set k₃ to the blood-elimination rate and it reduces to a Bateman curve).
    nonisolated struct DepotParameters: Equatable, Codable, Sendable {
        /// Amplitude, output-unit per mg. Wraps F/Vd; population value from the ester table, or user-calibrated.
        let d: Double
        /// Rate constant 1, per day (the slow/terminal depot-release rate for most esters).
        let k1: Double
        /// Rate constant 2, per day.
        let k2: Double
        /// Rate constant 3, per day.
        let k3: Double

        init(d: Double, k1: Double, k2: Double, k3: Double) {
            self.d = d
            self.k1 = k1
            self.k2 = k2
            self.k3 = k3
        }

        /// The same parameters with a replaced amplitude — the amplitude-calibration
        /// output (shape held, y-axis scaled).
        func withAmplitude(_ newD: Double) -> DepotParameters {
            DepotParameters(d: newD, k1: k1, k2: k2, k3: k3)
        }

        /// The same parameters with `k1` (the slow terminal depot-release rate)
        /// scaled by `s` — the rate-fit output (v2 calibration). Scaling k1 stretches
        /// or compresses the curve's rise and terminal decay in time, which is where
        /// individual depot variation (injection depth, oil vehicle, SC vs IM) lands;
        /// k2/k3 stay put so the fitted k1 never crosses them. `min(k1·s, k2, k3)`
        /// bound is enforced by the caller's `[0.5, 2]×` search range.
        func withK1Scale(_ s: Double) -> DepotParameters {
            DepotParameters(d: d, k1: k1 * s, k2: k2, k3: k3)
        }
    }

    /// Single-dose serum concentration `days` after one injection. Returns 0 for `days < 0`.
    ///
    /// The three rate constants are distinct for every population ester and stay distinct under the
    /// calibration bounds (only k₁ is fitted, within [0.5, 2]× its population value, never crossing the
    /// much larger k₂/k₃). A pair that lands within `rateEpsilon` is nudged apart rather than dividing
    /// by zero — the perturbation is far below the precision of any depot PK datum.
    nonisolated static func depotConcentration(
        doseMg: Double,
        at days: Double,
        parameters p: DepotParameters,
    ) -> Double {
        guard doseMg > 0, days >= 0, p.d > 0, p.k1 > 0, p.k2 > 0, p.k3 > 0 else { return 0 }

        let (k1, k2, k3) = separatedRates(p.k1, p.k2, p.k3)

        let t1 = exp(-k1 * days) / ((k1 - k2) * (k1 - k3))
        let t2 = exp(-k2 * days) / ((k1 - k2) * (k2 - k3))
        let t3 = exp(-k3 * days) / ((k1 - k3) * (k2 - k3))

        let value = doseMg * p.d * k1 * k2 * (t1 - t2 + t3)
        return max(0, value)
    }

    /// Multi-dose superposition: total serum concentration at `date`, summing each prior injection's
    /// single-dose contribution. Injections at or after `date` contribute nothing.
    nonisolated static func depotConcentrationMultiDose(
        injections: [(date: Date, doseMg: Double)],
        at date: Date,
        parameters p: DepotParameters,
    ) -> Double {
        var total = 0.0
        for injection in injections {
            let days = date.timeIntervalSince(injection.date) / secondsPerDay
            guard days >= 0 else { continue }
            total += depotConcentration(doseMg: injection.doseMg, at: days, parameters: p)
        }
        return total
    }

    /// The superposition curve sampled at `pointCount` evenly spaced points across `dateRange`.
    nonisolated static func depotCurve(
        injections: [(date: Date, doseMg: Double)],
        over dateRange: ClosedRange<Date>,
        parameters p: DepotParameters,
        pointCount: Int = 600,
    ) -> [(date: Date, pgPerML: Double)] {
        guard pointCount > 1 else {
            let single = depotConcentrationMultiDose(injections: injections, at: dateRange.lowerBound, parameters: p)
            return [(dateRange.lowerBound, single)]
        }
        let start = dateRange.lowerBound.timeIntervalSinceReferenceDate
        let end = dateRange.upperBound.timeIntervalSinceReferenceDate
        let span = end - start
        var out: [(date: Date, pgPerML: Double)] = []
        out.reserveCapacity(pointCount)
        for i in 0 ..< pointCount {
            let frac = Double(i) / Double(pointCount - 1)
            let date = Date(timeIntervalSinceReferenceDate: start + span * frac)
            let value = depotConcentrationMultiDose(injections: injections, at: date, parameters: p)
            out.append((date, value))
        }
        return out
    }

    // MARK: - Internals

    nonisolated static let secondsPerDay = 86_400.0

    /// Minimum separation between rate constants below which the closed form loses precision to a
    /// vanishing denominator. Rates are per-day; 1e-6/day is ~0.05 s of half-life difference — far
    /// finer than any measured depot rate, so nudging apart at this scale is invisible in the curve.
    private nonisolated static let rateEpsilon = 1e-6

    /// Return the three rates guaranteed pairwise-separated by at least `rateEpsilon`, nudging any
    /// coincident pair upward. Preserves ordering-independent behavior of the symmetric closed form.
    private nonisolated static func separatedRates(_ a: Double, _ b: Double, _ c: Double) -> (Double, Double, Double) {
        let k1 = a
        var k2 = b
        var k3 = c
        if abs(k1 - k2) < rateEpsilon { k2 += rateEpsilon }
        if abs(k1 - k3) < rateEpsilon { k3 += 2 * rateEpsilon }
        if abs(k2 - k3) < rateEpsilon { k3 += 2 * rateEpsilon }
        return (k1, k2, k3)
    }
}
