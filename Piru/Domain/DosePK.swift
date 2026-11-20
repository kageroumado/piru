import Foundation

/// Shared "how much of the last dose is still active" computation, used by the
/// full `EntryLevelEstimateCard` and the compact `DosePKBadge`.
enum DosePK {
    static func status(substanceName: String, route: RouteOfAdministration, lastDoseTimestamp: Date) -> Double? {
        // Only half-life + duration are needed, both carried by the lightweight batch
        // cache — resolve **once** through it rather than two full overlay-aware
        // `lookupByNameOrAlias` calls (≈18 SQL + chem/mechanism decode each). This runs
        // per unique recent substance when the quick-log card list rebuilds.
        let substance = SubstanceLibrary.lookup(substanceName)
        let halfLife: Double
        guard let hl = substance?.halfLifeMinutes, hl > 0 else { return nil }
        halfLife = hl

        let ke = PKModel.ke(fromHalfLifeMinutes: halfLife)
        guard ke > 0 else { return nil }

        let duration = substance?.resolveDuration(for: route)

        let ka: Double
        if let duration {
            let ttp = (duration.onset?.midpoint ?? 0) + (duration.comeup?.midpoint ?? 0)
            ka = ttp > 0 ? PKModel.estimateKa(timeToPeak: ttp, ke: ke) : PKModel.defaultKa(ke: ke)
        } else {
            ka = PKModel.defaultKa(ke: ke)
        }

        let elapsed = Date.now.timeIntervalSince(lastDoseTimestamp) / 60
        guard elapsed >= 0 else { return nil }

        return PKModel.fractionRemainingInBody(at: elapsed, ke: ke, ka: ka) * 100
    }

    /// The time since a dose, in the unit its label reads in: whole minutes
    /// under an hour, hours (whole or to one decimal) under a day, else whole
    /// days.
    enum Elapsed: Equatable {
        case minutes(Int)
        case wholeHours(Int)
        case hours(Double)
        case days(Int)

        init(since date: Date, now: Date = .now) {
            let minutes = now.timeIntervalSince(date) / 60
            if minutes < 60 {
                self = .minutes(Int(minutes))
                return
            }
            let hours = minutes / 60
            if hours < 24 {
                self = hours == hours.rounded(.toNearestOrEven) ? .wholeHours(Int(hours)) : .hours(hours)
                return
            }
            self = .days(Int(hours / 24))
        }
    }

    /// Bare elapsed-time label for the badge ("23m", "5.9h", "2d").
    static func shortElapsed(since date: Date) -> String {
        switch Elapsed(since: date) {
        case let .minutes(minutes): "\(minutes)m"
        case let .wholeHours(hours): "\(hours)h"
        case let .hours(hours): String(format: "%.1fh", hours)
        case let .days(days): "\(days)d"
        }
    }

    /// Bare duration label ("23m", "3.7h", "10d").
    static func shortDuration(minutes: Double) -> String {
        if minutes < 60 { return "\(Int(minutes))m" }
        let hours = minutes / 60
        if hours >= 48 { return "\(Int((hours / 24).rounded()))d" }
        return hours == hours.rounded(.toNearestOrEven) ? "\(Int(hours))h" : String(format: "%.1fh", hours)
    }
}
