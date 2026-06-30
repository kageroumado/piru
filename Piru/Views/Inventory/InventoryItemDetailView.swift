import SwiftData
import SwiftUI
import WidgetKit

/// Detail for one inventory item: the current amount, the run-out estimate and
/// its basis, the supply bar (baseline only), a primary Restock action, a nav
/// Edit pencil, and the merged history of manual events and matching doses.
///
/// Built as a `List` so dose rows get native swipe-to-delete; the header lives in
/// its own section styled to read as a card.
struct InventoryItemDetailView: View {
    @Bindable var item: InventoryItem

    @Environment(\.appNavigator) private var navigator
    @Environment(\.modelContext) private var modelContext
    @Query private var substanceColors: [SubstanceColor]

    @State private var showBasisInfo = false

    private var colorMap: [String: Color] {
        Array(substanceColors).colorMap
    }
    private var runOut: InventoryMath.RunOut? {
        InventoryMath.runOut(for: item, in: modelContext)
    }

    var body: some View {
        List {
            headerSection
            historySection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(item.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    navigator.present(.inventoryItemEdit(id: item.id))
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Edit")
            }
        }
        // Re-derive when returning from a restock/edit sheet or a dose change.
        .onAppear { InventoryService.recompute(item, in: modelContext) }
        .alert("Run-out estimate", isPresented: $showBasisInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Estimated from your average daily use over the last 7 days. Shown only when you've dosed on most days, so a one-off doesn't skew it.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            VStack(spacing: 14) {
                heroAmount
                    .accessibilityLabel(accessibilityAmount)

                if let supplyLine = inventorySupplyLine(for: item, runOut: runOut) {
                    VStack(spacing: 4) {
                        Text(supplyLine)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                        if let runOut {
                            Button {
                                showBasisInfo = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle")
                                    Text(basisLine(runOut))
                                }
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryLabel)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("How this is calculated")
                        }
                    }
                }

                if let fraction = item.fillFraction {
                    InventorySupplyBar(fraction: fraction, tint: item.stockStatus.barTint)
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                }

                Button {
                    navigator.present(.inventoryItemForm(id: item.id))
                } label: {
                    Text("Restock")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.vertical, 8)
            .listRowBackground(Theme.cardBackground)
        }
    }

    /// The centered hero amount — a big number with its unit, or "Out".
    @ViewBuilder
    private var heroAmount: some View {
        let status = item.stockStatus
        if status == .out {
            Text("Out")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(status.numberColor)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.currentQuantity.inventoryFormatted)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(status.numberColor)
                Text(item.unit)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }

    // MARK: - History

    private var historySection: some View {
        Section {
            let rows = historyRows
            if rows.isEmpty {
                Text("No restocks or doses yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .listRowBackground(Theme.cardBackground)
            } else {
                ForEach(rows) { row in
                    rowView(row)
                        .listRowBackground(Theme.cardBackground)
                }
            }
        } header: {
            Text("History")
        }
    }

    @ViewBuilder
    private func rowView(_ row: HistoryRow) -> some View {
        switch row {
        case let .dose(dose):
            NavigationLink {
                EntryDetailView(entry: dose)
            } label: {
                HistoryRowLabel(
                    glyph: "pills",
                    tint: Theme.secondaryLabel,
                    title: String(localized: "Dose"),
                    amount: "−\(dose.amount.inventoryFormatted) \(dose.unit)",
                    amountColor: Theme.secondaryLabel,
                    date: dose.timestamp,
                    note: nil,
                )
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { deleteDose(dose) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }

        case let .manual(event):
            HistoryRowLabel(
                glyph: glyph(for: event.kind),
                tint: tint(for: event.kind),
                title: title(for: event.kind),
                amount: amountLabel(event),
                amountColor: event.amount >= 0 ? .green : Theme.secondaryLabel,
                date: event.date,
                note: event.note,
            )
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { deleteEvent(event) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var historyRows: [HistoryRow] {
        let doseRows = InventoryMath.doses(for: item, in: modelContext).map { HistoryRow.dose($0) }
        let manualRows = item.manualEvents.map { HistoryRow.manual($0) }
        return (doseRows + manualRows).sorted { $0.date > $1.date }
    }

    // MARK: - Mutations

    private func deleteDose(_ dose: DoseEntry) {
        DoseNotificationManager.doseDeleted(timestamp: dose.timestamp)
        modelContext.delete(dose)
        InventoryService.recompute(item, in: modelContext)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func deleteEvent(_ event: ManualEvent) {
        item.manualEvents.removeAll { $0.id == event.id }
        InventoryService.recompute(item, in: modelContext)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Run-out copy

    private func basisLine(_ runOut: InventoryMath.RunOut) -> String {
        let avg = "\(runOut.dailyAvg.inventoryFormatted) \(item.unit)"
        if let size = item.doseSize, size > 0 {
            return String(localized: "Single dose \(size.inventoryFormatted) \(item.unit) · daily avg \(avg)")
        }
        return String(localized: "Daily avg \(avg)")
    }

    private func glyph(for kind: ManualEvent.Kind) -> String {
        switch kind {
        case .initial: "plus.circle"
        case .restock: "cart"
        case .adjustment: "slider.horizontal.3"
        }
    }

    private func tint(for kind: ManualEvent.Kind) -> Color {
        switch kind {
        case .initial: Theme.accent
        case .restock: .green
        case .adjustment: .orange
        }
    }

    private func title(for kind: ManualEvent.Kind) -> String {
        switch kind {
        case .initial: String(localized: "Initial")
        case .restock: String(localized: "Restock")
        case .adjustment: String(localized: "Adjustment")
        }
    }

    private func amountLabel(_ event: ManualEvent) -> String {
        let sign = event.amount >= 0 ? "+" : "−"
        return "\(sign)\(abs(event.amount).inventoryFormatted) \(item.unit)"
    }

    private var accessibilityAmount: String {
        switch item.stockStatus {
        case .out:
            String(localized: "\(item.substance), out of stock")
        case .low:
            String(localized: "\(item.substance), \(item.currentQuantity.inventoryFormatted) \(item.unit) in stock, low")
        case .ok:
            String(localized: "\(item.substance), \(item.currentQuantity.inventoryFormatted) \(item.unit) in stock")
        }
    }
}

// MARK: - History model

/// One merged history entry: a logged dose or a manual event.
private enum HistoryRow: Identifiable {
    case dose(DoseEntry)
    case manual(ManualEvent)

    var id: String {
        switch self {
        case let .dose(dose): "dose-\(dose.id.uuidString)"
        case let .manual(event): "manual-\(event.id.uuidString)"
        }
    }

    var date: Date {
        switch self {
        case let .dose(dose): dose.timestamp
        case let .manual(event): event.date
        }
    }
}

/// The visual content of a history row (icon, title, optional note, timestamp,
/// trailing signed amount).
private struct HistoryRowLabel: View {
    let glyph: String
    let tint: Color
    let title: String
    let amount: String
    let amountColor: Color
    let date: Date
    let note: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: glyph)
                .font(.body)
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                if let note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(1)
                }
                Text(date.formatted(.dateTime.month().day().hour().minute()))
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer(minLength: 8)
            Text(amount)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(amountColor)
                .monospacedDigit()
        }
    }
}
