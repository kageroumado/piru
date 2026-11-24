import SwiftUI

// MARK: - Active Substance Model

struct ActiveSubstance: Identifiable {
    let name: String
    let unit: String
    /// A quantity in ``unit``, for converting ``totalRemaining`` to another unit of its family.
    let unitOf: DoseQuantity
    let color: Color
    let halfLifeMinutes: Double
    let totalDosed: Double
    let totalRemaining: Double
    let doses: [DoseInfo]
    /// When the last of these doses falls below ``ActiveSubstanceCalculator/activeFloor``
    /// of its amount, leaving the substance off the active list if nothing else is
    /// logged; `nil` when the model gives no time.
    let activeUntil: Date?

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
    /// The share of a dose still in the body below which the dose no longer counts as active.
    static let activeFloor = 0.03

    /// Computes the active substances at `now` (default: the present) from dose
    /// history using a one-compartment PK model. Parameterizing `now` is what
    /// lets a body-load readout be produced for any past — or projected future —
    /// date, which the Insights "in your body over time" graph samples across a
    /// day grid. Only doses at or before `now` contribute (causality).
    static func compute(
        from entries: [DoseEntry],
        colorMap: [String: Color],
        now: Date = .now,
    ) -> [ActiveSubstance] {
        // Batch lookups: cache substance resolution so each unique name is looked up once
        var substanceCache: [String: Substance?] = [:]
        func cachedLookup(_ name: String) -> Substance? {
            let key = name.lowercased()
            if let cached = substanceCache[key] { return cached }
            let result = SubstanceLibrary.lookup(name)
            substanceCache[key] = result
            return result
        }

        // Half-life resolution goes through the shared `PKResolver`; the local cache just
        // avoids re-resolving the same name across a long dose log. Depot doses bypass
        // the cache (their half-life depends on the ester on the entry, not just the
        // name) and the acute duration below, so they read as a slow depot decay.
        var halfLifeCache: [String: Double] = [:]
        func resolveHalfLife(substance: Substance?, entry: DoseEntry, isDepot: Bool) -> Double? {
            if let depot = PKResolver.depotHalfLifeMinutes(entry: entry, isDepot: isDepot) { return depot }
            let key = entry.substance.lowercased()
            if let cached = halfLifeCache[key] { return cached }
            guard let hl = PKResolver.halfLifeMinutes(substance: substance) else { return nil }
            halfLifeCache[key] = hl
            return hl
        }

        // The group key carries the unit family, not just the name. Two doses of
        // the same substance in µg/mg/g are one group (converted into whichever
        // unit arrived first); a dose in mL or IU is a *different* quantity and
        // gets its own group rather than being summed into a mass total.
        struct GroupKey: Hashable {
            let name: String
            let family: DoseQuantity.Family
        }
        var grouped: [GroupKey: (name: String, unit: String, unitOf: DoseQuantity, halfLife: Double, doses: [ActiveSubstance.DoseInfo], totalDosed: Double, totalRemaining: Double, activeUntil: Date?)] = [:]

        for entry in entries {
            let substance = cachedLookup(entry.substance)
            // Supplements/vitamins clear over days-to-weeks, so a body-load readout
            // for them ("0% eliminated · clear in 5 months") is noise, not session
            // insight. Excluded here to match their suppression on the timeline and
            // in the entry-row rail (see `from`).
            if substance?.modelsBodyLoad == false { continue }
            // No amount, no body load: 0 remaining of 0 dosed is not a fraction.
            guard let dose = substance?.quantity(of: entry) ?? entry.quantity else { continue }
            let productDuration = entry.productDuration
            let isDepot = PKResolver.isDepot(entry: entry)
            // A dose naming a form we don't model gets no body-load estimate: `ka`
            // comes from the route's immediate-release absorption limb, so an
            // extended-release dose would be modeled as landing at once and its
            // clear time would have no basis. A per-product envelope (Concerta,
            // Adderall XR) models the release, so that dose counts. A depot counts
            // too: it has no acute form, and its slow persistence is what a
            // body-load readout is for.
            if !isDepot, productDuration == nil, entry.namesUnmodeledForm { continue }
            guard let halfLife = resolveHalfLife(substance: substance, entry: entry, isDepot: isDepot) else { continue }

            let elapsed = now.timeIntervalSince(entry.timestamp) / 60
            guard elapsed >= 0 else { continue }

            // The product envelope wins the absorption limb; otherwise the
            // route/salt/isomer-specific profile. A depot has no acute absorption
            // limb — its slow release IS the rate — so it takes the default `ka`
            // proportional to its (long) `ke`, giving a slow-rise, slow-fall shape.
            let (ke, ka) = PKResolver.rateConstants(
                halfLifeMinutes: halfLife,
                duration: isDepot ? nil : entry.applyingMeal(to: productDuration ?? substance?.resolveDuration(
                    for: entry.route, saltForm: entry.saltForm, isomer: entry.isomer,
                )),
            )
            let remaining = entry.amount * PKModel.fractionRemainingInBody(at: elapsed, ke: ke, ka: ka)
            let fraction = remaining / entry.amount

            guard fraction > activeFloor else { continue }
            let activeUntil = PKModel.minutesUntilRemaining(activeFloor, ke: ke, ka: ka)
                .map { entry.timestamp.addingTimeInterval($0 * 60) }

            let name = substance?.name ?? entry.substance
            let key = GroupKey(name: name, family: dose.family)

            if var existing = grouped[key] {
                // Express this dose in the group's established unit; the key's
                // family guarantees the two convert.
                guard let amount = dose.value(inUnitOf: existing.unitOf) else { continue }
                let converted = amount * fraction
                existing.doses.append(ActiveSubstance.DoseInfo(
                    amount: amount,
                    remaining: converted,
                    timestamp: entry.timestamp,
                ))
                existing.totalDosed += amount
                existing.totalRemaining += converted
                existing.activeUntil = [existing.activeUntil, activeUntil].compactMap(\.self).max()
                grouped[key] = existing
            } else {
                grouped[key] = (
                    name: name,
                    // The unit the user actually logged. Taking it from the
                    // library's `defaultUnit` instead printed "7.2 mg" under two
                    // 3.6 g doses of gabapentin — right number, wrong suffix.
                    unit: entry.unit,
                    unitOf: dose,
                    halfLife: halfLife,
                    doses: [ActiveSubstance.DoseInfo(
                        amount: entry.amount,
                        remaining: remaining,
                        timestamp: entry.timestamp,
                    )],
                    totalDosed: entry.amount,
                    totalRemaining: remaining,
                    activeUntil: activeUntil,
                )
            }
        }

        return grouped.map { _, info in
            let color = colorMap[info.name.lowercased()] ?? Theme.accent
            return ActiveSubstance(
                name: info.name,
                unit: info.unit,
                unitOf: info.unitOf,
                color: color,
                halfLifeMinutes: info.halfLife,
                totalDosed: info.totalDosed,
                totalRemaining: info.totalRemaining,
                doses: info.doses.sorted { $0.timestamp > $1.timestamp },
                activeUntil: info.activeUntil,
            )
        }
        .sorted { $0.eliminatedFraction < $1.eliminatedFraction }
    }
}
