import Foundation

/// Curated saturable-kinetics seed for the **Ceiling-Effect** tool (pharmacology axis, Stage 6).
///
/// Most substances clear by first-order kinetics — double the dose, double the exposure — which the
/// closed-form ``PKModel/concentration(at:ke:ka:)`` Bateman path already models. A handful break that
/// rule because an enzyme runs out of capacity (Michaelis-Menten saturation), and they break it in two
/// opposite directions:
///
/// - **Saturable elimination** (ethanol, phenytoin, GHB): the *clearing* enzyme saturates, so above its
///   `Km` elimination goes zero-order and a small dose increase produces a **supralinear** jump in
///   total exposure. The dangerous ceiling — the tool draws the curve bending *up* away from the
///   proportional reference.
/// - **Saturable activation** (codeine → morphine): the *activating* enzyme saturates, so the active
///   species stops scaling with dose past the knee. The (relatively) safer ceiling — extra dose buys
///   duration and side-effects, not peak effect.
///
/// ## Faithful over comprehensive
/// Every numeric `Kinetics` row traces to resolvable human literature (see `ceiling-kinetics-evidence.json`,
/// Foundation-C gate-clean 2026-06-22). Only **ethanol** and **phenytoin** have clean human Km/Vmax and
/// ship a drawable quantitative curve. **Codeine** and **GHB** ship *qualitative* (`kinetics == nil`) —
/// a knee + direction in words, never a fabricated curve:
/// - codeine's morphine ceiling is CYP2D6 *phenotype/enzyme-quantity*-limited, **not** substrate-saturable
///   at clinical doses, so drawing a saturating activation curve would be wrong;
/// - GHB has only rat/in-vitro Km values (grade D) — the human nonlinearity is real but unquantified.
///
/// Lisdexamfetamine was **dropped** from the spec's proposed seed: its activation is rate-limited, not
/// capacity-saturated (linear through ≥250 mg), so it is not a ceiling substance.
enum SaturablePharmacology {
    /// Which enzymatic step saturates — the two attachment points of the same Michaelis-Menten term.
    enum Mechanism {
        /// The *clearing* enzyme saturates → supralinear accumulation (the warning).
        case elimination
        /// The *activating* enzyme (prodrug → active species) saturates → a ceiling on effect.
        case activation
    }

    /// Quantitative kinetics — present only when the substance has clean human Km/Vmax and the
    /// dose→exposure curve can be drawn. `nil` on a ``Profile`` means qualitative-only.
    struct Kinetics {
        /// Michaelis constant, **mg/L** (the concentration at half-maximal clearance rate).
        let kmMgPerL: Double
        /// Maximum metabolic rate, expressed in whichever convention the literature reports.
        let vmax: VmaxBasis
        /// Volume of distribution per kg, **L/kg**.
        let vdPerKg: Double
        /// Bioavailability `F ∈ (0, 1]`.
        let bioavailability: Double
        /// First-order absorption rate constant, per minute.
        let ka: Double
        /// The dose treated as "1 unit" — the smallest example dose (milligrams).
        let referenceDoseMg: Double
        /// The example doses (as multiples of the reference dose) drawn as overlaid concentration-time
        /// curves, e.g. `[1, 2, 3, 4]` for "1–4 drinks".
        let exampleDoseMultiples: [Double]
        /// How the per-curve dose labels read ("2 drinks" vs "600 mg").
        let doseLabel: DoseLabel
        /// The plotted time window (minutes) — wide enough for the largest example dose to fall back
        /// toward baseline.
        let displayWindowMinutes: Double
        /// How long to integrate when measuring total exposure (AUC) — sized to capture the slowest
        /// (highest-dose) clearance fully, so the exposure ratio isn't truncated.
        let integrationMinutes: Double
        /// Integration step (minutes); coarser for long-clearance drugs to keep the render cheap.
        let stepMinutes: Double

        /// How a curve's dose is named in the legend.
        enum DoseLabel {
            /// Whole "drinks" — `multiple` units (1 → "1 drink", 2 → "2 drinks").
            case drinks
            /// `multiple × mgPerUnit` milligrams (1 → "300 mg", 2 → "600 mg").
            case milligrams(perUnit: Double)
        }

        /// Vmax is reported two incompatible ways in the literature; both reduce to mg/L/min here.
        enum VmaxBasis {
            /// Whole-body elimination rate, **mg/min** (ethanol: 95 mg/min). Divided by Vd.
            case wholeBodyMgPerMin(Double)
            /// Weight-scaled rate, **mg/kg/day** (phenytoin: 7). Scaled by weight, per-day → per-min,
            /// then divided by Vd — the weight cancels, leaving a weight-independent mg/L/min.
            case mgPerKgPerDay(Double)

            func mgPerLPerMin(weightKg: Double, vdPerKg: Double) -> Double {
                let vd = max(vdPerKg * weightKg, .leastNonzeroMagnitude)
                switch self {
                case let .wholeBodyMgPerMin(rate):
                    return rate / vd
                case let .mgPerKgPerDay(rate):
                    return (rate * weightKg / 1_440) / vd
                }
            }
        }
    }

    /// A curated ceiling-effect profile for one substance.
    struct Profile: Identifiable {
        /// Canonical substance name, matched case-insensitively against the library / dose log.
        let substanceName: String
        /// Display name shown in the tool (may differ from the canonical name).
        let displayName: LocalizedStringResource
        let mechanism: Mechanism
        let confidence: ConfidenceTier
        /// Quantitative kinetics, or `nil` for a qualitative (knee + direction only) profile.
        let kinetics: Kinetics?
        /// One-line takeaway — the headline message.
        let headline: LocalizedStringResource
        /// Where the curve bends and why (the "knee").
        let knee: LocalizedStringResource
        /// Longer explanation / caveats.
        let detail: LocalizedStringResource
        /// Primary source, shown verbatim (regenerated from resolved PMIDs).
        let citation: String

        var id: String {
            substanceName
        }
        var isQuantitative: Bool {
            kinetics != nil
        }
    }

    // MARK: - The seed

    static let profiles: [Profile] = [ethanol, phenytoin, codeine, ghb]

    /// Case-insensitive lookup by substance name (canonical or display alias handled by the caller).
    static func profile(forSubstanceName name: String) -> Profile? {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return profiles.first { $0.substanceName.lowercased() == needle }
    }

    // MARK: - Quantitative profiles (drawable)

    /// **Ethanol** — the textbook capacity-limited (zero-order) elimination drug. Km is so far below
    /// intoxicating BACs that clearance is effectively a fixed ~1 standard drink/hour regardless of
    /// load, so total exposure scales roughly with the *square* of the dose.
    /// Norberg et al. 2000 (PMID 10792196): Vmax 95 ± 25 mg/min, Km 27 ± 19 mg/L (IV primary).
    private static let ethanol = Profile(
        substanceName: "Alcohol",
        displayName: "Alcohol (ethanol)",
        mechanism: .elimination,
        confidence: .high,
        kinetics: Kinetics(
            kmMgPerL: 27,
            vmax: .wholeBodyMgPerMin(95),
            vdPerKg: 0.55,
            bioavailability: 0.9,
            ka: 0.05,
            referenceDoseMg: 14_000,
            exampleDoseMultiples: [1, 2, 3, 4],
            doseLabel: .drinks,
            displayWindowMinutes: 780,
            integrationMinutes: 1_440,
            stepMinutes: 2,
        ),
        headline: "Clearance is capped at ~1 drink/hour, so each extra drink stacks on top of the last and lingers — total exposure climbs far faster than the number of drinks.",
        knee: "Elimination is already maxed out after about one drink, so there is no \u{201C}safe extra\u{201D} that clears as fast as the first.",
        detail: "Alcohol is the classic zero-order drug: above a very low blood level the enzyme that clears it (alcohol dehydrogenase) is fully saturated and works at a fixed rate. Doubling the drinks more than doubles how long alcohol stays in your system and the area under the curve. Chronic heavy drinking speeds clearance somewhat (CYP2E1 induction); the ALDH2 \u{201C}flush\u{201D} variant does the opposite for acetaldehyde.",
        citation: "Norberg, Gabrielsson, Jones & Hahn 2000, Br J Clin Pharmacol (PMID 10792196); Holford 1987 (PMID 3319346).",
    )

    /// **Phenytoin** — the second textbook Michaelis-Menten elimination drug. Its Km (~4–7 mg/L) sits
    /// *below* the therapeutic range, so the system is already partly saturated within the normal dose
    /// range and a small dose increase near the top can roughly double serum levels into toxicity.
    private static let phenytoin = Profile(
        substanceName: "Phenytoin",
        displayName: "Phenytoin",
        mechanism: .elimination,
        confidence: .high,
        kinetics: Kinetics(
            kmMgPerL: 5.7,
            vmax: .mgPerKgPerDay(7),
            vdPerKg: 0.65,
            bioavailability: 0.9,
            ka: 0.005,
            referenceDoseMg: 300,
            exampleDoseMultiples: [1, 1.5, 2],
            doseLabel: .milligrams(perUnit: 300),
            displayWindowMinutes: 4_320,
            integrationMinutes: 7_200,
            stepMinutes: 12,
        ),
        headline: "The clearing enzyme is already half-saturated inside the normal dose range, so a small dose increase near the top can roughly double the level into toxicity.",
        knee: "Saturation begins within the therapeutic window itself — the curve bends up where most other drugs would still be a straight line.",
        detail: "Phenytoin is hydroxylated by a saturable liver enzyme system (CYP2C9/CYP2C19). Because its Km lies below the therapeutic range, dose and level are not proportional: titrate in small steps and confirm with blood levels. CYP2C9/2C19 poor metabolizers, age, and interacting drugs shift the knee lower. Shown as relative shape — phenytoin is individualized by therapeutic drug monitoring.",
        citation: "FDA Dilantin label (NDA 084349); Ludden et al. 1977 (PMID 837647); Ismail et al. 1990 (PMID 2089048).",
    )

    // MARK: - Qualitative profiles (no curve)

    /// **Codeine → morphine** — an *activation* ceiling, but a phenotype-limited one. The CYP2D6 step is
    /// low-affinity (high Km ~100 µM), so it does **not** substrate-saturate at clinical codeine levels;
    /// the morphine ceiling is set by enzyme *quantity* (CYP2D6 activity), not a dose knee. Drawing a
    /// saturating curve would be wrong, so this ships qualitative.
    private static let codeine = Profile(
        substanceName: "Codeine",
        displayName: "Codeine → morphine",
        mechanism: .activation,
        confidence: .medium,
        kinetics: nil,
        headline: "Codeine only works by being converted to morphine, and most people's CYP2D6 enzyme caps how much morphine they can make — so past a point, more codeine adds side-effects and duration, not more pain relief.",
        knee: "The limit is set by how much CYP2D6 enzyme you have, not by a specific milligram dose. The analgesic plateau around ~60 mg is a clinical observation, not a kinetic ceiling.",
        detail: "This ceiling is on the opioid effect only — not on codeine's other risks. Two big caveats: \u{201C}ultra-rapid metabolizers\u{201D} convert far more codeine to morphine and can reach dangerous levels at ordinary doses (the FDA contraindicates codeine in them), while \u{201C}poor metabolizers\u{201D} get little relief. So this is not a green light to take more.",
        citation: "Frontiers Pharmacol 2024 (PMC11096448); CPIC 2021 (PMC8249478); Kirchheiner et al. 2007 (PMID 16819548).",
    )

    /// **GHB / GBL** — saturable elimination with a genuinely steep human dose-exposure curve, but no
    /// clean human Km/Vmax exists (only rat/in-vitro numbers, grade D). Ships qualitative: the direction
    /// and the harm-reduction crux (thin recreational-to-dangerous margin) are well-evidenced.
    private static let ghb = Profile(
        substanceName: "GHB",
        displayName: "GHB / GBL",
        mechanism: .elimination,
        confidence: .medium,
        kinetics: nil,
        headline: "Exposure rises steeply and faster than dose — a small step up can disproportionately increase how much your body sees. The gap between a recreational and a dangerous dose is small.",
        knee: "Nonlinearity appears already at moderate recreational doses: a controlled study saw ~40% more exposure going from 25 to 35 mg/kg, and the regulated product's exposure rises ~3.8× when the dose doubles.",
        detail: "GHB's clearing pathway saturates, so dose and effect are not proportional and the margin for error is thin. Measure precisely, wait fully between doses (never re-dose because \u{201C}it hasn't hit yet\u{201D}), and treat any other depressant — especially alcohol — as compounding the danger. Liver impairment lowers the threshold further. No reliable human Km/Vmax exists, so the direction is shown without a drawn curve.",
        citation: "Liechti et al. 2016, Br J Clin Pharmacol (PMID 26659543); FDA/EMA sodium oxybate (Xyrem) label.",
    )

    // MARK: - Concentration-time curves (intensity over time, one per example dose)

    /// One sample on a concentration-time curve.
    struct ConcentrationPoint: Identifiable {
        /// Minutes since the dose.
        let minutes: Double
        /// Blood level, normalized so the *reference* dose's peak = 1 (relative intensity).
        let level: Double
        var id: Double {
            minutes
        }
    }

    /// One example dose's concentration-time curve.
    struct DoseCurve: Identifiable {
        let doseMultiple: Double
        /// Legend label, e.g. "2 drinks" or "600 mg".
        let label: LocalizedStringResource
        let points: [ConcentrationPoint]
        var id: Double {
            doseMultiple
        }
    }

    /// The overlaid family of curves plus the headline exposure figure.
    struct ConcentrationChart {
        let curves: [DoseCurve]
        /// Plotted time window, minutes.
        let windowMinutes: Double
        /// Total exposure (area under the curve) at the largest example dose, as a multiple of the
        /// reference dose's exposure — the supralinear payload, stated in words beside the chart.
        let exposureMultipleAtMax: Double
        /// The largest example dose, as a multiple of the reference.
        let maxDoseMultiple: Double
    }

    /// Build the overlaid concentration-time curves for a quantitative (elimination) profile.
    ///
    /// Rather than an abstract dose→exposure scaling plot, this draws *what's in the blood over time*
    /// for several example doses (the same visual language as the journal effects graph). The supralinear
    /// danger is then directly visible: a higher dose is not just a taller curve — because clearance is
    /// capacity-limited it is also a much **wider** one, so the area it encloses (total exposure) grows
    /// far faster than the dose. Levels are normalized to the reference dose's peak; the largest dose's
    /// exposure multiple (measured over the full integration window) is returned for the caption.
    ///
    /// Returns `nil` for qualitative profiles.
    static func concentrationChart(for kinetics: Kinetics, weightKg: Double) -> ConcentrationChart? {
        let vmax = kinetics.vmax.mgPerLPerMin(weightKg: weightKg, vdPerKg: kinetics.vdPerKg)
        guard vmax > 0, kinetics.kmMgPerL > 0, !kinetics.exampleDoseMultiples.isEmpty else { return nil }
        let saturation = PKModel.Saturation.elimination(km: kinetics.kmMgPerL, vmax: vmax)

        func curve(multiple: Double, minutes: Double) -> PKModel.SaturableCurve {
            PKModel.saturableCurve(
                dose: multiple * kinetics.referenceDoseMg,
                bioavailability: kinetics.bioavailability,
                vdPerKg: kinetics.vdPerKg,
                weightKg: weightKg,
                ka: kinetics.ka,
                saturation: saturation,
                durationMinutes: minutes,
                stepMinutes: kinetics.stepMinutes,
            )
        }

        // Normalize every curve to the reference dose's peak so the y-axis reads as relative intensity.
        let refPeak = max(curve(multiple: 1, minutes: kinetics.displayWindowMinutes).peakParent, .leastNonzeroMagnitude)

        let curves: [DoseCurve] = kinetics.exampleDoseMultiples.sorted().map { multiple in
            let c = curve(multiple: multiple, minutes: kinetics.displayWindowMinutes)
            let points = c.parent.enumerated().map { index, conc in
                ConcentrationPoint(minutes: Double(index) * c.stepMinutes, level: conc / refPeak)
            }
            return DoseCurve(doseMultiple: multiple, label: kinetics.doseLabel.text(multiple: multiple), points: points)
        }

        // Exposure (AUC) ratio at the largest dose, integrated over the full window so it isn't truncated.
        let maxMultiple = kinetics.exampleDoseMultiples.max() ?? 1
        let refAUC = max(curve(multiple: 1, minutes: kinetics.integrationMinutes).effectAUC, .leastNonzeroMagnitude)
        let maxAUC = curve(multiple: maxMultiple, minutes: kinetics.integrationMinutes).effectAUC

        return ConcentrationChart(
            curves: curves,
            windowMinutes: kinetics.displayWindowMinutes,
            exposureMultipleAtMax: maxAUC / refAUC,
            maxDoseMultiple: maxMultiple,
        )
    }
}

extension SaturablePharmacology.Kinetics.DoseLabel {
    /// Render the per-curve legend label for a given dose multiple.
    func text(multiple: Double) -> LocalizedStringResource {
        switch self {
        case .drinks:
            let n = Int(multiple.rounded())
            return n == 1 ? "1 drink" : "\(n) drinks"
        case let .milligrams(perUnit):
            return "\(Int((multiple * perUnit).rounded())) mg"
        }
    }
}
