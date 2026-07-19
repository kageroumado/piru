import SwiftUI

// MARK: - In-dock search results

/// One in-dock search hit: a recent card, a library substance, or a custom one.
enum QuickLogSearchResult: Identifiable {
    case recent(SubstanceCard)
    /// A library hit, carrying the alias the query matched — so a search for
    /// "Concerta" can say so instead of silently resolving to "Methylphenidate".
    case library(SubstanceMatch)
    case custom(Substance)

    var id: String {
        switch self {
        case let .recent(card): "recent|\(card.id)"
        case let .library(match): "library|\(match.substance.name.lowercased())"
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
    /// The name the user actually named this dose by — the catalog alias their
    /// query matched ("Concerta", "Vyvanse"). `nil` when they searched the
    /// canonical name, so nothing is asserted that they didn't say.
    ///
    /// Never a lookup key: `substance` stays canonical and every resolve keeps
    /// going through it (`Specs/psid-identity-consumption.md` LB-1).
    var productName: String?
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
/// reference defaults, then ends the search (the dock settles onto medium with
/// the new row's editor open — see ``DockMiddleContent/onDidStage``). Doses
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
                name: card.title ?? customSubstanceStore.displayName(for: card.substanceName),
                source: String(localized: "Recent"),
                tint: card.colorHex.map { Color(hex: $0) } ?? .gray,
                detail: card.routes.first?.librarySubstance.flatMap { substanceDetail($0) }
                    ?? card.routes.first.map { String(localized: $0.route.localizedName) },
            )
        case let .library(match):
            resultRow(
                result: result,
                name: match.displayName,
                source: String(localized: "Library"),
                tint: match.substance.category.color,
                detail: substanceDetail(match.substance, matchedAlias: match.matchedAlias),
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
    ///
    /// When the query named an alias, the identity displaces the dose band: a row
    /// titled "Concerta" has to answer *what is that* before it answers *how much*,
    /// and a successful brand match currently looks identical to a failed one.
    private func substanceDetail(_ substance: Substance, matchedAlias: String? = nil) -> String? {
        if let matchedAlias { return resolvedIdentity(substance, matchedAlias: matchedAlias) }
        var parts = [String(localized: substance.category.displayName)]
        if let routeInfo = substance.routes.first(where: { $0.route == substance.defaultRoute }),
           let common = routeInfo.doses.common {
            let low = common.lowerBound.doseFormatted
            let high = common.upperBound.doseFormatted
            parts.append(String(localized: "Common \(low)–\(high) \(routeInfo.unit)"))
        }
        return parts.joined(separator: " · ")
    }

    /// What the alias resolved to — "Methylphenidate XR" under a "Concerta" title,
    /// "Lisdexamfetamine" under "Vyvanse".
    ///
    /// The composed form title is right only when the alias actually names a form.
    /// For a plain brand the catalog's own title is better: `displayTitle` is
    /// region-resolved, which `substance_forms` deliberately is not, so a UK user
    /// searching a paracetamol brand should not be told it is "Acetaminophen".
    private func resolvedIdentity(_ substance: Substance, matchedAlias: String) -> String {
        let namesAForm = SubstanceLibrary.releaseForm(for: matchedAlias) != nil
            || SubstanceLibrary.isomer(for: matchedAlias) != nil
        if namesAForm, let composed = SubstanceLibrary.formTitle(for: matchedAlias) {
            return composed
        }
        return substance.displayTitle
    }

    /// Leading ⊕ tinted with the substance/category color — the whole row is
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
                productName: group?.stageProductName,
                volumeML: chip?.volumeML,
                abv: chip?.abv,
                drinkName: chip?.drinkName,
                emoji: chip?.emoji,
            )
        case let .library(match):
            return payload(for: match.substance, productName: match.matchedAlias)
        case let .custom(substance):
            return payload(for: substance, productName: nil)
        }
    }

    private func payload(for substance: Substance, productName: String?) -> QuickLogStagePayload {
        let route = substance.defaultRoute
        let unit = substance.defaultUnit
        return QuickLogStagePayload(
            // Canonical, always — `substance` is the lookup key every downstream
            // resolve depends on. The user's word rides alongside in `productName`
            // and never becomes a key.
            substance: substance.name,
            route: route,
            unit: unit,
            amount: StagedDose.lookupReferenceDose(substance: substance, route: route, unit: unit) ?? 0,
            colorHex: nil,
            librarySubstance: substance,
            productName: productName,
        )
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
