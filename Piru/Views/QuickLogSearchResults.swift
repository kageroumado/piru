import SwiftUI

// MARK: - In-dock search results

/// One in-dock search hit: a recent card, a library substance, or a custom one.
enum QuickLogSearchResult: Identifiable {
    case recent(SubstanceCard)
    case library(Substance)
    case custom(Substance)

    var id: String {
        switch self {
        case let .recent(card): "recent|\(card.id)"
        case let .library(substance): "library|\(substance.name.lowercased())"
        case let .custom(substance): "custom|\(substance.name.lowercased())"
        }
    }
}

/// Everything the tray needs to stage one hit — assembled by the row on tap.
struct QuickLogStagePayload {
    let substance: String
    let route: RouteOfAdministration
    let unit: String
    let amount: Double
    let colorHex: String?
    let librarySubstance: Substance?
    /// By-volume drink metadata carried from a recent's chip, so a re-logged
    /// drink re-stages exactly (name, strength, volume — chip parity) instead
    /// of opening a blank drink draft. `nil` everywhere else.
    var volumeML: Double?
    var abv: Double?
    var drinkName: String?
    var emoji: String?
}

/// The list of search hits beneath the dock's pinned field. Pure
/// presentation: the parent computes the ranked `results` and supplies the
/// staging/create actions; this view owns the row layout.
///
/// Every row is one big Add button: a tap stages the dose with its recent /
/// reference defaults into the staged card below — search never moves. Doses
/// that still need input (by-volume drinks, substances with no known dose)
/// stage as a draft, which opens the full editor in the tray. There is no
/// inline mini-editor: the staged card's editor is the one editing surface.
struct QuickLogSearchResults: View {
    let results: [QuickLogSearchResult]
    /// Stage a complete dose.
    let onAdd: (QuickLogStagePayload) -> Void
    /// Stage a draft that opens the full editor in the tray.
    let onAddDraft: (QuickLogStagePayload) -> Void
    /// `nil` hides the trailing "Create custom substance" row — the
    /// suggestions surfaces (recents, category browse) reuse these rows
    /// without the create CTA.
    let onCreateCustom: (() -> Void)?

    @State private var customSubstanceStore = CustomSubstanceStore.shared

    /// One fixed height for every result row — content varies (a substance may
    /// lack a dose band), the rhythm must not. Scaled so two lines still fit
    /// at accessibility text sizes.
    @ScaledMetric(relativeTo: .body) private var resultRowHeight: CGFloat = 56
    @ScaledMetric(relativeTo: .body) private var createRowHeight: CGFloat = 48

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                if index > 0 {
                    Divider().padding(.leading, 16)
                }
                row(result)
            }
            if let onCreateCustom {
                if !results.isEmpty {
                    Divider().padding(.leading, 16)
                }
                createCustomRow(onCreateCustom)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ result: QuickLogSearchResult) -> some View {
        switch result {
        case let .recent(card):
            resultRow(
                result: result,
                name: customSubstanceStore.displayName(for: card.substanceName),
                source: String(localized: "Recent"),
                tint: card.colorHex.map { Color(hex: $0) } ?? .gray,
                detail: card.routes.first?.librarySubstance.flatMap(substanceDetail)
                    ?? card.routes.first.map { String(localized: $0.route.localizedName) },
            )
        case let .library(substance):
            resultRow(
                result: result,
                name: substance.displayTitle,
                source: String(localized: "Library"),
                tint: substance.category.color,
                detail: substanceDetail(substance),
            )
        case let .custom(substance):
            resultRow(
                result: result,
                name: substance.name,
                source: String(localized: "Custom"),
                tint: substance.category.color,
                detail: substanceDetail(substance),
            )
        }
    }

    /// "Psychedelic · Common 75–150 µg" — class plus the default route's
    /// common-dose band.
    private func substanceDetail(_ substance: Substance) -> String? {
        var parts = [String(localized: substance.category.displayName)]
        if let routeInfo = substance.routes.first(where: { $0.route == substance.defaultRoute }),
           let common = routeInfo.doses.common {
            let low = common.lowerBound.doseFormatted
            let high = common.upperBound.doseFormatted
            parts.append(String(localized: "Common \(low)–\(high) \(routeInfo.unit)"))
        }
        return parts.joined(separator: " · ")
    }

    /// Leading ⊕ tinted with the substance/category colour — the whole row is
    /// the Add button.
    private func resultRow(
        result: QuickLogSearchResult,
        name: String,
        source: String,
        tint: Color,
        detail: String?,
    ) -> some View {
        Button {
            add(result)
        } label: {
            HStack(spacing: 10) {
                // Decorative — the row itself is the Add button; without this
                // VoiceOver announces the symbol before the substance name.
                Image(systemName: "plus.circle.fill")
                    .font(.body)
                    .foregroundStyle(tint)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(source)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    // The detail line always renders (a space when absent),
                    // so the title sits at the same height in every row.
                    Text(verbatim: detail ?? " ")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: resultRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Adds this dose")
    }

    /// A complete dose stages straight into the tray; one that still needs
    /// input (a by-volume drink with nothing recorded, or no known reference
    /// dose) stages as a draft, opening its full editor in the staged card.
    /// A recent with a recorded drink is already complete — it re-stages
    /// exactly, matching the recent-card chip path.
    private func add(_ result: QuickLogSearchResult) {
        let payload = payload(for: result)
        let hasRecordedDrink = payload.volumeML != nil && payload.abv != nil && payload.amount > 0
        if (payload.librarySubstance?.byVolumeDosing != nil && !hasRecordedDrink) || payload.amount <= 0 {
            onAddDraft(payload)
        } else {
            onAdd(payload)
        }
    }

    /// The stage payload for one hit. Recents prefill from their most recent
    /// chip; library hits from the reference dose for the default route.
    private func payload(for result: QuickLogSearchResult) -> QuickLogStagePayload {
        switch result {
        case let .recent(card):
            let group = card.routes.first
            let chip = group?.doses.first
            return QuickLogStagePayload(
                substance: card.substanceName,
                route: group?.route ?? .oral,
                unit: chip?.unit ?? "mg",
                amount: chip?.amount ?? 0,
                colorHex: card.colorHex,
                librarySubstance: group?.librarySubstance,
                volumeML: chip?.volumeML,
                abv: chip?.abv,
                drinkName: chip?.drinkName,
                emoji: chip?.emoji,
            )
        case let .library(substance), let .custom(substance):
            let route = substance.defaultRoute
            let unit = substance.defaultUnit
            return QuickLogStagePayload(
                substance: substance.name,
                route: route,
                unit: unit,
                amount: StagedDose.lookupReferenceDose(substance: substance, route: route, unit: unit) ?? 0,
                colorHex: nil,
                librarySubstance: substance,
            )
        }
    }

    private func createCustomRow(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text("Create custom substance")
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer()
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 16)
            .frame(height: createRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
