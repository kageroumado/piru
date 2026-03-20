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

    var id: String { name }
    var eliminatedFraction: Double { 1 - totalRemaining / totalDosed }

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
                timestamp: entry.timestamp
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
                    totalRemaining: remaining
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
                doses: info.doses.sorted { $0.timestamp > $1.timestamp }
            )
        }
        .sorted { $0.eliminatedFraction < $1.eliminatedFraction }
    }
}

// MARK: - ActiveSubstanceState Builders

extension ActiveSubstanceState {
    /// Build from a pre-resolved duration profile and basic dose info.
    init?(name: String, colorHex: String, timestamp: Date, amount: Double, unit: String, routeDisplayName: String, duration: DurationProfile?) {
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
            totalMinutes: duration.estimatedTotalMinutes
        )
    }

    /// Build from a dose entry by looking up substance duration data.
    static func from(entry: DoseEntry, colorHex: String) -> ActiveSubstanceState? {
        guard let substance = SubstanceLibrary.lookupByNameOrAlias(entry.substance),
              let duration = substance.resolveDuration(for: entry.route) else { return nil }
        return ActiveSubstanceState(
            name: entry.substance,
            colorHex: colorHex,
            timestamp: entry.timestamp,
            amount: entry.amount,
            unit: entry.unit,
            routeDisplayName: entry.route.displayName,
            duration: duration
        )
    }
}
