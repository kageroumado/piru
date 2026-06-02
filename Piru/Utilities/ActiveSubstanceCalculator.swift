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

    var id: String {
        name
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
            let result = SubstanceLibrary.lookupByNameOrAlias(name)
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

        for entry in entries {
            let substance = cachedLookup(entry.substance)
            guard let halfLife = resolveHalfLife(substance: substance, entryName: entry.substance) else { continue }

            let elapsed = now.timeIntervalSince(entry.timestamp) / 60
            guard elapsed >= 0 else { continue }

            let ke = PKModel.ke(fromHalfLifeMinutes: halfLife)
            let ka: Double
            if let sub = substance,
               let duration = sub.resolveDuration(for: entry.route) {
                let ttp = (duration.onset?.midpoint ?? 0) + (duration.comeup?.midpoint ?? 0)
                ka = ttp > 0 ? PKModel.estimateKa(timeToPeak: ttp, ke: ke) : PKModel.defaultKa(ke: ke)
            } else {
                ka = PKModel.defaultKa(ke: ke)
            }
            let remaining = entry.amount * PKModel.fractionRemainingInBody(at: elapsed, ke: ke, ka: ka)
            let fraction = remaining / entry.amount

            guard fraction > 0.03 else { continue }

            let doseInfo = ActiveSubstance.DoseInfo(
                amount: entry.amount,
                remaining: remaining,
                timestamp: entry.timestamp,
            )

            let key = substance?.name ?? entry.substance
            if var existing = grouped[key] {
                existing.doses.append(doseInfo)
                existing.totalDosed += entry.amount
                existing.totalRemaining += remaining
                grouped[key] = existing
            } else {
                grouped[key] = (
                    name: key,
                    unit: substance?.defaultUnit ?? "mg",
                    halfLife: halfLife,
                    doses: [doseInfo],
                    totalDosed: entry.amount,
                    totalRemaining: remaining,
                )
            }
        }

        return grouped.map { name, info in
            let color = colorMap[name.lowercased()] ?? Theme.accent
            return ActiveSubstance(
                name: name,
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
    init?(name: String, colorHex: String, timestamp: Date, amount: Double, unit: String, routeDisplayName: String, duration: DurationProfile?, doseIntensity: Double = 1.0, tachyphylaxis: Double = 0) {
        guard let duration else { return nil }
        let boundaries = duration.phaseBoundaries
        self.init(
            substanceName: name,
            colorHex: colorHex,
            doseTimestamp: timestamp,
            amount: amount,
            unit: unit,
            route: routeDisplayName,
            onsetEndMinutes: boundaries.onsetEnd,
            comeupEndMinutes: boundaries.comeupEnd,
            peakEndMinutes: boundaries.peakEnd,
            offsetEndMinutes: boundaries.offsetEnd,
            afterglowEndMinutes: duration.afterglow != nil ? boundaries.afterglowEnd : nil,
            totalMinutes: duration.estimatedTotalMinutes,
            doseIntensity: doseIntensity,
            tachyphylaxis: tachyphylaxis,
        )
    }

    /// Synthesize a state for a dose that has **no acute duration profile** but
    /// a known half-life, so it still renders as a plausible effect curve.
    ///
    /// `TimelineGraphView` now draws a phase-based effect curve, so we fabricate
    /// onset/come-up/peak/offset boundaries scaled around a realistic absorption
    /// `peakCenter` (a few hours, never tied to the half-life — a long-acting drug
    /// still absorbs quickly). `totalMinutes` is derived from the half-life
    /// (`ln(20)/ke` past the peak) so a longer half-life stretches the offset.
    init(synthesizedForName name: String, colorHex: String, timestamp: Date, amount: Double, unit: String, routeDisplayName: String, halfLifeMinutes: Double, doseIntensity: Double) {
        let ke = log(2) / halfLifeMinutes
        let peakCenter = min(max(halfLifeMinutes * 0.15, 20), 180)
        let total = peakCenter + log(20) / ke
        self.init(
            substanceName: name,
            colorHex: colorHex,
            doseTimestamp: timestamp,
            amount: amount,
            unit: unit,
            route: routeDisplayName,
            onsetEndMinutes: peakCenter * 0.4,
            comeupEndMinutes: peakCenter * 0.8,
            peakEndMinutes: peakCenter * 1.2,
            offsetEndMinutes: total * 0.92,
            afterglowEndMinutes: nil,
            totalMinutes: total,
            doseIntensity: doseIntensity,
        )
    }

    /// Build from a dose entry by looking up substance duration data.
    ///
    /// Resolution order:
    /// 1. **Acute subjective duration** → curve fit to the phase profile. This
    ///    is the right source even when it disagrees with blood half-life
    ///    (amphetamine's ~10 h t½ far outlasts its subjective effects).
    /// 2. **No acute duration but a known half-life** → a synthesized
    ///    half-life-driven curve, so long-acting / maintenance compounds
    ///    (Memantine, Tadalafil, Bromantane) render as a real — if long —
    ///    curve instead of a bare dot. The graph's tail-cutting frames the
    ///    active part and leaves the slow tail one pan away.
    /// 3. **Neither** → `nil`, so the dose falls through to a timestamp marker.
    static func from(entry: DoseEntry, colorHex: String) -> ActiveSubstanceState? {
        guard let substance = SubstanceLibrary.lookupByNameOrAlias(entry.substance) else { return nil }
        let intensity = Self.computeDoseIntensity(
            amount: entry.amount,
            doseRange: Self.resolveDoseRange(substance: substance, route: entry.route),
        )
        if let duration = substance.timelineDuration(for: entry.route) {
            return ActiveSubstanceState(
                name: entry.substance,
                colorHex: colorHex,
                timestamp: entry.timestamp,
                amount: entry.amount,
                unit: entry.unit,
                routeDisplayName: entry.route.displayName,
                duration: duration,
                doseIntensity: intensity,
                tachyphylaxis: substance.category.acuteToleranceFactor,
            )
        }
        if let halfLife = Self.resolveHalfLifeMinutes(substance: substance, name: entry.substance) {
            return ActiveSubstanceState(
                synthesizedForName: entry.substance,
                colorHex: colorHex,
                timestamp: entry.timestamp,
                amount: entry.amount,
                unit: entry.unit,
                routeDisplayName: entry.route.displayName,
                halfLifeMinutes: halfLife,
                doseIntensity: intensity,
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
            } else {
                markers.append(DoseMarker(
                    substanceName: entry.substance,
                    timestamp: entry.timestamp,
                    colorHex: hex,
                    amount: entry.amount,
                    unit: entry.unit,
                ))
            }
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
        guard let range = doseRange else { return unknownIntensity }

        let reference: Double
        if let heavy = range.heavy, heavy > 0 {
            reference = heavy
        } else if let strong = range.strong, strong.upperBound > 0 {
            reference = strong.upperBound
        } else if let common = range.common, common.upperBound > 0 {
            // Approximate a heavy threshold when only common is defined.
            reference = common.upperBound * 1.5
        } else if let light = range.light, light.upperBound > 0 {
            reference = light.upperBound * 3
        } else if let threshold = range.threshold, threshold > 0 {
            reference = threshold * 10
        } else {
            return unknownIntensity
        }
        return min(1.0, max(minimumIntensity, amount / reference))
    }
}
