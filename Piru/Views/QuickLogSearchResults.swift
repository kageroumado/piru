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

/// Everything the tray needs to stage one hit — assembled by the row when the
/// user commits an amount (or asks for the full editor).
struct QuickLogStagePayload {
    let substance: String
    let route: RouteOfAdministration
    let unit: String
    let amount: Double
    let colorHex: String?
    let librarySubstance: Substance?
}

/// The list of search hits beneath the dock's pinned field. Pure
/// presentation: the parent computes the ranked `results` and supplies the
/// staging/create actions; this view owns the row layout and the inline
/// expansion.
///
/// Tapping a row expands it in place — amount steppers prefilled with the
/// substance's reference dose and an Add button that stages into the tray —
/// so adding a dose never swaps the whole dock content out from under the
/// search. By-volume substances (alcohol) offer their full drink editor
/// instead, staged as a draft.
struct QuickLogSearchResults: View {
    let results: [QuickLogSearchResult]
    /// Stage a complete dose (the inline Add).
    let onAdd: (QuickLogStagePayload) -> Void
    /// Stage a draft that opens the full editor in the tray (by-volume).
    let onAddDraft: (QuickLogStagePayload) -> Void
    /// `nil` hides the trailing "Create custom substance" row — the
    /// suggestions surfaces (recents, category browse) reuse these rows
    /// without the create CTA.
    let onCreateCustom: (() -> Void)?

    @State private var customSubstanceStore = CustomSubstanceStore.shared

    /// The one row currently expanded into its inline dose entry.
    @State private var expandedID: String?
    @State private var amount: Double = 0
    @State private var unit = "mg"

    /// One fixed height for every result row — content varies (a substance may
    /// lack a dose band), the rhythm must not.
    private static let resultRowHeight: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                if index > 0 {
                    Divider().padding(.leading, 16)
                }
                row(result)
                if expandedID == result.id {
                    inlineEntry(for: result)
                }
            }
            if let onCreateCustom {
                if !results.isEmpty {
                    Divider().padding(.leading, 16)
                }
                createCustomRow(onCreateCustom)
            }
        }
        .padding(.vertical, 4)
        // A changed result set invalidates the expansion (the row may be gone).
        .onChange(of: results.map(\.id)) {
            expandedID = nil
        }
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

    /// Leading chevron (rotates open with the inline entry), tinted with the
    /// substance/category colour.
    private func resultRow(
        result: QuickLogSearchResult,
        name: String,
        source: String,
        tint: Color,
        detail: String?,
    ) -> some View {
        let expanded = expandedID == result.id
        return Button {
            withAnimation(.snappy) { toggle(result) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 16)
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
            .frame(height: Self.resultRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(expanded ? "Collapses the dose entry" : "Expands a dose entry")
    }

    // MARK: Inline entry

    /// The expanded strip under a row: reference-dose steppers + Add. A
    /// by-volume substance (alcohol) routes to its full drink editor instead.
    @ViewBuilder
    private func inlineEntry(for result: QuickLogSearchResult) -> some View {
        let payload = payload(for: result)
        if payload.librarySubstance?.byVolumeDosing != nil {
            Button {
                withAnimation(.snappy) {
                    expandedID = nil
                    onAddDraft(payload)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wineglass")
                        .imageScale(.small)
                    Text("Add & edit drink…")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 42)
                .padding(.bottom, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 8) {
                stepButton(systemImage: "minus") {
                    amount = max(0, amount - amountStep)
                }
                .accessibilityLabel("Lower amount")
                Text(verbatim: "\(amount.doseFormatted) \(unit)")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
                stepButton(systemImage: "plus") {
                    amount += amountStep
                }
                .accessibilityLabel("Raise amount")
                Button {
                    let final = payload
                    withAnimation(.snappy) {
                        expandedID = nil
                        onAdd(final)
                    }
                } label: {
                    Text("Add")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 36)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(amount <= 0)
                .opacity(amount <= 0 ? 0.5 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private func stepButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(Color(.secondarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
    }

    /// ≈10% of the current amount, snapped like the tray editor's stepper.
    private var amountStep: Double {
        if amount > 0 {
            return DoseStepping.niceStep(for: amount)
        }
        return switch unit {
        case "µg": 10
        case "g": 0.5
        default: 5
        }
    }

    // MARK: Seeding

    private func toggle(_ result: QuickLogSearchResult) {
        guard expandedID != result.id else {
            expandedID = nil
            return
        }
        let seed = payload(for: result)
        amount = seed.amount
        unit = seed.unit
        expandedID = result.id
    }

    /// The stage payload for one hit at the currently dialed amount. Recents
    /// prefill from their most recent chip; library hits from the reference
    /// dose for the default route.
    private func payload(for result: QuickLogSearchResult) -> QuickLogStagePayload {
        switch result {
        case let .recent(card):
            let group = card.routes.first
            let chipUnit = group?.doses.first?.unit ?? "mg"
            let seeded = expandedID == result.id
                ? amount
                : group?.doses.first?.amount ?? 0
            return QuickLogStagePayload(
                substance: card.substanceName,
                route: group?.route ?? .oral,
                unit: chipUnit,
                amount: seeded,
                colorHex: card.colorHex,
                librarySubstance: group?.librarySubstance,
            )
        case let .library(substance), let .custom(substance):
            let route = substance.defaultRoute
            let unit = substance.defaultUnit
            let seeded = expandedID == result.id
                ? amount
                : StagedDose.lookupReferenceDose(substance: substance, route: route, unit: unit) ?? 0
            return QuickLogStagePayload(
                substance: substance.name,
                route: route,
                unit: unit,
                amount: seeded,
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
                Text("Create custom substance")
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer()
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
