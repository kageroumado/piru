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
            let name: String
            let displayName: String
            let color: Color
            let unit: String
        }

        let dates: [Date]
        let doses: [BodyLoadDose]
        let meta: [SeriesMeta]

        /// Resolve the log into a plan, or `nil` when nothing has a modeled
        /// body-load in the window (only supplements / unmodeled forms logged).
        @MainActor
        static func build(entries: [DoseEntry], colors: [SubstanceColor], range: UsageTimeRange, now: Date) -> Plan? {
            let dates = sampleDates(range: range, entries: entries, now: now)
            guard !dates.isEmpty else { return nil }

            let colorMap = colors.colorMap
            var substanceCache: [String: Substance?] = [:]
            func lookup(_ name: String) -> Substance? {
                let key = name.lowercased()
                if let hit = substanceCache[key] { return hit }
                let result = SubstanceLibrary.lookup(name)
                substanceCache[key] = result
                return result
            }

            var seriesIndex: [String: Int] = [:]
            var meta: [SeriesMeta] = []
            var doses: [BodyLoadDose] = []

            for entry in entries where entry.timestamp <= now {
                let substance = lookup(entry.substance)
                // Same exclusions as `ActiveSubstanceCalculator`: supplements clear
                // over days-to-weeks (their body-load readout is noise), and an
                // unmodeled release form without a per-product envelope has no
                // honest absorption limb.
                if substance?.category == .supplement { continue }
                let productDuration = entry.productDuration
                if productDuration == nil, entry.namesUnmodeledForm { continue }
                guard let params = PKResolver.params(
                    substance: substance,
                    entryName: entry.substance,
                    duration: productDuration ?? substance?.resolveDuration(
                        for: entry.route, saltForm: entry.saltForm, isomer: entry.isomer,
                    ),
                ) else { continue }

                let name = substance?.name ?? entry.substance
                let key = "\(name)|\(unitFamily(entry.unit))"
                let index: Int
                if let existing = seriesIndex[key] {
                    index = existing
                } else {
                    index = meta.count
                    seriesIndex[key] = index
                    meta.append(SeriesMeta(
                        name: name,
                        displayName: CustomSubstanceStore.shared.displayName(for: name, fallback: substance?.displayTitle),
                        color: SubstancePalette.color(for: name, colorMap: colorMap),
                        unit: entry.unit,
                    ))
                }
                // Express in the series' established unit; a same-family conversion
                // can't fail, and the fallback keeps scales from silently mixing.
                let amount = DoseUnit.convert(entry.amount, from: entry.unit, to: meta[index].unit) ?? entry.amount
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
        /// and order by peak so the heaviest load leads the legend.
        @MainActor
        func assemble(values: [[Double]]) -> BodyLoadTrail {
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
                    color: meta.color, unit: meta.unit, peak: peak, points: points,
                ))
            }
            series.sort { $0.peak > $1.peak }
            return BodyLoadTrail(dates: dates, series: series)
        }

        /// Group key must carry the unit family, not just the name — a substance
        /// logged in both mL and mg is two non-addable series. Mirrors
        /// ``ActiveSubstanceCalculator``.
        private static func unitFamily(_ unit: String) -> String {
            DoseUnit.convert(1, from: unit, to: "mg") == nil ? unit : "mass"
        }

        /// The ascending sample grid: the window `[start, now]` at a range-appropriate
        /// step. Steps are chosen so a short-half-life sawtooth stays legible on the
        /// tighter ranges while a year renders its envelope without a 17k-point comb.
        @MainActor
        private static func sampleDates(range: UsageTimeRange, entries: [DoseEntry], now: Date) -> [Date] {
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
