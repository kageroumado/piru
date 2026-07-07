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

/// The list of search hits beneath the dock's pinned field. Pure
/// presentation: the parent computes the ranked `results` and supplies the
/// staging/open/create actions; this view owns only the row layout.
///
/// The list reads downward from the field — best match first — and the create
/// CTA is pinned as the bottommost row in every search so it's always in the
/// same place.
struct QuickLogSearchResults: View {
    let results: [QuickLogSearchResult]
    let onStageRecent: (SubstanceCard) -> Void
    let onOpenSubstance: (Substance) -> Void
    /// `nil` hides the trailing "Create custom substance" row — the
    /// suggestions surfaces (recents, category browse) reuse these rows
    /// without the create CTA.
    let onCreateCustom: (() -> Void)?

    @State private var customSubstanceStore = CustomSubstanceStore.shared

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

    @ViewBuilder
    private func row(_ result: QuickLogSearchResult) -> some View {
        switch result {
        case let .recent(card):
            resultRow(
                name: customSubstanceStore.displayName(for: card.substanceName),
                source: String(localized: "Recent"),
                tint: card.colorHex.map { Color(hex: $0) } ?? .gray,
                detail: card.routes.first?.librarySubstance.flatMap(substanceDetail)
                    ?? card.routes.first.map { String(localized: $0.route.localizedName) },
            ) {
                onStageRecent(card)
            }
        case let .library(substance):
            resultRow(
                name: substance.displayTitle,
                source: String(localized: "Library"),
                tint: substance.category.color,
                detail: substanceDetail(substance),
            ) {
                onOpenSubstance(substance)
            }
        case let .custom(substance):
            resultRow(
                name: substance.name,
                source: String(localized: "Custom"),
                tint: substance.category.color,
                detail: substanceDetail(substance),
            ) {
                onOpenSubstance(substance)
            }
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

    /// Leading chevron (mirroring the trailing source tag for symmetry),
    /// tinted with the substance/category colour.
    private func resultRow(
        name: String,
        source: String,
        tint: Color,
        detail: String?,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
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
