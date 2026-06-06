import SwiftUI

/// Shared "how much of the last dose is still active" computation, used by the
/// full `DoseSuggestionCard` and the compact `DosePKBadge`.
enum DosePK {
    static func status(substanceName: String, route: RouteOfAdministration, lastDoseTimestamp: Date) -> (remainingPercent: Double, waitMinutes: Double)? {
        let halfLife: Double
        if let hl = SubstanceLibrary.lookupByNameOrAlias(substanceName)?.halfLifeMinutes, hl > 0 {
            halfLife = hl
        } else if let hl = HalfLifeDatabase.halfLife(for: substanceName), hl > 0 {
            halfLife = hl
        } else {
            return nil
        }

        let ke = PKModel.ke(fromHalfLifeMinutes: halfLife)
        guard ke > 0 else { return nil }

        let ka: Double
        if let substance = SubstanceLibrary.lookupByNameOrAlias(substanceName),
           let duration = substance.resolveDuration(for: route) {
            let ttp = (duration.onset?.midpoint ?? 0) + (duration.comeup?.midpoint ?? 0)
            ka = ttp > 0 ? PKModel.estimateKa(timeToPeak: ttp, ke: ke) : PKModel.defaultKa(ke: ke)
        } else {
            ka = PKModel.defaultKa(ke: ke)
        }

        let elapsed = Date.now.timeIntervalSince(lastDoseTimestamp) / 60
        guard elapsed >= 0 else { return nil }

        let remainingPercent = PKModel.fractionRemainingInBody(at: elapsed, ke: ke, ka: ka) * 100

        let timeTo10 = PKModel.timeToFraction(0.10, ke: ke, ka: ka)
        let waitMinutes = max(0, timeTo10 - elapsed)

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
}

/// Compact "58% · 5.9h" capsule shown in a quick-log substance header. Hidden
/// below the same 5% floor as the full card; tapping (handled by the parent)
/// expands into `DoseSuggestionCard`.
struct DosePKBadge: View {
    let remainingPercent: Double
    let lastDoseTimestamp: Date

    var body: some View {
        Text(verbatim: "\(Int(remainingPercent))% · \(DosePK.shortElapsed(since: lastDoseTimestamp))")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(.secondarySystemFill), in: Capsule())
            .foregroundStyle(Theme.secondaryLabel)
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
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.accent)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text("~\(Int(remainingPercent))% of your last dose (\(lastDoseAmount.doseFormatted)\(unit), \(timeAgo)) is still active")
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
