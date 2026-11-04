import SwiftUI

extension BodyLevelsManager {
    /// The main-actor half of a body-load computation: the resolved dose set, the
    /// per-series display metadata, and the sample grid. Built on the main actor
    /// (every substance/duration lookup behind it is `@MainActor`); its `doses` +
    /// `dates` then cross to the off-main sampler, and ``assemble(values:)`` folds
    /// the returned amounts back into a ``BodyLoadTrail`` on the main actor.
    struct Plan {
        /// Per-series display metadata, parallel to the sampler's outer array.
        struct SeriesMeta {
            let displayName: String
            let color: Color
            let unit: String
            /// The series' first dose; every later one is expressed in its unit.
            let unitOf: DoseQuantity
        }

        /// A series is one substance in one unit family — a substance logged in
        /// both mL and mg is two non-addable series. Mirrors ``ActiveSubstanceCalculator``.
        private struct SeriesKey: Hashable {
            let name: String
            let family: DoseQuantity.Family
        }

        let dates: [Date]
        let doses: [BodyLoadDose]
        let meta: [SeriesMeta]

        /// Resolve the log into a plan, or `nil` when nothing has a modeled
        /// body-load in the window (only supplements / unmodeled forms logged).
        @MainActor
        static func build(entries: [BodyLoadEntry], colorMap: [String: Color], range: UsageTimeRange, now: Date) -> Plan? {
            let dates = sampleDates(range: range, entries: entries, now: now)
            guard !dates.isEmpty else { return nil }

            var substanceCache: [String: Substance?] = [:]
            func lookup(_ name: String) -> Substance? {
                let key = name.lowercased()
                if let hit = substanceCache[key] { return hit }
                let result = SubstanceLibrary.lookup(name)
                substanceCache[key] = result
                return result
            }

            var seriesIndex: [SeriesKey: Int] = [:]
            var meta: [SeriesMeta] = []
            var doses: [BodyLoadDose] = []

            for entry in entries where entry.timestamp <= now {
                let substance = lookup(entry.substance)
                // Same exclusions as `ActiveSubstanceCalculator`: supplements clear
                // over days-to-weeks (their body-load readout is noise), and an
                // unmodeled release form without a per-product envelope has no
                // honest absorption limb.
                if substance?.modelsBodyLoad == false { continue }
                guard let dose = entry.quantity(using: substance) else { continue }
                let productDuration = entry.productDuration
                // A depot administration keeps its slow depot half-life and no acute
                // absorption limb (see PKResolver / ActiveSubstanceCalculator), so it
                // plots as a slow depot decay rather than a fast base-drug spike.
                let isDepot = entry.isDepot
                if !isDepot, productDuration == nil, entry.namesUnmodeledForm { continue }
                guard let halfLife = entry.halfLifeMinutes(substance: substance, isDepot: isDepot) else { continue }
                let (ke, ka) = PKResolver.rateConstants(
                    halfLifeMinutes: halfLife,
                    duration: isDepot ? nil : entry.applyingMeal(to: productDuration ?? substance?.resolveDuration(
                        for: entry.route, saltForm: entry.saltForm, isomer: entry.isomer,
                    )),
                )
                let params = PKResolver.Params(halfLifeMinutes: halfLife, ke: ke, ka: ka)

                let name = substance?.name ?? entry.substance
                let key = SeriesKey(name: name, family: dose.family)
                let index: Int
                if let existing = seriesIndex[key] {
                    index = existing
                } else {
                    index = meta.count
                    seriesIndex[key] = index
                    meta.append(SeriesMeta(
                        displayName: CustomSubstanceStore.shared.displayName(for: name, fallback: substance?.displayTitle),
                        color: SubstancePalette.color(for: name, colorMap: colorMap),
                        unit: entry.unit,
                        unitOf: dose,
                    ))
                }
                // Express in the series' established unit; the key's family
                // guarantees the two convert.
                guard let amount = dose.value(inUnitOf: meta[index].unitOf) else { continue }
                doses.append(BodyLoadDose(
                    seriesIndex: index, amount: amount, timestamp: entry.timestamp,
                    ke: params.ke, ka: params.ka,
                ))
            }

            guard !doses.isEmpty else { return nil }
            return Plan(dates: dates, doses: doses, meta: meta)
        }

        /// Fold the sampler's per-series amounts back into a trail: normalize each
        /// series to its own peak, drop series that never rose above the floor,
        /// and order by doses logged in the window, so the substances logged most
        /// lead the legend and are the lines the chart draws by default.
        @MainActor
        func assemble(values: [[Double]]) -> BodyLoadTrail {
            var doseCounts = [Int](repeating: 0, count: meta.count)
            if let start = dates.first {
                for dose in doses where dose.timestamp >= start {
                    doseCounts[dose.seriesIndex] += 1
                }
            }
            var series: [BodyLoadTrail.Series] = []
            for (index, meta) in meta.enumerated() {
                guard index < values.count else { continue }
                let amounts = values[index]
                let peak = amounts.max() ?? 0
                guard peak > 0 else { continue }
                let points = amounts.enumerated().map { i, amount in
                    BodyLoadTrail.Point(id: i, date: dates[i], amount: amount, fraction: amount / peak)
                }
                series.append(BodyLoadTrail.Series(
                    id: index, displayName: meta.displayName,
                    color: meta.color, unit: meta.unit, peak: peak, doseCount: doseCounts[index], points: points,
                ))
            }
            series.sort { lhs, rhs in
                lhs.doseCount != rhs.doseCount ? lhs.doseCount > rhs.doseCount : lhs.peak > rhs.peak
            }
            return BodyLoadTrail(dates: dates, series: series)
        }

        /// The ascending sample grid: the window `[start, now]` at a range-appropriate
        /// step. Steps are chosen so a short-half-life sawtooth stays legible on the
        /// tighter ranges while a year renders its envelope without a 17k-point comb.
        @MainActor
        private static func sampleDates(range: UsageTimeRange, entries: [BodyLoadEntry], now: Date) -> [Date] {
            let start: Date
            if let days = range.days {
                start = now.addingTimeInterval(-Double(days) * 86_400)
            } else {
                // "All": from the earliest logged dose (a day's margin so its own
                // rise is visible), falling back to a year when the log is empty.
                let earliest = entries.map(\.timestamp).min() ?? now.addingTimeInterval(-365 * 86_400)
                start = min(earliest.addingTimeInterval(-86_400), now.addingTimeInterval(-86_400))
            }
            let span = now.timeIntervalSince(start)
            guard span > 0 else { return [] }

            var step: Double = switch range {
            case .sevenDays: 900 // 15 min
            case .thirtyDays: 3_600 // 1 h
            case .ninetyDays: 3 * 3_600
            case .oneYear: 12 * 3_600
            case .all: max(6 * 3_600, span / 1_000)
            }
            // Never exceed ~2000 points regardless of range/span.
            if span / step > 2_000 { step = span / 2_000 }

            var dates: [Date] = []
            var t = start
            while t <= now {
                dates.append(t)
                t = t.addingTimeInterval(step)
            }
            if dates.last != now { dates.append(now) }
            return dates
        }
    }
}

/// What a plan asks of a logged dose, answered from its stored fields exactly as the
/// `DoseEntry` members of the same names answer from the model.
extension BodyLoadEntry {
    /// The amount parsed against `substance`'s units, its aliases included, or as written
    /// when the substance is unknown; `nil` for an unknown dose.
    func quantity(using substance: Substance?) -> DoseQuantity? {
        guard !isUnknownDose else { return nil }
        return substance?.quantity(amount, unit: unit) ?? DoseQuantity(amount, unit: unit)
    }

    var namesUnmodeledForm: Bool {
        DoseEntry.namesUnmodeledForm(releaseForm: releaseForm)
    }

    @MainActor var productDuration: DurationProfile? {
        DoseEntry.productDuration(named: productName)
    }

    @MainActor var isDepot: Bool {
        PKResolver.isDepot(
            releaseForm: releaseForm, route: route, saltForm: saltForm, substanceUID: substanceUID, substance: substance,
        )
    }

    /// The depot-aware half-life ``PKResolver/halfLifeMinutes(for:substance:)`` gives the
    /// model, for a caller that has already asked ``isDepot``.
    @MainActor
    func halfLifeMinutes(substance resolved: Substance?, isDepot: Bool) -> Double? {
        PKResolver.depotHalfLifeMinutes(substanceUID: substanceUID, substance: substance, saltForm: saltForm, isDepot: isDepot)
            ?? PKResolver.halfLifeMinutes(substance: resolved)
    }

    @MainActor
    func applyingMeal(to duration: DurationProfile?) -> DurationProfile? {
        MealState.shifting(duration, by: meal, substance: substance, product: productName, route: route)
    }
}
