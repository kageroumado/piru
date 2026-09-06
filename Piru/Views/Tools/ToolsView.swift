import SwiftData
import SwiftUI

/// A tool surfaced in the Tools tab hub. Each value is pushed as a full-screen
/// destination via `PushRoute.tool`. Kept `nonisolated`/`Codable` so it can ride
/// inside `PushRoute` (state restoration + potential deep links).
nonisolated enum Tool: String, Hashable, Codable, CaseIterable, Identifiable {
    case interactions
    case calculator
    case volumetric
    case recovery
    case pharma
    case ceiling
    case benzoEquivalence
    case opioidEquivalence
    case toleranceInfo
    case inventory
    case effectSandbox
    case steadyState
    case injectionLevels
    case drugClasses
    /// The box scanner as a reference: point the camera at any medication box
    /// and open what the library knows about what is inside.
    case identify

    var id: String {
        rawValue
    }

    /// Row label and pushed-screen title.
    var name: LocalizedStringResource {
        switch self {
        case .interactions: "Interactions"
        case .calculator: "Half-Life Calculator"
        case .volumetric: "Volumetric Dosing"
        case .recovery: "Recovery Guide"
        case .pharma: "Pharma Search"
        case .ceiling: "Ceiling Effect"
        case .benzoEquivalence: "Benzo Equivalence"
        case .opioidEquivalence: "Opioid Equivalence"
        case .toleranceInfo: "How Tolerance Works"
        case .inventory: "Inventory"
        case .effectSandbox: "Effect Estimator"
        case .steadyState: "Steady State"
        case .injectionLevels: "Injection Levels"
        case .drugClasses: "Drug Classes"
        case .identify: "Identify a Box"
        }
    }

    /// One-line description shown under the name in the hub list.
    var subtitle: LocalizedStringResource {
        switch self {
        case .interactions: "Check how substances interact"
        case .calculator: "Estimate active levels over time"
        case .volumetric: "Dilute and measure precise doses"
        case .recovery: "Comedown and aftercare tips"
        case .pharma: "Browse pharmacokinetics for every substance"
        case .ceiling: "When dose and exposure aren't proportional"
        case .benzoEquivalence: "Compare benzodiazepine doses to diazepam"
        case .opioidEquivalence: "Convert opioid doses to morphine (MME)"
        case .toleranceInfo: "Why effects fade and how receptors recover"
        case .inventory: "Track how much you have on hand"
        case .effectSandbox: "Compare substances and preview how they may feel"
        case .steadyState: "Where a repeated dose settles, and when"
        case .injectionLevels: "Project hormone levels from injectable esters"
        case .drugClasses: "What the members of a family share"
        case .identify: "Point at any medication box to see what's inside it"
        }
    }

    var icon: String {
        switch self {
        case .interactions: "exclamationmark.triangle"
        case .calculator: "hourglass"
        case .volumetric: "drop"
        case .recovery: "heart.text.square"
        case .pharma: "pills"
        case .ceiling: "chart.line.uptrend.xyaxis"
        case .benzoEquivalence: "moon.fill"
        case .opioidEquivalence: "cross.case"
        case .toleranceInfo: "chart.line.downtrend.xyaxis"
        case .inventory: "shippingbox"
        case .effectSandbox: "slider.horizontal.2.square"
        case .steadyState: "chart.line.flattrend.xyaxis"
        case .injectionLevels: "syringe"
        case .drugClasses: "square.stack.3d.up"
        case .identify: "barcode.viewfinder"
        }
    }
}

/// The Tools tab root: a hub of tools, each pushing a full-screen view.
///
/// Rich cards with preview state (Inventory, My Meds) and safety-relevant
/// summaries (Interactions) render full-width. Simpler tools sit in a
/// two-column grid to reduce vertical scroll.
struct ToolsView: View {
    /// Tools rendered as half-width compact cards, in order (left-to-right,
    /// top-to-bottom). Education sub-tools, Inventory, My Meds, Interactions,
    /// and Data & Backup have their own full-width cards above the grid.
    private let compactTools: [Tool] = [
        .identify, .effectSandbox,
        .calculator, .steadyState,
        .injectionLevels, .volumetric,
        .pharma,
        .benzoEquivalence, .opioidEquivalence,
    ]

    private let gridColumns = [
        GridItem(.flexible(), spacing: Spacing.xl),
        GridItem(.flexible(), spacing: Spacing.xl),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                MyMedsToolCard()
                InventorySummaryCard()
                InteractionsSummaryCard()
                DataBackupToolCard()
                EducationCard()

                LazyVGrid(columns: gridColumns, spacing: Spacing.xl) {
                    ForEach(compactTools) { tool in
                        ToolCompactCard(tool: tool)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, Spacing.xs)
            .padding(.bottom, 80)
        }
        .background(Theme.background)
        .appNavigationBar("Tools")
    }
}

/// A half-width tool card: tinted icon, title, and subtitle in a compact
/// `themeCard`, matching the Search tab's class browse grid density.
private struct ToolCompactCard: View {
    let tool: Tool

    var body: some View {
        NavigationLink(value: PushRoute.tool(tool)) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Image(systemName: tool.icon)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text(tool.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(tool.subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Pushes `DataStorageView` — the record's own tool: what is stored on the
/// device, iCloud backup, export and import, recovery snapshots, and the
/// substance database. The same screen stays reachable from Settings.
private struct DataBackupToolCard: View {
    var body: some View {
        GlanceCard(icon: "externaldrive", title: Text("Data & Backup"), route: .dataStorage) {
            Text("Export, import, and encrypted backups")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MyMedsToolCard: View {
    @Query(sort: \DailyDoseItem.sortOrder) private var items: [DailyDoseItem]
    @Query private var todayEntries: [DoseEntry]
    @Query private var recentOccurrences: [RoutineOccurrence]

    @State private var warmed = false

    init() {
        let dayStart = Calendar.current.startOfDay(for: .now)
        _todayEntries = Query(
            filter: #Predicate<DoseEntry> { $0.timestamp >= dayStart },
            sort: \DoseEntry.timestamp,
        )
        let yesterdayStart = Self.yesterdayStart
        _recentOccurrences = Query(
            filter: #Predicate<RoutineOccurrence> { $0.dueDay >= yesterdayStart },
        )
    }

    private static var yesterdayStart: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .day, value: -1, to: today) ?? today
    }

    private var todayOccurrences: [RoutineOccurrence] {
        let today = Calendar.current.startOfDay(for: .now)
        return recentOccurrences.filter { $0.dueDay >= today }
    }

    var body: some View {
        let scheduled = items.filter { !$0.isAsNeeded }
        GlanceCard(icon: "pills", title: Text("My Meds"), route: .myMeds) {
            if scheduled.isEmpty {
                Text("Set up your daily medications and supplements")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let slots = MyMedsModel.slots(items: items, occurrences: todayOccurrences)
                VStack(spacing: 0) {
                    ForEach(slots.prefix(3), id: \.id) { slot in
                        medsRow(slot)
                    }
                    if slots.count > 3 {
                        GlanceMoreRow(count: slots.count - 3)
                            .padding(.top, Spacing.xs)
                    }
                }

                let nextSlot = slots.first { $0.state == .pending && !$0.isDueNow && $0.time != nil }
                if let nextSlot {
                    nextDueLine(slot: nextSlot)
                }
            }
        }
        .task {
            await SubstanceStore.shared.ensureAllLoaded()
            warmed = true
        }
    }

    private func medsRow(_ slot: MyMedsCard.MedSlot) -> some View {
        HStack(spacing: Spacing.lg) {
            slotCircle(slot)
                .frame(width: 18, height: 18)
            Text(displayName(for: slot.item))
                .font(.subheadline.weight(slot.taken ? .regular : .medium))
                .foregroundStyle(slot.taken ? Theme.secondaryLabel : .primary)
                .strikethrough(slot.taken, color: Theme.secondaryLabel.opacity(Theme.Opacity.dimmed))
                .lineLimit(1)
            Spacer(minLength: 4)
            HStack(spacing: Spacing.xs) {
                Text("\(slot.item.amount.doseFormatted) \(slot.item.unit)")
                    .font(.footnote.monospacedDigit())
                if let time = slot.time {
                    Text("·")
                    Text(Self.timeText(time))
                        .font(.footnote.monospacedDigit())
                }
            }
            .foregroundStyle(Theme.secondaryLabel)
            .lineLimit(1)
        }
        .padding(.vertical, Spacing.xs)
    }

    @ViewBuilder
    private func slotCircle(_ slot: MyMedsCard.MedSlot) -> some View {
        switch slot.state {
        case .taken:
            Image(systemName: "circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.accent)
        case .skipped:
            Image(systemName: "minus.circle")
                .font(.system(size: 16))
                .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.muted))
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 16))
                .foregroundStyle(slot.isDueNow ? Theme.accent : Color.platformTertiarySystemFill)
        }
    }

    private func nextDueLine(slot: MyMedsCard.MedSlot) -> some View {
        HStack(spacing: Spacing.lg) {
            Image(systemName: "clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
                .frame(width: 18)
            Text("Next: \(displayName(for: slot.item)) at \(Self.timeText(slot.time!))")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, Spacing.sm)
    }

    private func displayName(for item: DailyDoseItem) -> String {
        if warmed {
            item.productName ?? CustomSubstanceStore.shared.displayName(for: item.substance)
        } else {
            item.productName ?? item.substance
        }
    }

    private static func timeText(_ minutes: Int) -> String {
        let date = Calendar.current.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now,
        ) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
