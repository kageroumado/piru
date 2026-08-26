import Foundation

/// One `saturable_kinetics` row as the database holds it — which step runs out of capacity, and the
/// Michaelis-Menten constants for the substances that have clean human values. Every numeric field is
/// `nil` together on a qualitative row.
nonisolated struct SaturableKineticsRow {
    let substanceName: String
    /// `elimination` | `activation` | `absorption`.
    let mechanism: String
    /// `high` | `medium` | `low`.
    let confidence: String
    /// Michaelis constant, mg/L.
    let kmMgPerL: Double?
    /// Maximum metabolic rate in whichever convention ``vmaxBasis`` names.
    let vmax: Double?
    /// `whole_body_mg_per_min` | `mg_per_kg_per_day`.
    let vmaxBasis: String?
    /// The **total-body-water** volume of distribution ``vmax`` was fitted against, L/kg. A different
    /// quantity from the substance's `pk_routes` Vd, which for ethanol carries the forensic whole-body
    /// (Widmark) 0.7 L/kg against this 0.55 — so never source this from the resolver instead: pairing a
    /// Michaelis-Menten Vmax with the other convention's Vd moves where the curve crosses Km.
    let vdLPerKg: Double?
    /// First-order absorption rate constant, per minute.
    let kaPerMin: Double?
    /// Terminal elimination half-life, minutes — present on an `absorption` row, whose clearance is
    /// ordinary first-order.
    let halfLifeMinutes: Double?
    /// The source line shown verbatim beneath the profile.
    let citation: String
}

/// One `bioavailability_by_dose` point: absolute oral bioavailability measured at a stated dose.
nonisolated struct BioavailabilityPoint {
    let doseMg: Double
    /// `per_day` (a divided daily dose, as the label reports it) | `single`.
    let basis: String
    let bioavailabilityPct: Double
    /// The series' source line, shown verbatim beneath the chart.
    let citation: String
}

/// Saturable-kinetics profiles for the **Ceiling-Effect** tool (pharmacology axis, Stage 6).
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
/// ## Where the numbers live
/// The constants a curve is *integrated from* — Km, Vmax, Vd, F, kₐ, and the F-vs-dose table — are data
/// and come from the bundled DB's `saturable_kinetics` and `bioavailability_by_dose`, each row carrying
/// the citation it is shown with. What a curve is *drawn on* — which dose to call one unit, which
/// multiples to overlay, how wide a window to plot — is a rendering choice with no source and stays in
/// ``ProfileCopy``, together with the substance's localized copy. A DB row whose substance has no
/// ``ProfileCopy`` case ships nothing: a profile with no explanation is not shippable.
///
/// ## Faithful over comprehensive
/// A profile ships numbers only where clean *human* Km/Vmax exist; the rest carry a direction and a knee
/// in words, never a fabricated curve. Codeine's morphine ceiling is CYP2D6 phenotype/enzyme-quantity
/// limited rather than substrate-saturable at clinical doses, and GHB's only published constants are rat
/// and in-vitro (grade D) — so both are qualitative even though their nonlinearity is real.
enum SaturablePharmacology {
    /// Which step saturates — the attachment points of the same capacity-limited (Michaelis-Menten)
    /// term. Raw values match the `saturable_kinetics.mechanism` vocabulary.
    enum Mechanism: String {
        /// The *clearing* enzyme saturates → supralinear accumulation (the warning).
        case elimination
        /// The *activating* enzyme (prodrug → active species) saturates → a ceiling on effect.
        case activation
        /// The *absorbing* carrier saturates (capacity-limited intestinal uptake) → fractional
        /// bioavailability FALLS with dose, so total exposure climbs SUB-proportionally. The benign
        /// ceiling — extra drug simply isn't absorbed; the directional inverse of saturable elimination.
        case absorption
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

            /// Attach a `saturable_kinetics` Vmax to the convention its `vmax_basis` column names.
            /// `nil` for an unknown basis: a rate whose units are unclear must not reach the integrator,
            /// where mg/min and mg/kg/day differ by three orders of magnitude.
            init?(rawBasis: String?, value: Double) {
                switch rawBasis {
                case "whole_body_mg_per_min": self = .wholeBodyMgPerMin(value)
                case "mg_per_kg_per_day": self = .mgPerKgPerDay(value)
                default: return nil
                }
            }

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

    /// Saturable-*absorption* kinetics — a capacity-limited intestinal carrier (gabapentin's
    /// system-L / LAT1) whose fractional bioavailability `F` FALLS as the single dose rises, so total
    /// exposure climbs SUB-proportionally with dose: the benign, sublinear inverse of the elimination
    /// ceiling. Modeled from an empirical F-vs-dose table; clearance is ordinary first-order (absorption,
    /// not elimination, is what saturates), so each example curve is a Bateman scaled by the absorbed
    /// amount `dose · F(dose)`.
    struct Absorption {
        /// Empirical `(single-dose mg, bioavailability fraction)` points, ascending by dose.
        let fByDose: [(doseMg: Double, f: Double)]
        /// Volume of distribution per kg, **L/kg**.
        let vdPerKg: Double
        /// Terminal elimination half-life, **minutes** (first-order — the ceiling is on absorption).
        let halfLifeMin: Double
        /// First-order absorption rate constant, per minute.
        let ka: Double
        /// The dose treated as "1 unit" — the smallest example single dose (milligrams).
        let referenceDoseMg: Double
        /// Example doses (as multiples of the reference dose) drawn as overlaid curves.
        let exampleDoseMultiples: [Double]
        /// How the per-curve dose labels read.
        let doseLabel: Kinetics.DoseLabel
        /// Plotted time window (minutes).
        let displayWindowMinutes: Double
        /// Window over which total exposure (AUC) is integrated.
        let integrationMinutes: Double
        /// Integration / sampling step (minutes).
        let stepMinutes: Double

        /// Linearly-interpolated bioavailability `F` at a single `dose` (clamped to the table ends).
        func bioavailability(atDoseMg dose: Double) -> Double {
            guard let first = fByDose.first, let last = fByDose.last else { return 1 }
            if dose <= first.doseMg { return first.f }
            if dose >= last.doseMg { return last.f }
            for i in 1 ..< fByDose.count {
                let lo = fByDose[i - 1], hi = fByDose[i]
                if dose <= hi.doseMg {
                    let span = hi.doseMg - lo.doseMg
                    let t = span > 0 ? (dose - lo.doseMg) / span : 0
                    return lo.f + t * (hi.f - lo.f)
                }
            }
            return last.f
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
        /// Quantitative saturable-*elimination* kinetics, or `nil` for a qualitative / non-elimination profile.
        let kinetics: Kinetics?
        /// Quantitative saturable-*absorption* kinetics (sublinear ceiling), or `nil`.
        var absorption: Absorption?
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
            kinetics != nil || absorption != nil
        }
    }

    // MARK: - Assembly from the bundled DB

    /// The substances with a shipped ceiling profile, in the curated display order the DB row carries.
    ///
    /// A DB row becomes a ``Profile`` only when a ``ProfileCopy`` case names its substance: the numbers
    /// are data, but the sentences and the chart geometry are not, and a curve with neither would be a
    /// shape with no meaning attached.
    static var profiles: [Profile] {
        let fByDose = SubstanceStore.shared.bioavailabilityByDose()
        return SubstanceStore.shared.saturableKinetics().compactMap { row in
            guard let copy = ProfileCopy(rawValue: row.substanceName.lowercased()),
                  let mechanism = Mechanism(rawValue: row.mechanism) else { return nil }
            return Profile(
                substanceName: row.substanceName,
                displayName: copy.displayName,
                mechanism: mechanism,
                confidence: ConfidenceTier(grade: row.confidence),
                kinetics: copy.kinetics(from: row, bioavailability: resolvedBioavailability(row.substanceName)),
                absorption: copy.absorption(from: row, fByDose: fByDose[row.substanceName.lowercased()] ?? []),
                headline: copy.headline,
                knee: copy.knee,
                detail: copy.detail,
                citation: row.citation,
            )
        }
    }

    /// Oral bioavailability for a ceiling profile, from the same `pk_routes` resolution every other
    /// consumer reads. `saturable_kinetics` carries no F of its own, so a correction to a substance's
    /// bioavailability reaches this tool with no second copy to remember.
    ///
    /// The resolver's fallback when a substance has no measured F is `1.0`, badged `.unverified` —
    /// which is the consistent reading where the stored Vd is an apparent V/F, but not where this
    /// table supplies a true Vd. A profile in that position wants a sourced `pk_routes` row, never a
    /// column here: a second copy is what lets the two disagree.
    private static func resolvedBioavailability(_ substanceName: String) -> Double {
        SubstanceStore.shared.pharmacologyParameters(forSubstanceName: substanceName)
            .bioavailabilityFraction ?? 1
    }

    /// Case-insensitive lookup by substance name (canonical or display alias handled by the caller).
    static func profile(forSubstanceName name: String) -> Profile? {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return profiles.first { $0.substanceName.lowercased() == needle }
    }

    // MARK: - Gabapentinoid absorption contrast (teaching pair, not a ceiling profile)

    /// The gabapentinoid absorption contrast — **same α2δ-1 drug class, opposite dose→exposure
    /// behavior**, the first absorption-side teaching pair. Gabapentin's intestinal uptake saturates
    /// (system-L / LAT1) so oral bioavailability FALLS with dose; pregabalin uses the carrier in a
    /// non-saturating regime and stays dose-LINEAR (~90% at any dose). Pregabalin has no knee, so it is
    /// NOT a ceiling ``Profile`` (never in ``profiles``) — it exists only as this comparison.
    ///
    /// Both lines are the same `bioavailability_by_dose` rows the gabapentin ceiling curves are drawn
    /// from, read on their reported per-day basis. One table, two charts: a second copy of the F-vs-dose
    /// points on a different dose axis is how the two would silently drift apart.
    enum GabapentinoidComparison {
        /// One (daily-dose, bioavailability) sample on a drug's F-vs-dose line.
        struct Point: Identifiable {
            /// Total daily dose, **mg/day** (divided across the day).
            let doseMgPerDay: Double
            /// Absolute oral bioavailability at that dose, **percent**.
            let bioavailabilityPct: Double
            var id: Double {
                doseMgPerDay
            }
        }

        /// Gabapentin — saturable: F falls across the label dose range.
        static var gabapentin: [Point] {
            points(for: "gabapentin")
        }

        /// Pregabalin — dose-linear: F stays put across its therapeutic range.
        static var pregabalin: [Point] {
            points(for: "pregabalin")
        }

        private static func points(for name: String) -> [Point] {
            SubstanceStore.shared.bioavailabilityByDose()[name, default: []]
                .filter { $0.basis == BioavailabilityBasis.perDay }
                .map { Point(doseMgPerDay: $0.doseMg, bioavailabilityPct: $0.bioavailabilityPct) }
        }

        static let headline: LocalizedStringResource = "Two drugs that hit the same target behave oppositely as you scale the dose: gabapentin's absorbed fraction falls, pregabalin's stays put."
        static let detail: LocalizedStringResource = "Both bind the α2δ-1 calcium-channel subunit — but gabapentin rides a saturable intestinal carrier (system-L / LAT1), so the fraction absorbed drops as the dose climbs (~60% → ~27%) and exposure flattens out. That's why gabapentin is dosed several times a day and why very large single doses buy little extra. Pregabalin uses the carrier without saturating it, so it stays ~90% absorbed at any dose — predictable, dose-proportional, simpler to titrate. (Pregabalin is also effective at far fewer milligrams, so its line sits at the low end of the dose axis.)"

        /// Both drugs' source lines, joined — the comparison cites whatever each line was measured in.
        static var citation: String {
            let table = SubstanceStore.shared.bioavailabilityByDose()
            var seen = Set<String>()
            let sources = ["gabapentin", "pregabalin"]
                .compactMap { table[$0]?.first?.citation }
                .filter { seen.insert($0).inserted }
            return sources.joined(separator: "; ") + "."
        }
    }

    // MARK: - Per-substance copy and chart geometry

    /// The `dose_basis` values `bioavailability_by_dose` uses. Spelled once so a filter and a pipeline
    /// row can never drift apart on a string literal.
    enum BioavailabilityBasis {
        /// A total daily dose, divided across the day as the label directs.
        static let perDay = "per_day"
        /// One administration.
        static let single = "single"
    }

    /// Everything about a ceiling profile that is *not* a measured quantity: the substance's localized
    /// copy, and the geometry its curves are drawn on. Keyed by the lowercased canonical name of the
    /// `saturable_kinetics` row it belongs to.
    ///
    /// Chart geometry is a rendering choice, not evidence — no source states that ethanol should be
    /// plotted as one to four drinks over thirteen hours. Keeping it here rather than in the database
    /// is what stops an unsourced number from sitting in a table beside cited ones.
    enum ProfileCopy: String {
        case alcohol
        case phenytoin
        case gabapentin
        case codeine
        case tramadol
        case ghb

        /// Display name shown in the tool (may differ from the canonical name).
        var displayName: LocalizedStringResource {
            switch self {
            case .alcohol: "Alcohol (ethanol)"
            case .phenytoin: "Phenytoin"
            case .gabapentin: "Gabapentin"
            case .codeine: "Codeine → morphine"
            case .tramadol: "Tramadol → O-DSMT (M1)"
            case .ghb: "GHB / GBL"
            }
        }

        /// One-line takeaway — the headline message.
        var headline: LocalizedStringResource {
            switch self {
            case .alcohol:
                "Clearance is capped at ~1 drink/hour, so each extra drink stacks on top of the last and lingers — total exposure climbs far faster than the number of drinks."
            case .phenytoin:
                "The clearing enzyme is already half-saturated inside the normal dose range, so a small dose increase near the top can roughly double the level into toxicity."
            case .gabapentin:
                "Gabapentin is absorbed by a carrier that runs out of capacity, so the fraction that reaches your blood DROPS as the dose climbs — taking twice as much delivers much less than twice the exposure."
            case .codeine:
                "Codeine only works by being converted to morphine, and most people's CYP2D6 enzyme caps how much morphine they can make — so past a point, more codeine adds side-effects and duration while the pain relief plateaus."
            case .tramadol:
                "Tramadol only becomes a strong opioid after CYP2D6 converts it to M1 — and how much you make depends on your genes. Most people plateau; \u{201C}ultra-rapid metabolizers\u{201D} have no such cap and can reach dangerous levels at ordinary doses."
            case .ghb:
                "Exposure rises steeply and faster than dose — a small step up can disproportionately increase how much your body sees. The gap between a recreational and a dangerous dose is small."
            }
        }

        /// Where the curve bends and why (the "knee").
        var knee: LocalizedStringResource {
            switch self {
            case .alcohol:
                "Elimination is already maxed out after about one drink, so there is no \u{201C}safe extra\u{201D} that clears as fast as the first."
            case .phenytoin:
                "Saturation begins within the therapeutic window itself — the curve bends up where most other drugs would still be a straight line."
            case .gabapentin:
                "The carrier is already saturating across the normal dose range: bioavailability falls from ~60% at 900 mg/day to ~27% at 4800 mg/day, so each step up buys progressively less."
            case .codeine:
                "The limit is set by how much CYP2D6 enzyme you have. The analgesic plateau around ~60 mg is a clinical observation."
            case .tramadol:
                "There is no fixed milligram knee — the limit (or its absence) is set by your CYP2D6 activity. Poor metabolizers get little opioid effect but keep tramadol's serotonin/seizure risk; ultra-rapid metabolizers blow past the usual ceiling."
            case .ghb:
                "Nonlinearity appears already at moderate recreational doses: a controlled study saw ~40% more exposure going from 25 to 35 mg/kg, and the regulated product's exposure rises ~3.8× when the dose doubles."
            }
        }

        /// Longer explanation / caveats.
        var detail: LocalizedStringResource {
            switch self {
            case .alcohol:
                "Alcohol is the classic zero-order drug: above a very low blood level the enzyme that clears it (alcohol dehydrogenase) is fully saturated and works at a fixed rate. Doubling the drinks more than doubles how long alcohol stays in your system and the area under the curve. Chronic heavy drinking speeds clearance somewhat (CYP2E1 induction); the ALDH2 \u{201C}flush\u{201D} variant does the opposite for acetaldehyde."
            case .phenytoin:
                "Phenytoin is hydroxylated by a saturable liver enzyme system (CYP2C9/CYP2C19). Because its Km lies below the therapeutic range, dose and level are not proportional: titrate in small steps and confirm with blood levels. CYP2C9/2C19 poor metabolizers, age, and interacting drugs shift the knee lower. Shown as relative shape — phenytoin is individualized by therapeutic drug monitoring."
            case .gabapentin:
                "This is the opposite of the alcohol/phenytoin ceiling: there the clearing enzyme saturates and exposure runs away upward; here the absorbing transporter (system-L / LAT1) saturates and exposure flattens out — a built-in brake, though it also caps the benefit of very large single doses and is why gabapentin is dosed several times a day. Pregabalin, the same drug class, uses the transporter differently and stays ~90% absorbed at any dose (dose-linear) — a clean contrast in the same family. Shown as relative shape."
            case .codeine:
                "This ceiling is on the opioid effect only — not on codeine's other risks. Two big caveats: \u{201C}ultra-rapid metabolizers\u{201D} convert far more codeine to morphine and can reach dangerous levels at ordinary doses (the FDA contraindicates codeine in them), while \u{201C}poor metabolizers\u{201D} get little relief. So this is not a green light to take more."
            case .tramadol:
                "This is the mirror image of codeine: same CYP2D6 activation step, opposite danger. Two cautions. (1) Repeated dosing raises tramadol's own absorption (first-pass saturates, F climbs ~75%→90–100%), so steady-state levels run higher than a single dose predicts. (2) The opioid limb is carried almost entirely by the metabolite M1/O-DSMT (a potent 3.4 nM µ-agonist), so strong CYP2D6 inhibitors (paroxetine, fluoxetine, bupropion, quinidine) mute the painkilling effect while leaving — or raising — the serotonergic and seizure risk of the parent. \u{201C}Cleaner\u{201D} is not \u{201C}safer.\u{201D} Described in words."
            case .ghb:
                "GHB's clearing pathway saturates, so dose and effect are not proportional and the margin for error is thin. Measure precisely, wait fully between doses (never re-dose because \u{201C}it hasn't hit yet\u{201D}), and treat any other depressant — especially alcohol — as compounding the danger. Liver impairment lowers the threshold further. No reliable human Km/Vmax exists, so the direction is shown without a drawn curve."
            }
        }

        /// The geometry this substance's overlaid curves are drawn on, or `nil` for a substance that
        /// ships words only.
        var geometry: Geometry? {
            switch self {
            case .alcohol:
                Geometry(
                    referenceDoseMg: 14_000,
                    exampleDoseMultiples: [1, 2, 3, 4],
                    doseLabel: .drinks,
                    displayWindowMinutes: 780,
                    integrationMinutes: 1_440,
                    stepMinutes: 2,
                )
            case .phenytoin:
                Geometry(
                    referenceDoseMg: 300,
                    exampleDoseMultiples: [1, 1.5, 2],
                    doseLabel: .milligrams(perUnit: 300),
                    displayWindowMinutes: 4_320,
                    integrationMinutes: 7_200,
                    stepMinutes: 12,
                )
            case .gabapentin:
                Geometry(
                    referenceDoseMg: 300,
                    exampleDoseMultiples: [1, 2, 3, 4],
                    doseLabel: .milligrams(perUnit: 300),
                    displayWindowMinutes: 1_440,
                    integrationMinutes: 2_880,
                    stepMinutes: 5,
                    dosesPerDay: 3,
                )
            case .codeine, .tramadol, .ghb:
                nil
            }
        }

        /// Quantitative saturable-*elimination* kinetics for this substance, or `nil` when the DB row
        /// carries no Km/Vmax (a qualitative profile) or the mechanism is not elimination.
        /// `bioavailability` comes from the substance's resolved pharmacology, not from this table.
        func kinetics(from row: SaturableKineticsRow, bioavailability: Double) -> Kinetics? {
            guard let geometry, let km = row.kmMgPerL, let vmax = row.vmax,
                  let basis = Kinetics.VmaxBasis(rawBasis: row.vmaxBasis, value: vmax),
                  let vdPerKg = row.vdLPerKg, let ka = row.kaPerMin else { return nil }
            return Kinetics(
                kmMgPerL: km,
                vmax: basis,
                vdPerKg: vdPerKg,
                bioavailability: bioavailability,
                ka: ka,
                referenceDoseMg: geometry.referenceDoseMg,
                exampleDoseMultiples: geometry.exampleDoseMultiples,
                doseLabel: geometry.doseLabel,
                displayWindowMinutes: geometry.displayWindowMinutes,
                integrationMinutes: geometry.integrationMinutes,
                stepMinutes: geometry.stepMinutes,
            )
        }

        /// Quantitative saturable-*absorption* kinetics for this substance, or `nil` when the DB carries
        /// no F-vs-dose series or the row lacks the first-order clearance the curves are cleared with.
        ///
        /// The DB reports F against the **daily** dose, because that is what the label measured. One
        /// administration is that dose divided by ``Geometry/dosesPerDay`` — a modeling assumption about
        /// the dosing regimen, which is why the divisor lives beside the geometry and not in the table.
        func absorption(from row: SaturableKineticsRow, fByDose points: [BioavailabilityPoint]) -> Absorption? {
            guard let geometry, let dosesPerDay = geometry.dosesPerDay, dosesPerDay > 0,
                  let vdPerKg = row.vdLPerKg, let halfLife = row.halfLifeMinutes,
                  let ka = row.kaPerMin, !points.isEmpty else { return nil }
            let perDose = points.map { point -> (doseMg: Double, f: Double) in
                let divisor = point.basis == BioavailabilityBasis.perDay ? dosesPerDay : 1
                return (doseMg: point.doseMg / divisor, f: point.bioavailabilityPct / 100)
            }
            return Absorption(
                fByDose: perDose,
                vdPerKg: vdPerKg,
                halfLifeMin: halfLife,
                ka: ka,
                referenceDoseMg: geometry.referenceDoseMg,
                exampleDoseMultiples: geometry.exampleDoseMultiples,
                doseLabel: geometry.doseLabel,
                displayWindowMinutes: geometry.displayWindowMinutes,
                integrationMinutes: geometry.integrationMinutes,
                stepMinutes: geometry.stepMinutes,
            )
        }

        /// How one substance's curves are laid out. Every field is a rendering choice.
        struct Geometry {
            /// The dose treated as "1 unit" — the smallest example dose (milligrams).
            let referenceDoseMg: Double
            /// The example doses (as multiples of the reference dose) drawn as overlaid curves.
            let exampleDoseMultiples: [Double]
            /// How the per-curve dose labels read ("2 drinks" vs "600 mg").
            let doseLabel: Kinetics.DoseLabel
            /// The plotted time window (minutes) — wide enough for the largest example dose to fall back
            /// toward baseline.
            let displayWindowMinutes: Double
            /// How long to integrate when measuring total exposure (AUC) — sized to capture the slowest
            /// (highest-dose) clearance fully, so the exposure ratio isn't truncated.
            let integrationMinutes: Double
            /// Integration step (minutes); coarser for long-clearance drugs to keep the render cheap.
            let stepMinutes: Double
            /// Administrations per day assumed when turning a per-day bioavailability point into a
            /// single-dose one. `nil` for a substance with no F-vs-dose series.
            var dosesPerDay: Double?

            init(
                referenceDoseMg: Double,
                exampleDoseMultiples: [Double],
                doseLabel: Kinetics.DoseLabel,
                displayWindowMinutes: Double,
                integrationMinutes: Double,
                stepMinutes: Double,
                dosesPerDay: Double? = nil,
            ) {
                self.referenceDoseMg = referenceDoseMg
                self.exampleDoseMultiples = exampleDoseMultiples
                self.doseLabel = doseLabel
                self.displayWindowMinutes = displayWindowMinutes
                self.integrationMinutes = integrationMinutes
                self.stepMinutes = stepMinutes
                self.dosesPerDay = dosesPerDay
            }
        }
    }

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

    /// Build the overlaid concentration-time curves for a saturable-*absorption* profile.
    ///
    /// Same visual language as ``concentrationChart(for:weightKg:)``, but the nonlinearity lives in
    /// *absorption*: each example dose is scaled by its dose-dependent bioavailability `F(dose)` (which
    /// falls as the dose rises) and then cleared first-order. So a higher dose is a curve that grows
    /// *less* than proportionally — the area it encloses (total exposure) lags behind the dose, the
    /// mirror image of the elimination ceiling. Levels are normalized to the reference dose's peak; the
    /// largest dose's exposure multiple (< its dose multiple) is returned for the caption.
    static func absorptionChart(for a: Absorption, weightKg: Double) -> ConcentrationChart? {
        guard a.vdPerKg > 0, a.halfLifeMin > 0, a.ka > 0, weightKg > 0,
              !a.exampleDoseMultiples.isEmpty, a.stepMinutes > 0 else { return nil }
        let ke = log(2) / a.halfLifeMin

        func conc(multiple: Double, at minutes: Double) -> Double {
            let dose = multiple * a.referenceDoseMg
            return PKModel.concentrationAbsolute(
                dose: dose,
                bioavailability: a.bioavailability(atDoseMg: dose),
                vdPerKg: a.vdPerKg,
                weightKg: weightKg,
                ke: ke,
                ka: a.ka,
                at: minutes,
            )
        }

        let displaySteps = max(Int(a.displayWindowMinutes / a.stepMinutes), 1)
        func peak(multiple: Double) -> Double {
            (0 ... displaySteps).map { conc(multiple: multiple, at: Double($0) * a.stepMinutes) }.max() ?? 0
        }
        let refPeak = max(peak(multiple: 1), .leastNonzeroMagnitude)

        let curves: [DoseCurve] = a.exampleDoseMultiples.sorted().map { multiple in
            let points = (0 ... displaySteps).map { i -> ConcentrationPoint in
                let m = Double(i) * a.stepMinutes
                return ConcentrationPoint(minutes: m, level: conc(multiple: multiple, at: m) / refPeak)
            }
            return DoseCurve(doseMultiple: multiple, label: a.doseLabel.text(multiple: multiple), points: points)
        }

        /// Trapezoidal AUC over the integration window so the exposure ratio isn't truncated.
        func auc(multiple: Double) -> Double {
            let n = max(Int(a.integrationMinutes / a.stepMinutes), 1)
            var sum = 0.0
            var prev = conc(multiple: multiple, at: 0)
            for i in 1 ... n {
                let c = conc(multiple: multiple, at: Double(i) * a.stepMinutes)
                sum += (prev + c) / 2 * a.stepMinutes
                prev = c
            }
            return sum
        }
        let maxMultiple = a.exampleDoseMultiples.max() ?? 1
        let refAUC = max(auc(multiple: 1), .leastNonzeroMagnitude)

        return ConcentrationChart(
            curves: curves,
            windowMinutes: a.displayWindowMinutes,
            exposureMultipleAtMax: auc(multiple: maxMultiple) / refAUC,
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
