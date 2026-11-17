import Foundation

// MARK: - Display

extension ActiveSubstanceState {
    /// The name to show for this dose: the user's relabel of its canonical
    /// name, else the title the state was built with. The one path every
    /// surface takes, so none resolves the title back into a substance — a
    /// title can be an alias another substance also lists ("K").
    func displayLabel(customs: CustomSubstanceStore = .shared) -> String {
        customs.displayName(for: canonicalName, fallback: substanceName)
    }
}

// MARK: - ActiveSubstanceState Builders

extension ActiveSubstanceState {
    /// Build from a pre-resolved duration profile and basic dose info.
    init?(name: String, canonicalName: String? = nil, tint: P3Color, timestamp: Date, amount: Double, unit: String, routeDisplayName: String, duration: DurationProfile?, category: SubstanceCategory? = nil, doseIntensity: Double = 1.0, doseMagnitude: Double? = nil, heavyThresholdMagnitude: Double? = nil, doseIsUnscaled: Bool = false, tachyphylaxis: Double = 0, weightKg: Double = PKModel.referenceBodyWeightKg, zeroOrderKinetics: PKModel.ZeroOrderKinetics? = nil) {
        guard let rawDuration = duration else { return nil }
        // Endpoint-only data (a `total` with no come-up/peak/offset) would
        // otherwise collapse the curve to the onset length; synthesize the
        // missing shapers so it spans the real duration. No-op for complete
        // profiles. Curve-only — the detail card keeps the raw phases.
        let duration = category.map { rawDuration.fillingMissingPhases(for: $0) } ?? rawDuration
        let boundaries = duration.phaseBoundaries
        // Zero-order substances (alcohol) clear in a dose-scaled time, so the whole readout — phase
        // bar, phase-band coloring, now-line active window, "{elapsed} in · {remaining} left" — must
        // track the same kinetics the curve draws, not the fixed `DurationProfile`. Falls back to the
        // profile below when the dose can't be read as a mass or is too small to form a BAC peak.
        let zeroOrder = TimelineCurveModel.zeroOrderBoundaries(zeroOrderKinetics, amount: amount, unit: unit)
        self.init(
            substanceName: name,
            canonicalName: canonicalName,
            tint: tint,
            doseTimestamp: timestamp,
            amount: amount,
            unit: unit,
            route: routeDisplayName,
            onsetEndMinutes: zeroOrder?.onsetEnd ?? boundaries.onsetEnd,
            comeupEndMinutes: zeroOrder?.comeupEnd ?? boundaries.comeupEnd,
            peakEndMinutes: zeroOrder?.peakEnd ?? boundaries.peakEnd,
            offsetEndMinutes: zeroOrder?.offsetEnd ?? boundaries.offsetEnd,
            afterglowEndMinutes: zeroOrder != nil ? nil : (duration.afterglow != nil ? boundaries.afterglowEnd : nil),
            totalMinutes: zeroOrder?.total ?? duration.estimatedTotalMinutes,
            doseIntensity: doseIntensity,
            doseMagnitude: doseMagnitude,
            heavyThresholdMagnitude: heavyThresholdMagnitude,
            doseIsUnscaled: doseIsUnscaled,
            tachyphylaxis: tachyphylaxis,
            bodyWeightKg: weightKg,
            zeroOrder: zeroOrderKinetics,
            // Phase-range widths for the effect curve's spread-aware fit.
            // Synthesized phases are min == max, so they contribute zero
            // spread automatically. A zero-order dose draws no phase curve, so
            // its kinetic boundaries take none: a spread would move its end.
            comeupSpreadMinutes: zeroOrder != nil ? nil : duration.comeup.map { $0.max - $0.min },
            peakSpreadMinutes: zeroOrder != nil ? nil : duration.peak.map { $0.max - $0.min },
            offsetSpreadMinutes: zeroOrder != nil ? nil : duration.offset.map { $0.max - $0.min },
        )
    }

    /// Build from a dose entry by looking up substance duration data.
    ///
    /// **The curve means acute psychoactive effect, and nothing else.** A dose
    /// resolves one only from an ``Substance/timelineDuration(for:)`` — a real,
    /// sourced phase profile. That is the right source even when it disagrees
    /// with blood half-life (amphetamine's ~10 h t½ far outlasts its subjective
    /// effects). With no such profile the answer is `nil`, and the dose falls
    /// through to a timestamp marker.
    ///
    /// A half-life is deliberately **not** a fallback. It answers "how much is
    /// still in you", which is the ``ActiveSubstanceCalculator/compute(from:colorMap:)``
    /// body-load readout's question, not this one — and the two diverge hardest
    /// exactly where a fabricated curve does the most damage. Chronic medication
    /// is the whole population that reached the old synthesized tier: SSRIs,
    /// antipsychotics, anticonvulsants, thyroid, therapeutic peptides. None has
    /// an acute curve to draw, and deriving one from t½ drew a flat multi-week
    /// plateau over every real curve on the graph (fluoxetine's 16-day t½ → a
    /// 69-day "effect", `1,638h left`). The tier's stated beneficiaries
    /// (Memantine, Tadalafil, Bromantane) have all since gained real duration
    /// data and resolve above, so it had no honest users left.
    ///
    /// A substance that genuinely does have acute effects but renders as a bare
    /// marker is a **data** gap — fix it by adding durations in the pipeline, not
    /// by inferring a shape from elimination kinetics. Note the pharmacology-blind
    /// counterpart: ``DoseEntry/isBackgroundMed`` lets the user mute a dose that
    /// *does* have a curve (a daily-med amphetamine), filtered in
    /// ``TimelineWindowModel``.
    ///
    /// `weightKg` is the body weight of the person who took the dose; `nil`
    /// reads the active profile's.
    static func from(entry: DoseEntry, tint: P3Color, weightKg: Double? = nil) -> ActiveSubstanceState? {
        // A dose of unknown amount has no intensity to draw; it lands as a
        // timestamp marker. This one guard is what keeps it out of Active Now,
        // the Live Activity, the timeline curves, and the session effect models.
        if entry.isUnknownDose { return nil }
        // Timeline path: the lightweight batch row carries everything used below
        // (category, dose-ranges, durations, half-life, aliases) without the
        // heavy per-substance chem/mechanism SQL. Falls back to the full lookup
        // when the batch cache is cold or the substance is custom-only.
        guard let substance = SubstanceLibrary.lookup(entry.substance) else { return nil }
        // A depot administration (an injectable ester; a formulation flagged depot)
        // releases over days-to-weeks and has no acute psychoactive curve — the same
        // reasoning as an unmodeled form below, so it shows as a bare marker rather
        // than borrowing the parent's acute profile (estradiol's IM curve for an
        // Estradiol Valerate depot). The Injection Levels tool models its serum
        // curve; the body-load readout uses its depot half-life (PKResolver).
        if PKResolver.isDepot(entry: entry) { return nil }
        // An extended-release product we model per-product ("Concerta", "Adderall
        // XR") draws ITS authored envelope — the whole point of the product-duration
        // table — even though its release form is otherwise unmodeled.
        let productDuration = entry.productDuration
        // Otherwise a dose that names a form we don't model draws no curve at all.
        // Both fallbacks below would answer with the *base* form's kinetics: a
        // Concerta dose would take Ritalin's 150–240 min profile, and an OxyContin
        // dose oxycodone's ~4 h — the exact number that invites a redose. We know
        // the form and we know we can't model it, so we say when it was taken and
        // stop there. This must precede both tiers; see `namesUnmodeledForm`.
        if productDuration == nil, entry.namesUnmodeledForm { return nil }
        let ladder = substance.scalingLadder(for: entry.route)
        let dose = substance.quantity(of: entry)
        let intensity = Self.computeDoseIntensity(dose: dose, ladder: ladder)
        let magnitude = Self.computeDoseMagnitude(dose: dose, ladder: ladder)
        let isUnscaled = Self.heavyFraction(of: dose, on: ladder) == nil
        let weightKg = weightKg ?? UserProfileStore.shared.effectiveWeightKg
        // Prefer the product envelope; else the form actually logged — a D-isomer
        // dose must not be drawn with the racemic curve the detail card wouldn't show.
        if let duration = entry.applyingMeal(to: productDuration ?? substance.timelineDuration(
            for: entry.route, saltForm: entry.saltForm, isomer: entry.isomer,
        )) {
            return ActiveSubstanceState(
                // Canonical common name, so a dose logged under an alias (e.g. "Lysergic Acid
                // Diethylamide") labels its curve "LSD" like the rest of the app.
                name: substance.displayTitle,
                canonicalName: substance.name,
                tint: tint,
                timestamp: entry.timestamp,
                amount: entry.amount,
                unit: entry.unit,
                routeDisplayName: entry.route.displayName,
                duration: duration,
                category: substance.category,
                doseIntensity: intensity,
                doseMagnitude: magnitude,
                // No heavy band over a curve whose height says nothing about the dose.
                heavyThresholdMagnitude: isUnscaled ? nil : Self.heavyThresholdMagnitude(for: ladder?.range),
                doseIsUnscaled: isUnscaled,
                tachyphylaxis: substance.category.acuteToleranceFactor,
                weightKg: weightKg,
                zeroOrderKinetics: SubstanceStore.shared.zeroOrderKinetics(
                    forSubstanceName: substance.name, weightKg: weightKg,
                ),
            )
        }
        return nil
    }

    /// Resolve a half-life (minutes) for a duration-less dose, through the shared ``PKResolver``.
    static func resolveHalfLifeMinutes(substance: Substance, name _: String) -> Double? {
        PKResolver.halfLifeMinutes(substance: substance)
    }

    /// Convert dose entries into the two inputs ``TimelineGraphView`` consumes:
    /// `states` (doses that resolve duration data, drawn as curves) and
    /// `markers` (the duration-less remainder, drawn as timestamp diamonds).
    /// Single source of truth shared by the day detail and the journal cards.
    static func timeline(
        for entries: [DoseEntry],
        colors: [SubstanceColor],
    ) -> (states: [ActiveSubstanceState], markers: [DoseMarker]) {
        let tintMap = colors.tintMap
        return timeline(for: entries) { SubstancePalette.tint(for: $0.substance, tintMap: tintMap) }
    }

    /// ``timeline(for:colors:)`` with each dose's tint chosen by `tint`, for
    /// `weightKg`'s body (`nil`: the active profile's). A shared session draws
    /// another person's doses this way, in their colors and on their weight.
    static func timeline(
        for entries: [DoseEntry],
        weightKg: Double? = nil,
        tint: (DoseEntry) -> P3Color,
    ) -> (states: [ActiveSubstanceState], markers: [DoseMarker]) {
        var states: [ActiveSubstanceState] = []
        var markers: [DoseMarker] = []
        for entry in entries {
            let tint = tint(entry)
            if let state = from(entry: entry, tint: tint, weightKg: weightKg) {
                states.append(state)
                continue
            }
            // A dose with no curve normally still lands as a timestamp marker — but
            // a supplement without an acute profile (Vitamin D3, magnesium) has no
            // duration *or* effect to honestly plot, so it stays off the effect
            // graph entirely (it remains in the entries list and the info card). A
            // non-supplement with no data still gets its marker.
            let substance = SubstanceLibrary.lookup(entry.substance)
            if substance?.category == .supplement { continue }
            markers.append(DoseMarker(
                // Canonical name so the marker's label and its lane matching agree with the curves.
                substanceName: substance?.displayTitle ?? entry.substance,
                timestamp: entry.timestamp,
                tint: tint,
                amount: entry.amount,
                unit: entry.unit,
            ))
        }
        return (states, markers)
    }

    /// Compute dose intensity (0.05...1.0) used to scale timeline curve heights.
    ///
    /// Uses `amount / heavy_threshold` directly — matches PsychonautWiki's
    /// visual behavior: 17g alcohol renders at half the height of 34g, plat-1
    /// DXM (150mg / 700mg heavy ≈ 0.21) renders much shorter than 75g alcohol
    /// (75 / 40 = 1.0 saturated). The ratio naturally captures within-substance
    /// proportionality while the `min(1.0, …)` cap handles overdose cases.
    ///
    /// Falls back to looser references (strong upper, common upper × 1.5, etc.)
    /// when heavy isn't defined, so substances with partial data still produce
    /// a sensible scale. Returns a neutral 0.60 (mid-common-ish) when no dose
    /// range information is available at all — we'd rather show "unknown" as
    /// a moderate curve than peg it at the top of the graph where it would
    /// wrongly dominate every other dose.
    static let unknownIntensity: Double = 0.60

    /// Floor height so sub-threshold doses still show a visible nub rather
    /// than disappearing.
    static let minimumIntensity: Double = 0.05

    static func computeDoseIntensity(dose: DoseQuantity?, ladder: DoseLadder?) -> Double {
        min(1.0, computeDoseMagnitude(dose: dose, ladder: ladder))
    }

    /// The **unclamped** dose magnitude — `amount / heavy_threshold` with no 1.0
    /// cap. Single source for the timeline's dose-superposition: stacked doses
    /// sum their magnitudes and a single combined dose of the same total lands
    /// identically, so the merged curve passes one Hill link and
    /// `4×20 mg ≡ 1×80 mg`. Still floored at ``minimumIntensity`` so a
    /// sub-threshold dose keeps a visible nub. Falls back to ``unknownIntensity``
    /// when no dose-range reference exists (mirrors ``computeDoseIntensity``).
    static func computeDoseMagnitude(dose: DoseQuantity?, ladder: DoseLadder?) -> Double {
        heavyFraction(of: dose, on: ladder).map { max(minimumIntensity, $0) } ?? unknownIntensity
    }

    /// `dose ÷ heavy reference`, or `nil` when the ladder has no reference or the
    /// dose can't be expressed in the ladder's unit. A dose in a unit the ladder
    /// can't read is *unknown*, never small: reading 0.02 g of heroin as 0.02 on a
    /// mg ladder floors it to ``minimumIntensity``, which the interaction checker
    /// takes as confidently trivial and suppresses the warning.
    private static func heavyFraction(of dose: DoseQuantity?, on ladder: DoseLadder?) -> Double? {
        guard let dose, let ladder, let reference = heavyReference(for: ladder.range) else { return nil }
        return ladder.fraction(of: dose, reference: reference)
    }

    /// Where a **published** heavy bound sits on the magnitude scale, or `nil`
    /// when the ladder has none.
    ///
    /// The distinction ``heavyReference(for:)`` deliberately erases — it will
    /// improvise a denominator from `strong.upperBound`, `common × 1.5`, even
    /// `threshold × 10`, because a curve needs *a* height and any monotone
    /// reference gives an honest ordering. A marked region on the graph is a
    /// different kind of claim: it names a line, so it may only be drawn where
    /// a source actually drew one. When `heavy` is present it is the
    /// denominator, which puts the threshold at exactly `1.0`.
    static func heavyThresholdMagnitude(for doseRange: DoseRange?) -> Double? {
        guard let heavy = doseRange?.heavy, heavy > 0 else { return nil }
        return 1.0
    }

    /// Resolve the "heavy" reference dose used as the denominator for both
    /// intensity and magnitude, with looser fallbacks (strong upper, common
    /// upper × 1.5, …) when `heavy` isn't defined. `nil` when nothing is
    /// populated, so callers can substitute ``unknownIntensity``.
    private static func heavyReference(for doseRange: DoseRange?) -> Double? {
        guard let range = doseRange else { return nil }
        if let heavy = range.heavy, heavy > 0 { return heavy }
        if let strong = range.strong, strong.upperBound > 0 { return strong.upperBound }
        // Approximate a heavy threshold when only common is defined.
        if let common = range.common, common.upperBound > 0 { return common.upperBound * 1.5 }
        if let light = range.light, light.upperBound > 0 { return light.upperBound * 3 }
        if let threshold = range.threshold, threshold > 0 { return threshold * 10 }
        return nil
    }
}
