import Foundation

enum PKModel {
    /// Normalized one-compartment oral PK concentration at time `t` (minutes).
    /// Returns raw (unnormalized) value — divide by `cmax` to get [0, 1] range.
    nonisolated static func concentration(at minutes: Double, ke: Double, ka: Double) -> Double {
        guard minutes >= 0, ka > 0, ke > 0 else { return 0 }

        // Handle ka ≈ ke singularity (L'Hopital limit)
        if abs(ka - ke) < 1e-10 {
            return ke * minutes * exp(-ke * minutes)
        }

        let raw = (ka / (ka - ke)) * (exp(-ke * minutes) - exp(-ka * minutes))
        return max(0, raw)
    }

    /// Time of peak concentration (Tmax) in minutes.
    nonisolated static func tmax(ke: Double, ka: Double) -> Double {
        guard ka > ke, ka > 0, ke > 0 else { return 0 }
        if abs(ka - ke) < 1e-10 { return 1.0 / ke }
        return log(ka / ke) / (ka - ke)
    }

    /// Peak concentration value (unnormalized).
    nonisolated static func cmax(ke: Double, ka: Double) -> Double {
        concentration(at: tmax(ke: ke, ka: ka), ke: ke, ka: ka)
    }

    /// Derive elimination rate constant from half-life in minutes.
    nonisolated static func ke(fromHalfLifeMinutes hl: Double) -> Double {
        guard hl > 0 else { return 0 }
        return log(2) / hl
    }

    /// Estimate absorption rate constant (ka) from time-to-peak and ke using Newton's method.
    /// Falls back to `defaultKa` if convergence fails.
    nonisolated static func estimateKa(timeToPeak: Double, ke: Double) -> Double {
        guard timeToPeak > 0, ke > 0 else { return defaultKa(ke: ke) }

        // Tmax = ln(ka/ke) / (ka - ke), solve for ka
        var ka = 4 * ke
        for _ in 0 ..< 50 {
            guard ka > ke else { return defaultKa(ke: ke) }
            let f = log(ka / ke) / (ka - ke) - timeToPeak
            let denom = (ka - ke) * (ka - ke)
            let df = ((ka - ke) / ka - log(ka / ke)) / denom
            guard abs(df) > 1e-15 else { break }
            let kaNew = ka - f / df
            if abs(kaNew - ka) < 1e-6 { ka = max(ke * 1.01, kaNew); break }
            ka = max(ke * 1.01, kaNew)
        }
        return ka
    }

    /// Default ka when no duration data available: 4x the elimination rate.
    nonisolated static func defaultKa(ke: Double) -> Double {
        4 * ke
    }

    /// Fraction of original dose still in the body (absorption site + central compartment) at time `t`.
    /// Unlike `concentration(at:)` which tracks plasma levels only, this accounts for drug still being
    /// absorbed from the gut — giving an accurate "% eliminated" even before peak concentration.
    nonisolated static func fractionRemainingInBody(at minutes: Double, ke: Double, ka: Double) -> Double {
        guard minutes >= 0, ka > 0, ke > 0 else { return 1 }

        // Handle ka ≈ ke singularity: limit is (1 + ke·t)·e^(-ke·t)
        if abs(ka - ke) < 1e-10 {
            return (1 + ke * minutes) * exp(-ke * minutes)
        }

        // F(t) = (ka·e^(-ke·t) - ke·e^(-ka·t)) / (ka - ke)
        let result = (ka * exp(-ke * minutes) - ke * exp(-ka * minutes)) / (ka - ke)
        return min(1, max(0, result))
    }

    /// Time (in minutes) at which concentration drops to `fraction` of Cmax (on the descending side).
    /// Useful for determining chart x-axis range.
    nonisolated static func timeToFraction(_ fraction: Double, ke: Double, ka: Double, maxMinutes: Double = 50_000) -> Double {
        let peak = cmax(ke: ke, ka: ka)
        guard peak > 0 else { return 0 }
        let target = peak * fraction
        let peakTime = tmax(ke: ke, ka: ka)

        // Binary search on the descending portion
        var lo = peakTime
        var hi = maxMinutes
        for _ in 0 ..< 100 {
            let mid = (lo + hi) / 2
            if concentration(at: mid, ke: ke, ka: ka) > target {
                lo = mid
            } else {
                hi = mid
            }
            if hi - lo < 0.1 { break }
        }
        return hi
    }
}
