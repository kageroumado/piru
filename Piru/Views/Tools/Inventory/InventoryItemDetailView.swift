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
    @Environment(\.profileDirectory) private var directory

    @State private var showBasisInfo = false
    /// The merged history, derived in `.task(id: historyToken)`; `nil` until the first pass.
    @State private var historyRows: [HistoryRow]?

    /// The profile sharing this item with the active one; `nil` for the
    /// active profile's own item.
    private var owner: PiruProfile? {
        SharedInventory.shared.owner(of: item)
    }

    /// What the history depends on: the dose log, the item's events, its quantity (which every
    /// refresh of other profiles' doses against it rewrites), its owner and the profiles.
    private var historyToken: Int {
        var hasher = Hasher()
        hasher.combine(DoseLogService.shared.revision)
        hasher.combine(item.manualEvents)
        hasher.combine(item.currentQuantity)
        hasher.combine(owner)
        hasher.combine(directory.profiles)
        return hasher.finalize()
    }

    private var runOut: InventoryMath.RunOut? {
        InventoryMath.runOut(for: item, in: modelContext)
    }

    var body: some View {
        List {
            headerSection
            substanceInfoSection
            historySection
        }
        .insetGroupedListStyle()
        .themedPage()
        .navigationTitle(item.displayTitle)
        .inlineNavigationTitle()
        .toolbar {
            #if os(iOS)
                ToolbarItem(placement: .platformTopBarTrailing) {
                    Button {
                        navigator.present(.inventoryItemEdit(id: item.id))
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Edit")
                }
            #else
                ToolbarItem(placement: .automatic) {
                    Button {
                        navigator.present(.inventoryItemEdit(id: item.id))
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Edit")
                }
            #endif
        }
        // Re-derive when returning from a restock/edit sheet or a dose change.
        .onAppear {
            SharedInventory.write(to: item) { InventoryService.recompute(item, in: modelContext) }
        }
        .task(id: historyToken) {
            historyRows = buildHistoryRows()
        }
        .alert("Run-out estimate", isPresented: $showBasisInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Estimated from your average daily use over the last 7 days. Shown only when you've dosed on most days, so a one-off doesn't skew it.")
        }
    }

    // MARK: - Substance info

    /// The way out of the stockroom and into the reference. Inventory knows the
    /// substance already (`item.substance` resolves its display title); this
    /// row is the link into `SubstanceLibrary`, matching the dose screen's row.
    @ViewBuilder private var substanceInfoSection: some View {
        if let info = SubstanceLibrary.lookup(item.substance) {
            Section {
                RouteLink(PushRoute.substance(name: info.name)) {
                    Label("Substance Info", systemImage: "info.circle")
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            VStack(spacing: 14) {
                heroAmount
                    .accessibilityLabel(accessibilityAmount)

                SharedStockLine(owner: owner, sharees: owner == nil ? SharedInventory.shared.sharees(of: item) : [])

                if let supplyLine = inventorySupplyLine(for: item, runOut: runOut) {
                    VStack(spacing: Spacing.xs) {
                        Text(supplyLine)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                        if let runOut {
                            Button {
                                showBasisInfo = true
                            } label: {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: "info.circle")
                                        .accessibilityHidden(true)
                                    Text(basisLine(runOut))
                                }
                                .captionSecondary()
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("How this is calculated")
                        }
                    }
                }

                if let fraction = item.fillFraction {
                    InventorySupplyBar(fraction: fraction, tint: item.stockStatus.barTint, thickness: 12, status: item.stockStatus)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.top, Spacing.xxs)
                }

                Button {
                    navigator.present(.inventoryItemForm(id: item.id))
                } label: {
                    Text("Restock")
                        .cardTitle()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .padding(.top, Spacing.xxs)
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.vertical, Spacing.md)
            .listRowBackground(CardBackground())
        }
    }

    /// The centered hero amount — a big number with its unit, or "Out".
    @ViewBuilder
    private var heroAmount: some View {
        let status = item.stockStatus
        if status == .out {
            Text("Out")
                .font(.heroStat)
                .foregroundStyle(status.numberColor)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(item.currentQuantity.inventoryFormatted)
                    .font(.heroStat)
                    .foregroundStyle(status.numberColor)
                Text(item.unit)
                    .font(.piru(.title3, weight: .medium))
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }

    // MARK: - History

    private var historySection: some View {
        Section {
            if let rows = historyRows, rows.isEmpty {
                Text("No restocks or entries yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .listRowBackground(CardBackground())
            } else if let rows = historyRows {
                ForEach(rows) { row in
                    rowView(row)
                        .listRowBackground(CardBackground())
                }
            }
        } header: {
            Text("History")
        }
    }

    @ViewBuilder
    private func rowView(_ row: HistoryRow) -> some View {
        switch row {
        case let .shared(dose, profile):
            // Logged in another journal: shown, never opened or deleted from here.
            HistoryRowLabel(
                glyph: "pills",
                tint: Theme.secondaryLabel,
                title: String(localized: "Dose"),
                amount: "−\(dose.amount.inventoryFormatted) \(dose.unit)",
                amountColor: Theme.secondaryLabel,
                date: dose.timestamp,
                note: profile.name,
                avatar: profile,
            )

        case let .dose(dose):
            RouteLink(PushRoute.entry(timestamp: dose.timestamp, id: dose.id)) {
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
                amountColor: event.amount >= 0 ? Color.successText : Theme.secondaryLabel,
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

    /// The item's own store's doses, its sharees' doses (each with their
    /// avatar), and its manual events, newest first. On a shared-in item the
    /// owner's doses are another journal's too, so they show as theirs.
    private func buildHistoryRows() -> [HistoryRow] {
        let own = InventoryMath.doses(for: item, in: modelContext)
        let doseRows: [HistoryRow] = if let owner {
            own.map {
                .shared(ForeignDose(profileID: owner.id, entryID: $0.id, amount: $0.amount, unit: $0.unit, timestamp: $0.timestamp), owner)
            }
        } else {
            own.map { HistoryRow.dose($0) }
        }
        let sharedRows = SharedInventory.foreignDoses(for: item).compactMap { dose in
            directory.profile(id: dose.profileID).map { HistoryRow.shared(dose, $0) }
        }
        let manualRows = item.manualEvents.map { HistoryRow.manual($0) }
        return (doseRows + sharedRows + manualRows).sorted { $0.date > $1.date }
    }

    // MARK: - Mutations

    private func deleteDose(_ dose: DoseEntry) {
        // Drop the row before the entry is deleted, so no pass reads a deleted model.
        historyRows?.removeAll { $0.id == HistoryRow.dose(dose).id }
        SessionEditingService.shared.delete(dose, in: modelContext)
        InventoryService.recompute(item, in: modelContext)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func deleteEvent(_ event: ManualEvent) {
        SharedInventory.write(to: item) {
            item.manualEvents.removeAll { $0.id == event.id }
            InventoryService.recompute(item, in: modelContext)
        }
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
    /// A dose from another profile's journal, and that profile.
    case shared(ForeignDose, PiruProfile)
    case manual(ManualEvent)

    var id: String {
        switch self {
        case let .dose(dose): "dose-\(dose.id.uuidString)"
        case let .shared(dose, profile): "shared-\(profile.id.uuidString)-\(dose.entryID.uuidString)"
        case let .manual(event): "manual-\(event.id.uuidString)"
        }
    }

    var date: Date {
        switch self {
        case let .dose(dose): dose.timestamp
        case let .shared(dose, _): dose.timestamp
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
    /// Whose dose this is, drawn in place of the glyph.
    var avatar: PiruProfile?

    var body: some View {
        HStack(spacing: Spacing.xl) {
            Group {
                if let avatar {
                    ProfileAvatarView(avatar, diameter: 24)
                } else {
                    Image(systemName: glyph)
                        .font(.body)
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 26)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                if let note, !note.isEmpty {
                    Text(note)
                        .captionSecondary()
                        .lineLimit(1)
                }
                Text(date.formatted(.dateTime.month().day().hour().minute()))
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer(minLength: 8)
            Text(amount)
                .sectionLabel()
                .foregroundStyle(amountColor)
                .monospacedDigit()
        }
    }
}
