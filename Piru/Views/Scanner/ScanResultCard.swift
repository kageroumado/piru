import SwiftUI

/// The floating card at the bottom of the scanner. It reflects the live
/// recognition state — a hint while scanning, the resolved substance with an
/// "Add to Log" action, or a no-match with a manual-search fallback.
struct ScanResultCard: View {
    let phase: LabelScanModel.Phase
    let onAdd: (ResolvedDrug) -> Void
    let onSearch: (String) -> Void
    let onRescan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(.snappy, value: phaseKey)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .scanning:
            Label("Point at a barcode or label, then tap a highlighted area", systemImage: "viewfinder")
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case .resolving:
            HStack(spacing: 10) {
                ProgressView()
                Text("Resolving…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case let .resolved(resolved):
            resolvedContent(resolved)

        case let .noMatch(text, canSearch):
            noMatchContent(text: text, canSearch: canSearch)
        }
    }

    private func resolvedContent(_ resolved: ResolvedDrug) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(resolved.brandName ?? resolved.substance.displayTitle)
                    .font(.headline)
                if let brand = resolved.brandName, brand.caseInsensitiveCompare(resolved.substance.name) != .orderedSame {
                    Text(resolved.substance.displayTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(detailLine(resolved))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button { onAdd(resolved) } label: {
                    Label("Add to Log", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button("Scan Again", action: onRescan)
                    .buttonStyle(.bordered)
            }
        }
    }

    private func noMatchContent(text: String, canSearch: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No match")
                .font(.headline)

            if canSearch, !text.isEmpty {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button { onSearch(text) } label: {
                        Label("Search", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Scan Again", action: onRescan)
                        .buttonStyle(.bordered)
                }
            } else {
                Text("Point the camera at the printed drug name.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Scan Again", action: onRescan)
                    .buttonStyle(.bordered)
            }
        }
    }

    /// "36 mg · Oral" — the strength (when read) and route of the resolved dose.
    private func detailLine(_ resolved: ResolvedDrug) -> String {
        let route = String(localized: resolved.stagingRoute.localizedName)
        if resolved.strength != nil {
            let dose = "\(resolved.stagingAmount.doseFormatted) \(resolved.stagingUnit)"
            return "\(dose) · \(route)"
        }
        return route
    }

    /// A cheap discriminant so `.animation(value:)` fires on phase changes without
    /// requiring the payloads to be `Equatable`.
    private var phaseKey: Int {
        switch phase {
        case .scanning: 0
        case .resolving: 1
        case .resolved: 2
        case .noMatch: 3
        }
    }
}
