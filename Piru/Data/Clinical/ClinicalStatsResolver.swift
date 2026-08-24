import SwiftUI

/// Resolves the dose log into the Sendable snapshots ``ClinicalStats`` aggregates.
/// Every equivalence / ladder / duration lookup behind a dose is `@MainActor`, so
/// they happen here, once; the aggregation that follows is pure and off-main-ready.
///
/// One resolver, two consumers: the Insights patterns screen and the PDF clinician
/// report both call ``resolve(entries:colorMap:start:end:)`` and hand the result to
/// ``ClinicalStats/report(substances:doses:start:end:calendar:)``, so they can
/// never show different numbers.
enum ClinicalStatsResolver {
    @MainActor
    static func resolve(
        entries: [DoseEntry], hexMap: [String: String], start _: Date, end: Date,
    ) -> (substances: [ClinicalSubstance], doses: [ClinicalDose]) {
        let opioids = OpioidEquivalence.table
        let benzos = SubstanceStore.shared.benzoEquivalences()

        var substanceCache: [String: Substance?] = [:]
        func lookup(_ name: String) -> Substance? {
            let key = name.lowercased()
            if let hit = substanceCache[key] { return hit }
            let result = SubstanceLibrary.lookup(name)
            substanceCache[key] = result
            return result
        }

        // One resolved currency + display per substance, computed on first sight.
        struct Meta {
            let index: Int
            let substance: Substance?
            let currency: ExposureCurrency
        }
        var metaByName: [String: Meta] = [:]
        var substances: [ClinicalSubstance] = []
        var doses: [ClinicalDose] = []

        // Overlap needs doses that landed before the window but are still active
        // inside it, so include everything up to `end`; per-window stats filter
        // themselves in `ClinicalStats`.
        for entry in entries where entry.timestamp <= end {
            let substance = lookup(entry.substance)
            let canonical = substance?.name ?? entry.substance
            let canonicalKey = canonical.lowercased()

            let meta: Meta
            if let existing = metaByName[canonicalKey] {
                meta = existing
            } else {
                // Both tables key by name, but the opioid table is lowercase while
                // the benzo names come from the DB's `canonical_name` (title-case),
                // so match case-insensitively.
                let opioid = opioids.first { $0.name.lowercased() == canonicalKey && $0.mmePerMg != nil }
                let benzo = benzos.first { $0.name.lowercased() == canonicalKey && $0.diazepamPerMg != nil }
                let currency: ExposureCurrency = currency(for: substance, opioid: opioid, benzo: benzo)
                let index = substances.count
                meta = Meta(index: index, substance: substance, currency: currency)
                metaByName[canonicalKey] = meta
                substances.append(ClinicalSubstance(
                    name: canonical,
                    displayName: CustomSubstanceStore.shared.displayName(for: canonical, fallback: substance?.displayTitle),
                    colorHex: SubstancePalette.hex(for: canonical, hexMap: hexMap),
                    unit: unitLabel(currency: currency, loggedUnit: entry.unit),
                    currency: currency,
                ))
            }

            let doseMg = DoseUnit.convert(entry.amount, from: entry.unit, to: "mg")
            let exposure = exposureValue(
                currency: meta.currency, substance: meta.substance, entry: entry,
                doseMg: doseMg, opioids: opioids, benzos: benzos,
            )
            let (ke, ka) = rateConstants(substance: meta.substance, entry: entry)
            doses.append(ClinicalDose(
                substanceIndex: meta.index, timestamp: entry.timestamp,
                exposure: exposure, ke: ke, ka: ka,
            ))
        }

        return (substances, doses)
    }

    /// Resolve + aggregate in one call — the shape both consumers use.
    @MainActor
    static func report(entries: [DoseEntry], hexMap: [String: String], start: Date, end: Date) -> ClinicalReport {
        let (substances, doses) = resolve(entries: entries, hexMap: hexMap, start: start, end: end)
        return ClinicalStats.report(substances: substances, doses: doses, start: start, end: end, calendar: .current)
    }

    // MARK: - Currency

    private static func currency(for substance: Substance?, opioid: OpioidEquivalence?, benzo: BenzoEquivalence?) -> ExposureCurrency {
        if opioid != nil { return .mme }
        if benzo != nil { return .diazepam }
        // A substance with a common-dose ladder gets the normalized fallback.
        if let substance, let range = substance.doseRange(for: substance.defaultRoute) ?? substance.routes.first?.doses,
           range.common != nil {
            return .commonDose
        }
        return .milligrams
    }

    private static func exposureValue(
        currency: ExposureCurrency, substance: Substance?, entry: DoseEntry,
        doseMg: Double?, opioids: [OpioidEquivalence], benzos: [BenzoEquivalence],
    ) -> Double? {
        let key = (substance?.name ?? entry.substance).lowercased()
        switch currency {
        case .mme:
            guard let doseMg else { return nil }
            return opioids.first { $0.name.lowercased() == key }?.mme(forDoseMg: doseMg)
        case .diazepam:
            guard let doseMg else { return nil }
            return benzos.first { $0.name.lowercased() == key }?.diazepamEquivalent(forDoseMg: doseMg)
        case .commonDose:
            guard let substance else { return nil }
            let route = entry.route
            let range = substance.doseRange(for: route) ?? substance.doseRange(for: substance.defaultRoute) ?? substance.routes.first?.doses
            guard let range else { return nil }
            let ladderUnit = substance.unit(for: route)
            return UsageAnalyticsModel.commonDoses(range: range, ladderUnit: ladderUnit, amount: entry.amount, loggedUnit: entry.unit)
        case .milligrams:
            return doseMg
        }
    }

    private static func unitLabel(currency: ExposureCurrency, loggedUnit _: String) -> String {
        switch currency {
        case .mme: String(localized: "MME")
        case .diazepam: String(localized: "mg diazepam-eq")
        case .commonDose: String(localized: "common doses")
        case .milligrams: "mg"
        }
    }

    // MARK: - Overlap PK params

    /// `(ke, ka)` for the overlap body-load pass — `nil` for supplements and
    /// unmodeled forms, which are excluded from co-exposure the same way they're
    /// excluded from the body-load graph.
    private static func rateConstants(substance: Substance?, entry: DoseEntry) -> (Double?, Double?) {
        if substance?.category == .supplement { return (nil, nil) }
        let productDuration = entry.productDuration
        if productDuration == nil, entry.namesUnmodeledForm { return (nil, nil) }
        guard let params = PKResolver.params(
            substance: substance, entryName: entry.substance,
            duration: productDuration ?? substance?.resolveDuration(for: entry.route, saltForm: entry.saltForm, isomer: entry.isomer),
        ) else { return (nil, nil) }
        return (params.ke, params.ka)
    }
}
