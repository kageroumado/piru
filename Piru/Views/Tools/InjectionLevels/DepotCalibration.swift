import Foundation

/// Pins the depot model's amplitude to a user's own lab results
/// (Specs/injection-levels-tool.md §3). Pure math, fully testable against the
/// prototype's known-good outputs.
///
/// v1 is **amplitude-only**: the population parameters give the curve *shape*; the
/// user's measurements scale its *y-axis*. Individual variation in `d`
/// (bioavailability × volume of distribution) is the dominant source of
/// between-person differences, so scaling amplitude alone captures most of the
/// personalization value. Rate-fitting (v2) is deliberately out of scope here.
enum DepotCalibration {
    struct Result: Equatable, Sendable {
        /// The fitted amplitude `d_cal` (weighted least-squares).
        let calibratedAmplitude: Double
        /// `d_cal / d_pop` — how far the user sits from the population amplitude.
        let scale: Double
        /// RMS of the calibration residuals in canonical units, or `nil` with fewer
        /// than two included measurements (a single point fits exactly).
        let residualRMS: Double?
        /// How many measurements the fit used.
        let usedCount: Int
    }

    /// One measurement the fit consumes: draw time and observed level (canonical unit).
    struct Measurement: Equatable, Sendable {
        let date: Date
        let value: Double
    }

    /// Amplitude-only least-squares calibration. Returns `nil` when no measurement
    /// lands on a nonzero predicted level (nothing to scale to).
    ///
    /// For each measurement the predicted level at **unit amplitude** is
    /// `pⱼ = Σᵢ depotConcentration(doseᵢ, dateⱼ − dateᵢ, d = 1)`. The weighted
    /// least-squares amplitude is `d_cal = Σⱼ(E₂ⱼ · pⱼ) / Σⱼ(pⱼ²)`; with one
    /// measurement this is the ratio `E₂_obs / p_obs`.
    static func calibrate(
        population p: PKModel.DepotParameters,
        injections: [(date: Date, doseMg: Double)],
        measurements: [Measurement],
    ) -> Result? {
        guard p.d > 0 else { return nil }
        let unit = p.withAmplitude(1)

        var num = 0.0
        var den = 0.0
        var pairs: [(observed: Double, unitPredicted: Double)] = []
        for m in measurements {
            let predicted = PKModel.depotConcentrationMultiDose(
                injections: injections, at: m.date, parameters: unit,
            )
            guard predicted > 0 else { continue }
            num += m.value * predicted
            den += predicted * predicted
            pairs.append((m.value, predicted))
        }
        guard den > 0, !pairs.isEmpty else { return nil }

        let dCal = num / den
        var residualRMS: Double?
        if pairs.count >= 2 {
            let ss = pairs.reduce(0.0) { acc, pair in
                let residual = pair.observed - dCal * pair.unitPredicted
                return acc + residual * residual
            }
            residualRMS = (ss / Double(pairs.count)).squareRoot()
        }
        return Result(
            calibratedAmplitude: dCal,
            scale: dCal / p.d,
            residualRMS: residualRMS,
            usedCount: pairs.count,
        )
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
