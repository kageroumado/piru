import SwiftUI

/// Shared "how much of the last dose is still active" computation, used by the
/// full `DoseSuggestionCard` and the compact `DosePKBadge`.
enum DosePK {
    static func status(substanceName: String, route: RouteOfAdministration, lastDoseTimestamp: Date) -> (remainingPercent: Double, waitMinutes: Double)? {
        // Only half-life + duration are needed, both carried by the lightweight batch
        // cache — resolve **once** through it rather than two full overlay-aware
        // `lookupByNameOrAlias` calls (≈18 SQL + chem/mechanism decode each). This runs
        // per unique recent substance when the quick-log card list rebuilds.
        let substance = SubstanceLibrary.timelineLookup(substanceName)
        let halfLife: Double
        if let hl = substance?.halfLifeMinutes, hl > 0 {
            halfLife = hl
        } else if let hl = HalfLifeDatabase.halfLife(for: substanceName), hl > 0 {
            halfLife = hl
        } else {
            return nil
        }

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

        let remainingPercent = PKModel.fractionRemainingInBody(at: elapsed, ke: ke, ka: ka) * 100

        // "How long until this stops being felt": prefer the substance's real
        // duration-of-effects profile; the half-life → 10%-body-load
        // projection is only the fallback for substances without duration
        // data (it wildly overstates for long-half-life drugs).
        let waitMinutes: Double
        if let duration, duration.estimatedTotalMinutes > 0 {
            waitMinutes = max(0, duration.estimatedTotalMinutes - elapsed)
        } else {
            let timeTo10 = PKModel.timeToFraction(0.10, ke: ke, ka: ka)
            waitMinutes = max(0, timeTo10 - elapsed)
        }

        return (remainingPercent, waitMinutes)
    }

    /// Bare elapsed-time label for the badge ("23m", "5.9h", "2d").
    static func shortElapsed(since date: Date) -> String {
        let minutes = Date.now.timeIntervalSince(date) / 60
        if minutes < 60 { return "\(Int(minutes))m" }
        let hours = minutes / 60
        if hours < 24 {
            return hours == hours.rounded(.toNearestOrEven) ? "\(Int(hours))h" : String(format: "%.1fh", hours)
        }
        return "\(Int(hours / 24))d"
    }

    /// Bare duration label ("23m", "3.7h", "10d").
    static func shortDuration(minutes: Double) -> String {
        if minutes < 60 { return "\(Int(minutes))m" }
        let hours = minutes / 60
        if hours >= 48 { return "\(Int((hours / 24).rounded()))d" }
        return hours == hours.rounded(.toNearestOrEven) ? "\(Int(hours))h" : String(format: "%.1fh", hours)
    }
}

/// Compact "≈110 mg active · 3.7h left" capsule shown in a quick-log
/// substance header — the estimated amount still in the body, in the dose's
/// own unit, rather than a bare percentage. Hidden below the same 5% floor as
/// the full card; tapping (handled by the parent) expands into
/// `DoseSuggestionCard`.
struct DosePKBadge: View {
    let remainingPercent: Double
    let lastDoseAmount: Double
    let unit: String
    let waitMinutes: Double
    let lastDoseTimestamp: Date

    private var activeAmount: Double {
        lastDoseAmount * remainingPercent / 100
    }

    var body: some View {
        // Dressed as something you can open, because you can. This capsule was
        // the only interactive element in the card header wearing the app's
        // *passive* vocabulary — `secondarySystemFill` behind `secondaryLabel`,
        // the same combination as the inert "+N" chip fold — so nothing said it
        // expanded. The accent tint and the chevron are the card's existing
        // signals for "there is more behind this", borrowed rather than invented.
        HStack(spacing: 3) {
            Text(label)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.accent)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.accent.opacity(0.12), in: Capsule())
        .foregroundStyle(Theme.accent)
    }

    private var label: String {
        let amount = activeAmount.doseFormatted
        let ago = DosePK.shortElapsed(since: lastDoseTimestamp)
        if waitMinutes > 1 {
            let wait = DosePK.shortDuration(minutes: waitMinutes)
            return String(localized: "≈\(amount) \(unit) active · \(ago) ago · \(wait) left")
        }
        return String(localized: "≈\(amount) \(unit) active · \(ago) ago")
    }
}

struct DoseSuggestionCard: View {
    let substanceName: String
    let lastDoseAmount: Double
    let lastDoseTimestamp: Date
    let unit: String
    let route: RouteOfAdministration

    private var pkResult: (remainingPercent: Double, waitMinutes: Double)? {
        DosePK.status(substanceName: substanceName, route: route, lastDoseTimestamp: lastDoseTimestamp)
    }

    var body: some View {
        if let result = pkResult, result.remainingPercent > 5 {
            cardContent(remainingPercent: result.remainingPercent, waitMinutes: result.waitMinutes)
        }
    }

    private func cardContent(remainingPercent: Double, waitMinutes: Double) -> some View {
        let activeAmount = lastDoseAmount * remainingPercent / 100
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.accent)
                .padding(.top, 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                // Leads with the same absolute amount as the badge — the two
                // surfaces must never look like they disagree.
                Text("≈\(activeAmount.doseFormatted) \(unit) of your \(lastDoseAmount.doseFormatted) \(unit) dose (\(timeAgo)) is still active — ~\(Int(remainingPercent))%")
                    .font(.caption)
                    .foregroundStyle(.primary)

                if remainingPercent > 10, waitMinutes > 1 {
                    Text("Consider waiting ~\(formattedWait(waitMinutes)) more")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        // Accent-tinted so it reads as an informational callout instead of a
        // second gray surface clashing with the card behind it.
        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var timeAgo: String {
        let minutes = Date.now.timeIntervalSince(lastDoseTimestamp) / 60
        if minutes < 60 {
            let m = Int(minutes)
            return String(localized: "\(m)m ago")
        }
        let hours = minutes / 60
        if hours < 24 {
            if hours == hours.rounded(.toNearestOrEven) {
                let h = Int(hours)
                return String(localized: "\(h)h ago")
            }
            return String(localized: "\(String(format: "%.1f", hours))h ago")
        }
        let d = Int(hours / 24)
        return String(localized: "\(d)d ago")
    }

    private func formattedWait(_ minutes: Double) -> String {
        if minutes < 60 {
            let m = Int(minutes)
            return String(localized: "\(m)m")
        }
        let hours = minutes / 60
        if hours == hours.rounded(.toNearestOrEven) {
            let h = Int(hours)
            return String(localized: "\(h)h")
        }
        return String(localized: "\(String(format: "%.1f", hours))h")
    }
}
