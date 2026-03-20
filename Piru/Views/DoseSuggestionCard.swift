import SwiftUI

struct DoseSuggestionCard: View {
    let substanceName: String
    let lastDoseAmount: Double
    let lastDoseTimestamp: Date
    let unit: String
    let route: RouteOfAdministration

    private var pkResult: (remainingPercent: Double, waitMinutes: Double)? {
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var timeAgo: String {
        let minutes = Date.now.timeIntervalSince(lastDoseTimestamp) / 60
        if minutes < 60 {
            return "\(Int(minutes))m ago"
        }
        let hours = minutes / 60
        if hours < 24 {
            return String(format: "%.1fh ago", hours).replacingOccurrences(of: ".0h", with: "h")
        }
        return String(format: "%.0fd ago", hours / 24)
    }

    private func formattedWait(_ minutes: Double) -> String {
        if minutes < 60 {
            return "\(Int(minutes))m"
        }
        let hours = minutes / 60
        return String(format: "%.1fh", hours).replacingOccurrences(of: ".0h", with: "h")
    }
}
