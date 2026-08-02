import ActivityKit
import Foundation

/// Wire format for the Piru Live Activity widget extension.
///
/// `PiruActivityAttributes` defines two parts of the data the app and extension
/// exchange via ActivityKit:
///
/// - **Static attributes** (this struct's stored properties): set once at
///   `Activity.request(…)` time and immutable for the lifetime of the activity.
///   Currently just `startTime`.
/// - **`ContentState`**: mutable per-update payload pushed via `activity.update(…)`.
///   Drives the widget's timeline graph, progress bar, and timer labels.
///
/// Because the app target and the widget extension can be on different versions
/// at runtime (a widget extension launched against an older activity, or vice
/// versa after an upgrade), every field on `ContentState`, `ActiveSubstanceState`,
/// and the static attributes MUST be treated as a stable, append-only contract:
///
/// - Never remove or rename fields without a deprecation window.
/// - New fields must be optional (`Codable` decoding tolerates missing keys) or
///   provide a default in a custom `init(from:)` — see `ActiveSubstanceState`'s
///   `doseIntensity` for the pattern.
nonisolated struct PiruActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var activeSubstances: [ActiveSubstanceState]
        var lastUpdated: Date
    }

    let startTime: Date
}

nonisolated struct ActiveSubstanceState: Codable, Hashable {
    let substanceName: String
    let colorHex: String
    let doseTimestamp: Date
    let amount: Double
    let unit: String
    let route: String
    let onsetEndMinutes: Double
    let comeupEndMinutes: Double
    let peakEndMinutes: Double
    let offsetEndMinutes: Double
    let afterglowEndMinutes: Double?
    let totalMinutes: Double
    /// Dose intensity used to scale the timeline curve height, clamped to
    /// `[0.05, 1.0]`.
    ///
    /// Computed by `ActiveSubstanceCalculator.computeDoseIntensity(amount:doseRange:)`:
    /// `amount / heavy_threshold`, with looser fallbacks (strong upper, common
    /// upper × 1.5) when `heavy` isn't defined. Substances with no dose-range
    /// data fall back to `unknownIntensity` (0.60) — a neutral mid-common-ish
    /// height. Sub-threshold doses are floored at `minimumIntensity` (0.05) so
    /// they still render as a visible nub instead of disappearing.
    let doseIntensity: Double

    /// Unclamped dose magnitude — `amount / heavy_threshold` with the *same*
    /// reference as ``doseIntensity`` but **without the 1.0 cap**. This is the
    /// linear quantity the timeline superposes: stacked doses sum their
    /// magnitudes (`4×0.7 → 2.8`) and a single combined dose of the same total
    /// (`80 mg → 2.8`) lands identically, so the merged curve passes one
    /// saturating Hill link and `4×20 mg ≡ 1×80 mg` falls out for free. Floored
    /// at `minimumIntensity`; defaults to ``doseIntensity`` when not supplied.
    let doseMagnitude: Double

    /// Where the substance's **sourced** heavy-dose bound falls on the
    /// ``doseMagnitude`` scale, or `nil` when its dose ladder carries no heavy
    /// bound at all.
    ///
    /// Because magnitude is `amount / heavy_threshold`, this is `1.0` whenever
    /// the denominator *is* a published `heavy` value — so the number itself
    /// carries no new information, but its presence does: it is the difference
    /// between a threshold somebody wrote down and one
    /// `ActiveSubstanceCalculator.heavyReference(for:)` improvised from the
    /// strong/common bounds so the curve would have *some* height. Only the
    /// former may be drawn as a marked region on the graph; the fallbacks scale
    /// a curve honestly enough but are nobody's stated threshold.
    ///
    /// Route caveat: the ladder is the one that scaled this dose, which for a
    /// route with no doses of its own is another route's (see
    /// `ActiveSubstanceCalculator.resolveDoseRange(substance:route:)`). That is
    /// already true of the curve's whole height, so the band inherits it rather
    /// than introducing it.
    let heavyThresholdMagnitude: Double?

    /// Acute-tolerance (tachyphylaxis) strength, `0...1`, from the substance's
    /// category (`SubstanceCategory.acuteToleranceFactor`). Drives the timeline
    /// curve's descending-limb gate: stimulants/empathogens crash faster than
    /// their plasma curve, so the felt effect returns to baseline by
    /// `totalMinutes` rather than trailing off on the slow elimination tail. `0`
    /// leaves the pure Bateman offset unchanged.
    let tachyphylaxis: Double

    /// The user's body weight (kg) captured when this state was built. Only ethanol's zero-order
    /// elimination reads it — a heavier body clears a fixed gram dose faster (`Vmax ∝ weight`), so the
    /// alcohol curve narrows with weight. Riding inside the (immutable, `Hashable`) state keeps the
    /// off-main curve math weight-aware without a shared global, and folds weight into the model cache
    /// key for free. Defaults to ``PKModel/referenceBodyWeightKg`` for non-alcohol doses, which ignore it.
    let bodyWeightKg: Double

    init(substanceName: String, colorHex: String, doseTimestamp: Date, amount: Double, unit: String, route: String, onsetEndMinutes: Double, comeupEndMinutes: Double, peakEndMinutes: Double, offsetEndMinutes: Double, afterglowEndMinutes: Double?, totalMinutes: Double, doseIntensity: Double = 1.0, doseMagnitude: Double? = nil, heavyThresholdMagnitude: Double? = nil, tachyphylaxis: Double = 0, bodyWeightKg: Double = PKModel.referenceBodyWeightKg) {
        self.substanceName = substanceName
        self.colorHex = colorHex
        self.doseTimestamp = doseTimestamp
        self.amount = amount
        self.unit = unit
        self.route = route
        self.onsetEndMinutes = onsetEndMinutes
        self.comeupEndMinutes = comeupEndMinutes
        self.peakEndMinutes = peakEndMinutes
        self.offsetEndMinutes = offsetEndMinutes
        self.afterglowEndMinutes = afterglowEndMinutes
        self.totalMinutes = totalMinutes
        self.doseIntensity = doseIntensity
        self.doseMagnitude = doseMagnitude ?? doseIntensity
        self.heavyThresholdMagnitude = heavyThresholdMagnitude
        self.tachyphylaxis = tachyphylaxis
        self.bodyWeightKg = bodyWeightKg
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        substanceName = try c.decode(String.self, forKey: .substanceName)
        colorHex = try c.decode(String.self, forKey: .colorHex)
        doseTimestamp = try c.decode(Date.self, forKey: .doseTimestamp)
        amount = try c.decode(Double.self, forKey: .amount)
        unit = try c.decode(String.self, forKey: .unit)
        route = try c.decode(String.self, forKey: .route)
        onsetEndMinutes = try c.decode(Double.self, forKey: .onsetEndMinutes)
        comeupEndMinutes = try c.decode(Double.self, forKey: .comeupEndMinutes)
        peakEndMinutes = try c.decode(Double.self, forKey: .peakEndMinutes)
        offsetEndMinutes = try c.decode(Double.self, forKey: .offsetEndMinutes)
        afterglowEndMinutes = try c.decodeIfPresent(Double.self, forKey: .afterglowEndMinutes)
        totalMinutes = try c.decode(Double.self, forKey: .totalMinutes)
        doseIntensity = try c.decodeIfPresent(Double.self, forKey: .doseIntensity) ?? 1.0
        doseMagnitude = try c.decodeIfPresent(Double.self, forKey: .doseMagnitude) ?? doseIntensity
        // Absent on an activity started by an older build: no marked region, which
        // is the same answer as a substance with no published heavy bound.
        heavyThresholdMagnitude = try c.decodeIfPresent(Double.self, forKey: .heavyThresholdMagnitude)
        tachyphylaxis = try c.decodeIfPresent(Double.self, forKey: .tachyphylaxis) ?? 0
        bodyWeightKg = try c.decodeIfPresent(Double.self, forKey: .bodyWeightKg) ?? PKModel.referenceBodyWeightKg
    }
}
