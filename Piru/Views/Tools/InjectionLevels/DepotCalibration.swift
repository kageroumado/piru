import Foundation

/// Pins the depot model to a user's own lab results
/// (Specs/injection-levels-tool.md §3). Pure math, fully testable against the
/// prototype's known-good outputs.
///
/// Two tiers, chosen by how many measurements the user has:
///
/// - **Amplitude-only** (1 measurement, or rate-fit disabled): the population
///   parameters give the curve *shape*; the measurement scales its *y-axis*.
///   Individual variation in `d` (bioavailability × volume of distribution) is the
///   dominant between-person difference, so amplitude alone captures most of the
///   personalization from a single point.
/// - **Rate-fit** (≥2 measurements): also fits `k1`, the slow terminal
///   depot-release rate, within `[0.5, 2]×` its population value. One point can
///   only move the y-axis; two or more constrain the curve's *shape* in time —
///   which is what an amplitude-only fit structurally cannot do (the Elysia
///   validation: amplitude-only projected ~84 vs an actual 190 because the rise
///   between the two draws was steeper than the population shape). k2/k3 stay put
///   so the fitted k1 never crosses them.
enum DepotCalibration {
    struct Result: Equatable, Sendable {
        /// The fitted amplitude `d_cal` (weighted least-squares at the fitted k1).
        let calibratedAmplitude: Double
        /// `d_cal / d_pop` — how far the user sits from the population amplitude.
        let scale: Double
        /// The fitted `k1` multiplier (1.0 for an amplitude-only fit); the curve's
        /// terminal rate ran this much faster (>1) or slower (<1) than the population.
        let k1Scale: Double
        /// RMS of the calibration residuals in canonical units, or `nil` with fewer
        /// than two included measurements (a single point fits exactly).
        let residualRMS: Double?
        /// How many measurements the fit used.
        let usedCount: Int
        /// Whether the fit moved `k1` (a rate-fit ran), not just amplitude.
        var didFitRate: Bool {
            k1Scale != 1.0
        }
    }

    /// One measurement the fit consumes: draw time and observed level (canonical unit).
    struct Measurement: Equatable, Sendable {
        let date: Date
        let value: Double
    }

    /// The `k1` search bounds for the rate-fit — matches the invariant documented on
    /// ``PKModel/depotConcentration(doseMg:at:parameters:)``.
    static let k1ScaleRange: ClosedRange<Double> = 0.5 ... 2.0

    /// Calibrate the depot model to the user's measurements. With one measurement
    /// (or `fitRate` off) this is amplitude-only; with ≥2 it also fits `k1`. Returns
    /// `nil` when no measurement lands on a nonzero predicted level (nothing to fit).
    static func calibrate(
        population p: PKModel.DepotParameters,
        injections: [(date: Date, doseMg: Double)],
        measurements: [Measurement],
        fitRate: Bool = true,
    ) -> Result? {
        guard p.d > 0 else { return nil }
        let usable = measurements.filter { m in
            PKModel.depotConcentrationMultiDose(
                injections: injections, at: m.date, parameters: p.withAmplitude(1),
            ) > 0
        }
        guard !usable.isEmpty else { return nil }

        // Rate-fit only earns its second parameter with two+ points to constrain it.
        guard fitRate, usable.count >= 2 else {
            return amplitudeFit(population: p, injections: injections, measurements: usable, k1Scale: 1.0)?.result
        }

        // Golden-section search over k1Scale for the minimum residual sum of squares,
        // amplitude re-fitted linearly at each candidate. Unimodal enough in practice;
        // the bracket keeps k1 within its documented [0.5, 2]× envelope.
        let sse: (Double) -> Double = { s in
            let fit = amplitudeFit(population: p, injections: injections, measurements: usable, k1Scale: s)
            return fit?.sumOfSquares ?? .greatestFiniteMagnitude
        }
        let bestScale = goldenSectionMinimum(in: k1ScaleRange, evaluating: sse)
        guard let fit = amplitudeFit(population: p, injections: injections, measurements: usable, k1Scale: bestScale) else {
            return amplitudeFit(population: p, injections: injections, measurements: usable, k1Scale: 1.0).map(\.result)
        }
        return fit.result
    }

    /// The weighted least-squares amplitude at a fixed `k1Scale`, with its residuals.
    /// `d_cal = Σⱼ(E₂ⱼ·pⱼ) / Σⱼ(pⱼ²)` where `pⱼ` is the unit-amplitude prediction at
    /// the scaled `k1`; with one measurement this is the ratio `E₂_obs / p_obs`.
    private static func amplitudeFit(
        population p: PKModel.DepotParameters,
        injections: [(date: Date, doseMg: Double)],
        measurements: [Measurement],
        k1Scale: Double,
    ) -> Fit? {
        let unit = p.withK1Scale(k1Scale).withAmplitude(1)
        var num = 0.0, den = 0.0
        var pairs: [(observed: Double, unitPredicted: Double)] = []
        for m in measurements {
            let predicted = PKModel.depotConcentrationMultiDose(injections: injections, at: m.date, parameters: unit)
            guard predicted > 0 else { continue }
            num += m.value * predicted
            den += predicted * predicted
            pairs.append((m.value, predicted))
        }
        guard den > 0, !pairs.isEmpty else { return nil }
        let dCal = num / den
        let ss = pairs.reduce(0.0) { acc, pair in
            let r = pair.observed - dCal * pair.unitPredicted
            return acc + r * r
        }
        let rms = pairs.count >= 2 ? (ss / Double(pairs.count)).squareRoot() : nil
        return Fit(
            result: Result(
                calibratedAmplitude: dCal, scale: dCal / p.d, k1Scale: k1Scale,
                residualRMS: rms, usedCount: pairs.count,
            ),
            sumOfSquares: ss,
        )
    }

    private struct Fit {
        let result: Result
        let sumOfSquares: Double
    }

    /// Golden-section minimum of a unimodal-enough function on a closed interval.
    /// ~40 evaluations to ≈1e-4 in the scale — cheap for the handful of measurements
    /// a user has, and derivative-free (the objective is a superposition sum).
    private static func goldenSectionMinimum(
        in range: ClosedRange<Double>, evaluating f: (Double) -> Double,
    ) -> Double {
        let phi = (sqrt(5.0) - 1) / 2 // 0.618…
        var a = range.lowerBound, b = range.upperBound
        var c = b - phi * (b - a)
        var d = a + phi * (b - a)
        var fc = f(c), fd = f(d)
        for _ in 0 ..< 60 {
            if fc < fd { b = d; d = c; fd = fc; c = b - phi * (b - a); fc = f(c) }
            else { a = c; c = d; fc = fd; d = a + phi * (b - a); fd = f(d) }
            if b - a < 1e-6 { break }
        }
        return (a + b) / 2
    }

    /// Whether a newly observed level departs from the calibrated prediction by more
    /// than 2·σ_residual — a formulation change, injection-depth variance, or an
    /// assay switch. Only meaningful once the calibration set has ≥ 3 points
    /// (`residualRMS` from at least a 3-measurement fit); otherwise never flags.
    static func isOutlier(
        observed: Double,
        predicted: Double,
        residualRMS: Double?,
        calibrationCount: Int,
    ) -> Bool {
        guard calibrationCount >= 3, let rms = residualRMS, rms > 0 else { return false }
        return abs(observed - predicted) > 2 * rms
    }
}
