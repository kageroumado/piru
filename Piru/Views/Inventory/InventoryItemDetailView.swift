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

    private var colorMap: [String: Color] { Array(substanceColors).colorMap }
    private var runOut: InventoryMath.RunOut? { InventoryMath.runOut(for: item, in: modelContext) }

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
                    Image(systemName: "pencil")
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
            VStack(alignment: .leading, spacing: 14) {
                StockAmountText(item: item, style: .largeTitle)
                    .accessibilityLabel(accessibilityAmount)

                if let fraction = item.fillFraction {
                    InventorySupplyBar(fraction: fraction, tint: item.stockStatus.barTint)
                }

                if let runOut {
                    Text(runOutLine(runOut))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                    HStack(spacing: 6) {
                        Text(basisLine(runOut))
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                        Button {
                            showBasisInfo = true
                        } label: {
                            Image(systemName: "info.circle").font(.caption)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("How this is calculated")
                    }
                }

                Button {
                    navigator.present(.inventoryItemForm(id: item.id))
                } label: {
                    Text("Restock")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 2)
            }
            .padding(.vertical, 6)
            .listRowBackground(Theme.cardBackground)
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
                    title: String(localized: "Dose"),
                    amount: "−\(dose.amount.doseFormatted) \(dose.unit)",
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
                title: title(for: event.kind),
                amount: amountLabel(event),
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

    private func runOutLine(_ runOut: InventoryMath.RunOut) -> String {
        inventoryRunOutLine(for: item, runOut: runOut)
    }

    private func basisLine(_ runOut: InventoryMath.RunOut) -> String {
        let avg = "\(runOut.dailyAvg.doseFormatted) \(item.unit)"
        if let size = item.doseSize, size > 0 {
            return String(localized: "Single dose \(size.doseFormatted) \(item.unit) · daily avg \(avg)")
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

    private func title(for kind: ManualEvent.Kind) -> String {
        switch kind {
        case .initial: String(localized: "Initial")
        case .restock: String(localized: "Restock")
        case .adjustment: String(localized: "Adjustment")
        }
    }

    private func amountLabel(_ event: ManualEvent) -> String {
        let sign = event.amount >= 0 ? "+" : "−"
        return "\(sign)\(abs(event.amount).doseFormatted) \(item.unit)"
    }

    private var accessibilityAmount: String {
        switch item.stockStatus {
        case .out:
            return String(localized: "\(item.substance), out of stock")
        case .low:
            return String(localized: "\(item.substance), \(item.currentQuantity.doseFormatted) \(item.unit) in stock, low")
        case .ok:
            return String(localized: "\(item.substance), \(item.currentQuantity.doseFormatted) \(item.unit) in stock")
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
    let title: String
    let amount: String
    let date: Date
    let note: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: glyph)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
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
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
    }
}
