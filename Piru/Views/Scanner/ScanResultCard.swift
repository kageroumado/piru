import SwiftUI

/// The floating card at the bottom of the scanner. It reflects the live
/// recognition state — a hint while scanning, the resolved substance with an
/// "Add to Log" action, or a no-match with a manual-search fallback.
struct ScanResultCard: View {
    let phase: LabelScanModel.Phase
    let onAdd: (ResolvedDrug) -> Void
    let onSearch: (String) -> Void
    let onRescan: () -> Void
    /// Identify mode: hand over the reading gathered so far.
    var onCapture: (BoxReading) -> Void = { _ in }

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

        case let .reading(reading, barcodeKnown):
            readingContent(reading, barcodeKnown: barcodeKnown)
        }
    }

    /// Identify mode: a running tally of what the camera has read, and the
    /// button that turns it into an answer. The count is what keeps the user
    /// pointing — a box reads in over a second or two, not at once.
    private func readingContent(_ reading: BoxReading, barcodeKnown: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if reading.isEmpty {
                Label("Point at the box — name, strength, barcode", systemImage: "barcode.viewfinder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Label(readingSummary(reading, barcodeKnown: barcodeKnown), systemImage: barcodeKnown ? "checkmark.circle" : "text.viewfinder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button { onCapture(reading) } label: {
                Label("Identify", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(reading.isEmpty)
        }
    }

    private func readingSummary(_ reading: BoxReading, barcodeKnown: Bool) -> String {
        let lines = String(localized: "\(reading.texts.count) lines read")
        if barcodeKnown { return String(localized: "Barcode recognized · \(lines)") }
        if !reading.barcodes.isEmpty { return String(localized: "Barcode read · \(lines)") }
        return lines
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
        case .reading: 4
        }
    }
}
