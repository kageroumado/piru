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

    // MARK: - Absolute exposure (Foundation A)

    /// Absolute plasma concentration on a **mass** basis at time `t` (minutes), one-compartment oral.
    ///
    /// This is the multiplicative re-base of ``concentration(at:ke:ka:)``: that function returns the
    /// pure one-compartment shape `(ka/(ka−ke))·(e^{−ke·t} − e^{−ka·t})`, and absolute concentration
    /// is simply `(F · Dose / Vd)` times it, where `Vd = vdPerKg · weightKg`. Unlike the normalized
    /// curve used for the visual timeline, this preserves dose magnitude — so 5 mg and 50 mg of the
    /// same drug now yield *different* curves, which is what makes dose-dependent tolerance expressible.
    ///
    /// - Parameters:
    ///   - dose: administered amount in **milligrams** (convert the logged dose unit before calling).
    ///   - bioavailability: fraction reaching systemic circulation, `F ∈ (0, 1]`.
    ///   - vdPerKg: volume of distribution per kg body weight, in **L/kg**.
    ///   - weightKg: body weight in **kg** (the keystone input; caller supplies the 60 kg default).
    ///   - ke: elimination rate constant (per minute).
    ///   - ka: absorption rate constant (per minute).
    ///   - minutes: time since administration.
    /// - Returns: concentration in **mg/L** (≡ µg/mL). For ethanol dosed in mg with `vdPerKg ≈ 0.6`
    ///   this is the Widmark blood-alcohol concentration in mg/L (÷1000 for g/L, ×100 for g/dL).
    nonisolated static func concentrationAbsolute(
        dose: Double,
        bioavailability: Double,
        vdPerKg: Double,
        weightKg: Double,
        ke: Double,
        ka: Double,
        at minutes: Double,
    ) -> Double {
        guard dose >= 0, bioavailability > 0, vdPerKg > 0, weightKg > 0 else { return 0 }
        let vd = vdPerKg * weightKg
        return (bioavailability * dose / vd) * concentration(at: minutes, ke: ke, ka: ka)
    }

    /// Absolute plasma concentration on a **molar** basis at time `t` (minutes), one-compartment oral.
    ///
    /// Identical to ``concentrationAbsolute(dose:bioavailability:vdPerKg:weightKg:ke:ka:at:)`` divided
    /// by molar mass, giving the unit that receptor occupancy needs (compares directly to a Kᵢ/EC₅₀).
    /// This returns *total* plasma concentration; the unbound fraction `fu` is applied later, in the
    /// occupancy step, so it stays out of here (default `fu = 1`).
    ///
    /// - Parameters:
    ///   - molarMassGramsPerMole: molar mass in **g/mol** (already decoded on `Substance`).
    ///   - (others): see ``concentrationAbsolute(dose:bioavailability:vdPerKg:weightKg:ke:ka:at:)``.
    /// - Returns: concentration in **mol/L**. `C_molar = C_abs[mg/L] / 1000 / molarMass[g/mol]`.
    ///   ⚠️ The substance DB stores Kᵢ/EC₅₀ in **nanomolar**, so multiply this by `1e9` before passing
    ///   it to ``occupancy(concentration:halfMax:hillCoefficient:)`` against an nM half-max (which is
    ///   exactly what `PharmacologyParameters.peakPrimaryOccupancy` does). Mixing mol/L with an nM
    ///   half-max silently understates occupancy by 10⁹×.
    nonisolated static func concentrationMolar(
        dose: Double,
        bioavailability: Double,
        vdPerKg: Double,
        weightKg: Double,
        molarMassGramsPerMole: Double,
        ke: Double,
        ka: Double,
        at minutes: Double,
    ) -> Double {
        guard molarMassGramsPerMole > 0 else { return 0 }
        let massPerLiter = concentrationAbsolute(
            dose: dose,
            bioavailability: bioavailability,
            vdPerKg: vdPerKg,
            weightKg: weightKg,
            ke: ke,
            ka: ka,
            at: minutes,
        )
        return massPerLiter / 1_000.0 / molarMassGramsPerMole
    }

    // MARK: - Receptor occupancy / engagement (Foundation A → PD bridge)

    /// Fractional receptor occupancy (or transporter engagement) from a Hill/Langmuir binding
    /// isotherm: `O = C^h / (K^h + C^h)`, returned in `[0, 1]`.
    ///
    /// One form serves all three mechanism branches the pharmacology axis distinguishes — only the
    /// meaning of the half-saturation constant `K` changes:
    /// - **agonist / antagonist / PAM:** `K = Kᵢ` (binding affinity).
    /// - **releaser / substrate** (amphetamine, MDMA): `K = functional release EC₅₀` at the transporter.
    /// - **reuptake inhibitor** (methylphenidate, cocaine): `K = uptake-inhibition IC₅₀/Kᵢ`.
    ///
    /// `concentration` and `halfMax` must be in the **same unit** (it cancels — nM vs nM or mol/L vs
    /// mol/L both work). Pass the **free** (unbound) concentration: multiply total molar concentration
    /// by `fu` before calling. `hillCoefficient` defaults to 1 (simple mass action); `> 1` models
    /// positive cooperativity.
    ///
    /// This is the step that makes tolerance **dose-dependent**: its input comes from
    /// ``concentrationMolar(dose:bioavailability:vdPerKg:weightKg:molarMassGramsPerMole:ke:ka:at:)``,
    /// which is linear in dose, so at low exposure `C ≪ K` gives `O ≈ C/K → 0` (no allostatic drive)
    /// while near/above `K` it saturates. The normalized-shape model could not express this — every
    /// dose produced the same curve. Closing that is the keystone correctness requirement.
    nonisolated static func occupancy(
        concentration: Double,
        halfMax: Double,
        hillCoefficient: Double = 1,
    ) -> Double {
        guard concentration > 0, halfMax > 0, hillCoefficient > 0 else { return 0 }
        let cH = pow(concentration, hillCoefficient)
        let kH = pow(halfMax, hillCoefficient)
        return cH / (kH + cH)
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
