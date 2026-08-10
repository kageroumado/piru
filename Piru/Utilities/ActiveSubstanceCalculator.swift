import SwiftUI

// MARK: - Active Substance Model

struct ActiveSubstance: Identifiable {
    let name: String
    let unit: String
    let color: Color
    let halfLifeMinutes: Double
    let totalDosed: Double
    let totalRemaining: Double
    let doses: [DoseInfo]

    /// Identity carries the unit: a substance logged in both mL and mg yields two
    /// rows (they are not addable), and `ForEach` needs them to differ.
    var id: String {
        "\(name)|\(unit)"
    }
    var eliminatedFraction: Double {
        1 - totalRemaining / totalDosed
    }

    struct DoseInfo: Identifiable {
        let id = UUID()
        let amount: Double
        let remaining: Double
        let timestamp: Date
    }
}

// MARK: - Calculator

enum ActiveSubstanceCalculator {
    /// Computes currently active substances from dose history using one-compartment PK model.
    static func compute(from entries: [DoseEntry], colorMap: [String: Color]) -> [ActiveSubstance] {
        let now = Date.now

        // Batch lookups: cache substance resolution so each unique name is looked up once
        var substanceCache: [String: Substance?] = [:]
        func cachedLookup(_ name: String) -> Substance? {
            let key = name.lowercased()
            if let cached = substanceCache[key] { return cached }
            let result = SubstanceLibrary.timelineLookup(name)
            substanceCache[key] = result
            return result
        }

        // Resolve half-life with fallback: substance model -> HalfLifeDatabase by name -> HalfLifeDatabase by aliases
        var halfLifeCache: [String: Double] = [:]
        func resolveHalfLife(substance: Substance?, entryName: String) -> Double? {
            let key = entryName.lowercased()
            if let cached = halfLifeCache[key] { return cached }
            if let hl = substance?.halfLifeMinutes, hl > 0 { halfLifeCache[key] = hl; return hl }
            if let hl = HalfLifeDatabase.halfLife(for: entryName), hl > 0 { halfLifeCache[key] = hl; return hl }
            if let substance {
                for alias in substance.aliases {
                    if let hl = HalfLifeDatabase.halfLife(for: alias), hl > 0 { halfLifeCache[key] = hl; return hl }
                }
            }
            return nil
        }

        var grouped: [String: (name: String, unit: String, halfLife: Double, doses: [ActiveSubstance.DoseInfo], totalDosed: Double, totalRemaining: Double)] = [:]
        /// Group key must carry the unit family, not just the name. Two doses of
        /// the same substance in µg/mg/g are one group (converted into whichever
        /// unit arrived first); a dose in mL or IU is a *different* quantity and
        /// gets its own group rather than being summed into a mass total.
        func unitFamily(_ unit: String) -> String {
            DoseUnit.convert(1, from: unit, to: "mg") == nil ? unit : "mass"
        }

        for entry in entries {
            let substance = cachedLookup(entry.substance)
            // Supplements/vitamins clear over days-to-weeks, so a body-load readout
            // for them ("0% eliminated · clear in 5 months") is noise, not session
            // insight. Excluded here to match their suppression on the timeline and
            // in the entry-row rail (see `from`).
            if substance?.category == .supplement { continue }
            // A dose naming a form we don't model contributes no body-load estimate
            // either. The elimination half-life *is* a property of the molecule and
            // survives the delivery matrix — but the readout is not pure
            // elimination: `ka` below comes from the route's duration profile, i.e.
            // the immediate-release absorption limb, so a dose released over ~10 h
            // would be modelled as if it landed at once, and "clear ~12:33 PM"
            // states a time we have no basis for. Better to show nothing than
            // something misleading.
            // A per-product envelope (Concerta, Adderall XR) models the extended
            // release, so its dose contributes a body-load estimate with the right
            // absorption limb — unlike a bare unmodeled form, which we still skip.
            let productDuration = entry.productDuration
            if productDuration == nil, entry.namesUnmodeledForm { continue }
            guard let halfLife = resolveHalfLife(substance: substance, entryName: entry.substance) else { continue }

            let elapsed = now.timeIntervalSince(entry.timestamp) / 60
            guard elapsed >= 0 else { continue }

            let ke = PKModel.ke(fromHalfLifeMinutes: halfLife)
            let ka: Double
            if let duration = productDuration ?? substance?.resolveDuration(
                for: entry.route, saltForm: entry.saltForm, isomer: entry.isomer,
            ) {
                let ttp = (duration.onset?.midpoint ?? 0) + (duration.comeup?.midpoint ?? 0)
                ka = ttp > 0 ? PKModel.estimateKa(timeToPeak: ttp, ke: ke) : PKModel.defaultKa(ke: ke)
            } else {
                ka = PKModel.defaultKa(ke: ke)
            }
            let remaining = entry.amount * PKModel.fractionRemainingInBody(at: elapsed, ke: ke, ka: ka)
            let fraction = remaining / entry.amount

            guard fraction > 0.03 else { continue }

            let name = substance?.name ?? entry.substance
            let key = "\(name)|\(unitFamily(entry.unit))"

            if var existing = grouped[key] {
                // Express this dose in the group's established unit. Same family
                // by construction, so the conversion cannot fail; the fallback
                // keeps it honest rather than silently mixing scales.
                let amount = DoseUnit.convert(entry.amount, from: entry.unit, to: existing.unit) ?? entry.amount
                let converted = DoseUnit.convert(remaining, from: entry.unit, to: existing.unit) ?? remaining
                existing.doses.append(ActiveSubstance.DoseInfo(
                    amount: amount,
                    remaining: converted,
                    timestamp: entry.timestamp,
                ))
                existing.totalDosed += amount
                existing.totalRemaining += converted
                grouped[key] = existing
            } else {
                grouped[key] = (
                    name: name,
                    // The unit the user actually logged. Taking it from the
                    // library's `defaultUnit` instead printed "7.2 mg" under two
                    // 3.6 g doses of gabapentin — right number, wrong suffix.
                    unit: entry.unit,
                    halfLife: halfLife,
                    doses: [ActiveSubstance.DoseInfo(
                        amount: entry.amount,
                        remaining: remaining,
                        timestamp: entry.timestamp,
                    )],
                    totalDosed: entry.amount,
                    totalRemaining: remaining,
                )
            }
        }

        return grouped.map { _, info in
            let color = colorMap[info.name.lowercased()] ?? Theme.accent
            return ActiveSubstance(
                name: info.name,
                unit: info.unit,
                color: color,
                halfLifeMinutes: info.halfLife,
                totalDosed: info.totalDosed,
                totalRemaining: info.totalRemaining,
                doses: info.doses.sorted { $0.timestamp > $1.timestamp },
            )
        }
        .sorted { $0.eliminatedFraction < $1.eliminatedFraction }
    }
}

// MARK: - ActiveSubstanceState Builders

extension ActiveSubstanceState {
    /// Build from a pre-resolved duration profile and basic dose info.
    init?(name: String, colorHex: String, timestamp: Date, amount: Double, unit: String, routeDisplayName: String, duration: DurationProfile?, category: SubstanceCategory? = nil, doseIntensity: Double = 1.0, doseMagnitude: Double? = nil, heavyThresholdMagnitude: Double? = nil, tachyphylaxis: Double = 0, weightKg: Double = PKModel.referenceBodyWeightKg) {
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
        let zeroOrder = TimelineCurveModel.zeroOrderBoundaries(substanceName: name, amount: amount, unit: unit, weightKg: weightKg)
        self.init(
            substanceName: name,
            colorHex: colorHex,
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
            tachyphylaxis: tachyphylaxis,
            bodyWeightKg: weightKg,
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
    static func from(entry: DoseEntry, colorHex: String) -> ActiveSubstanceState? {
        // Timeline path: the lightweight batch row carries everything used below
        // (category, dose-ranges, durations, half-life, aliases) without the
        // heavy per-substance chem/mechanism SQL. Falls back to the full lookup
        // when the batch cache is cold or the substance is custom-only.
        guard let substance = SubstanceLibrary.timelineLookup(entry.substance) else { return nil }
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
        let doseRange = Self.resolveDoseRange(substance: substance, route: entry.route)
        let intensity = Self.computeDoseIntensity(amount: entry.amount, doseRange: doseRange)
        let magnitude = Self.computeDoseMagnitude(amount: entry.amount, doseRange: doseRange)
        // Prefer the product envelope; else the form actually logged — a D-isomer
        // dose must not be drawn with the racemic curve the detail card wouldn't show.
        if let duration = productDuration ?? substance.timelineDuration(
            for: entry.route, saltForm: entry.saltForm, isomer: entry.isomer,
        ) {
            return ActiveSubstanceState(
                // Canonical common name, so a dose logged under an alias (e.g. "Lysergic Acid
                // Diethylamide") labels its curve "LSD" like the rest of the app.
                name: substance.displayTitle,
                colorHex: colorHex,
                timestamp: entry.timestamp,
                amount: entry.amount,
                unit: entry.unit,
                routeDisplayName: entry.route.displayName,
                duration: duration,
                category: substance.category,
                doseIntensity: intensity,
                doseMagnitude: magnitude,
                heavyThresholdMagnitude: Self.heavyThresholdMagnitude(for: doseRange),
                tachyphylaxis: substance.category.acuteToleranceFactor,
                weightKg: UserProfileStore.shared.effectiveWeightKg,
            )
        }
        return nil
    }

    /// Resolve a half-life (minutes) for a duration-less dose, mirroring
    /// ``compute(from:colorMap:)``'s fallback: substance model → HalfLifeDatabase
    /// by name → by alias.
    static func resolveHalfLifeMinutes(substance: Substance, name: String) -> Double? {
        if let hl = substance.halfLifeMinutes, hl > 0 { return hl }
        if let hl = HalfLifeDatabase.halfLife(for: name), hl > 0 { return hl }
        for alias in substance.aliases {
            if let hl = HalfLifeDatabase.halfLife(for: alias), hl > 0 { return hl }
        }
        return nil
    }

    /// Convert dose entries into the two inputs ``TimelineGraphView`` consumes:
    /// `states` (doses that resolve duration data, drawn as curves) and
    /// `markers` (the duration-less remainder, drawn as timestamp diamonds).
    /// Single source of truth shared by the day detail and the journal cards.
    static func timeline(
        for entries: [DoseEntry],
        colors: [SubstanceColor],
    ) -> (states: [ActiveSubstanceState], markers: [DoseMarker]) {
        let hexMap = colors.hexColorMap
        var states: [ActiveSubstanceState] = []
        var markers: [DoseMarker] = []
        for entry in entries {
            let hex = SubstancePalette.hex(for: entry.substance, hexMap: hexMap)
            if let state = from(entry: entry, colorHex: hex) {
                states.append(state)
                continue
            }
            // A dose with no curve normally still lands as a timestamp marker — but
            // a supplement without an acute profile (Vitamin D3, magnesium) has no
            // duration *or* effect to honestly plot, so it stays off the effect
            // graph entirely (it remains in the entries list and the info card). A
            // non-supplement with no data still gets its marker.
            let substance = SubstanceLibrary.timelineLookup(entry.substance)
            if substance?.category == .supplement { continue }
            markers.append(DoseMarker(
                // Canonical name so the marker's label and its lane matching agree with the curves.
                substanceName: substance?.displayTitle ?? entry.substance,
                timestamp: entry.timestamp,
                colorHex: hex,
                amount: entry.amount,
                unit: entry.unit,
            ))
        }
        return (states, markers)
    }

    /// Fall back to the substance's default route (then any populated route)
    /// when the requested route has no DoseRange. Without this, a user logging
    /// a non-default route (e.g. insufflated when the library only has oral
    /// data) gets `doseIntensity = 1.0`, which makes every such dose render at
    /// full graph height regardless of magnitude — collapsing the visual
    /// distinction between light/common/heavy across the journal.
    static func resolveDoseRange(substance: Substance, route: RouteOfAdministration) -> DoseRange? {
        if let exact = substance.doseRange(for: route), hasAnyLevel(exact) { return exact }
        if let def = substance.doseRange(for: substance.defaultRoute), hasAnyLevel(def) { return def }
        return substance.routes.first { hasAnyLevel($0.doses) }?.doses
    }

    /// `true` when at least one dose-level bound is populated.
    private static func hasAnyLevel(_ range: DoseRange) -> Bool {
        range.threshold != nil || range.light != nil || range.common != nil
            || range.strong != nil || range.heavy != nil
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

    static func computeDoseIntensity(amount: Double, doseRange: DoseRange?) -> Double {
        guard let reference = heavyReference(for: doseRange) else { return unknownIntensity }
        return min(1.0, max(minimumIntensity, amount / reference))
    }

    /// The **unclamped** dose magnitude — `amount / heavy_threshold` with no 1.0
    /// cap. Single source for the timeline's dose-superposition: stacked doses
    /// sum their magnitudes and a single combined dose of the same total lands
    /// identically, so the merged curve passes one Hill link and
    /// `4×20 mg ≡ 1×80 mg`. Still floored at ``minimumIntensity`` so a
    /// sub-threshold dose keeps a visible nub. Falls back to ``unknownIntensity``
    /// when no dose-range reference exists (mirrors ``computeDoseIntensity``).
    static func computeDoseMagnitude(amount: Double, doseRange: DoseRange?) -> Double {
        guard let reference = heavyReference(for: doseRange) else { return unknownIntensity }
        return max(minimumIntensity, amount / reference)
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
