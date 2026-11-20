import SwiftUI

/// Compact "≈110 mg active · 3.7h left" capsule shown in a quick-log
/// substance header — the estimated amount still in the body, in the dose's
/// own unit, rather than a bare percentage. Hidden below the same 5% floor as
/// the full card; tapping (handled by the parent) expands into
/// `EntryLevelEstimateCard`.
struct DosePKBadge: View {
    let remainingPercent: Double
    let lastDoseAmount: Double
    let unit: String
    let lastDoseTimestamp: Date

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                // One line beside a card title; at accessibility sizes the
                // badge has its own row and wraps.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            Image(systemName: "chevron.down")
                .scaledSystemFont(size: 8, weight: .bold, relativeTo: .caption2)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 3)
        .background(Theme.accent.opacity(Theme.Opacity.tint), in: skinChipShape())
        .foregroundStyle(Theme.accent)
    }

    private var label: String {
        let amount = activeAmount.doseFormatted
        let ago = DosePK.shortElapsed(since: lastDoseTimestamp)
        return String(localized: "est. \(amount) \(unit) active · \(ago) ago")
    }
}

struct EntryLevelEstimateCard: View {
    let substanceName: String
    let lastDoseAmount: Double
    let lastDoseTimestamp: Date
    let unit: String
    let route: RouteOfAdministration

    private var remainingPercent: Double? {
        DosePK.status(substanceName: substanceName, route: route, lastDoseTimestamp: lastDoseTimestamp)
    }

    var body: some View {
        if let remainingPercent, remainingPercent > 5 {
            cardContent(remainingPercent: remainingPercent)
        }
    }

    private func cardContent(remainingPercent: Double) -> some View {
        let activeAmount = lastDoseAmount * remainingPercent / 100
        return HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "info.circle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.accent)
                .padding(.top, 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("The model puts ≈\(activeAmount.doseFormatted) \(unit) of your \(lastDoseAmount.doseFormatted) \(unit) dose (\(timeAgo)) as still active, ~\(Int(remainingPercent))%")
                    .font(.caption)
                    .foregroundStyle(.primary)

                Text("An estimate from population data, not a measurement. It doesn't say when another dose is safe.")
                    .captionSecondary()
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        // Accent-tinted so it reads as an informational callout instead of a
        // second gray surface clashing with the card behind it.
        .background(Theme.accent.opacity(Theme.Opacity.hairline), in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
    }

    private var timeAgo: String {
        switch DosePK.Elapsed(since: lastDoseTimestamp) {
        case let .minutes(m):
            String(localized: "\(m)m ago")
        case let .wholeHours(h):
            String(localized: "\(h)h ago")
        case let .hours(hours):
            String(localized: "\(hours.formatted(.number.precision(.fractionLength(1))))h ago")
        case let .days(d):
            String(localized: "\(d)d ago")
        }
    }
}
