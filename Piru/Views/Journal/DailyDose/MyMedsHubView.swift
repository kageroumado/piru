import SwiftData
import SwiftUI

// MARK: - Time-of-day groups

/// The derived time-of-day buckets of the My Meds hub
/// (Specs/meds-reminders-redesign.md): a med's reminder times slot it into
/// Morning/Afternoon/Evening/Night automatically — no named containers to
/// create. Meds without times are "Anytime"; PRN meds get their own group.
enum MedTimeGroup: Int, CaseIterable, Identifiable {
    case morning
    case afternoon
    case evening
    case night
    case anytime
    case asNeeded

    var id: Int {
        rawValue
    }

    static func group(forMinutes minutes: Int) -> MedTimeGroup {
        switch minutes {
        case ..<720: .morning
        case ..<1_020: .afternoon
        case ..<1_260: .evening
        default: .night
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        case .night: "Night"
        case .anytime: "Anytime"
        case .asNeeded: "As needed"
        }
    }

    var rangeLabel: LocalizedStringResource {
        switch self {
        case .morning: "before 12:00"
        case .afternoon: "12:00 – 17:00"
        case .evening: "17:00 – 21:00"
        case .night: "after 21:00"
        case .anytime: "no set time"
        case .asNeeded: "no schedule"
        }
    }

    var symbol: String {
        switch self {
        case .morning: "sunrise"
        case .afternoon: "sun.max"
        case .evening: "sunset"
        case .night: "moon"
        case .anytime: "pills"
        case .asNeeded: "cross.vial"
        }
    }

    /// Stable string id — rides in notification anchors, deep links
    /// (`piru://quicklog?routine=morning`), and QuickLog group pills.
    var slug: String {
        switch self {
        case .morning: "morning"
        case .afternoon: "afternoon"
        case .evening: "evening"
        case .night: "night"
        case .anytime: "anytime"
        case .asNeeded: "as-needed"
        }
    }

    init?(slug: String) {
        guard let match = Self.allCases.first(where: { $0.slug == slug }) else { return nil }
        self = match
    }

    /// Whether a med shows in this group: PRN meds live in `asNeeded`, meds
    /// without times in `anytime`, and a multi-time med appears in every
    /// group it has a time in.
    static func belongs(_ item: DailyDoseItem, to group: MedTimeGroup) -> Bool {
        if item.isAsNeeded {
            return group == .asNeeded
        }
        let times = item.reminderTimesMinutes
        guard !times.isEmpty else { return group == .anytime }
        return times.contains { Self.group(forMinutes: $0) == group }
    }
}

// MARK: - Hub

/// The one front door for everything a user takes on a schedule — replaces
/// the Routines screen. Meds auto-group by time of day. The hub is a *place*:
/// it pushes med details onto whatever stack hosts it (the Journal tab stack,
/// or the sheet's own bound stack when opened via `.dailyDoseSettings`); only
/// the add/edit *task* is modal.
struct MyMedsHubView: View {
    @Environment(\.appNavigator) private var navigator
    @Environment(\.opensRecordsBesideList) private var opensRecordsBesideList
    @Query(sort: \DailyDoseItem.sortOrder) private var items: [DailyDoseItem]

    @State private var showingAddMed = false
    /// A saved product no med names yet, opened in the add form to become one.
    @State private var adoptingProduct: CustomSubstanceEntry?

    private var groups: [(group: MedTimeGroup, items: [DailyDoseItem])] {
        MedTimeGroup.allCases.compactMap { group in
            let members = items.filter { belongs($0, to: group) }
            return members.isEmpty ? nil : (group, members)
        }
    }

    var body: some View {
        List {
            if items.isEmpty {
                emptyState
            } else {
                ForEach(groups, id: \.group) { group, members in
                    Section {
                        ForEach(members) { item in
                            MedRow(item: item, group: group) {
                                navigator.openRecord(
                                    .medDetail(identityKey: item.identityKey, sortOrder: item.sortOrder),
                                    besideList: opensRecordsBesideList,
                                )
                            }
                        }
                    } header: {
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                            Image(systemName: group.symbol)
                                .accessibilityHidden(true)
                            Text(group.label)
                            Text(group.rangeLabel)
                                .font(.caption2.monospaced())
                                .textCase(nil)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                    .listRowBackground(CardBackground())
                }

                Section {
                    addMedButton
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notification Settings", systemImage: "bell.badge")
                    }
                }
                .listRowBackground(CardBackground())
            }

            UnlistedProductsSection(items: items) { product in
                adoptingProduct = product
            }
        }
        .themedPage()
        .navigationTitle("My Meds")
        #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.large)
        #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddMed = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add a Med")
                }
            }
            .sheet(isPresented: $showingAddMed) {
                MedFormView()
            }
            .sheet(item: $adoptingProduct) { product in
                MedFormView(product: product)
            }
    }

    private var emptyState: some View {
        Section {
            VStack(spacing: Spacing.xxl) {
                ContentUnavailableView(
                    "No Meds Yet",
                    systemImage: "pills",
                    description: Text("Keep track of what you take and when, with gentle reminders set up in one tap. Prescriptions, supplements, vitamins: anything on a schedule."),
                )
                addMedButton
            }
        }
        .listRowBackground(CardBackground())
    }

    private var addMedButton: some View {
        GlassPillButton(title: "Add a Med") {
            showingAddMed = true
        }
    }

    private func belongs(_ item: DailyDoseItem, to group: MedTimeGroup) -> Bool {
        MedTimeGroup.belongs(item, to: group)
    }
}

// MARK: - Unlisted products

/// The combination products no med names, such as one whose med was deleted.
/// Tapping one opens the add form on it, so it becomes an As needed med with
/// its own pill.
private struct UnlistedProductsSection: View {
    let items: [DailyDoseItem]
    let onAdopt: (CustomSubstanceEntry) -> Void

    @State private var store = CustomSubstanceStore.shared

    private var unlisted: [CustomSubstanceEntry] {
        let products = store.productMeds
        let named = Set(items.compactMap { products[$0.substance.lowercased()]?.name })
        return store.all.filter { $0.isCombination && !named.contains($0.name) }
    }

    var body: some View {
        let products = unlisted
        if !products.isEmpty {
            Section {
                ForEach(products) { product in
                    Button {
                        onAdopt(product)
                    } label: {
                        HStack(spacing: Spacing.xl) {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(product.resolvedDisplayName)
                                    .foregroundStyle(.primary)
                                if let listing = product.componentsListing {
                                    Text(listing)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.secondaryLabel)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundStyle(Theme.accent)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Adds it to My Meds")
                }
            } header: {
                Text("Your Products")
            } footer: {
                Text("Products you made, ready to add as a med.")
            }
            .listRowBackground(CardBackground())
        }
    }
}

// MARK: - Row

/// One med in one group. A multi-time med appears once per group it has a
/// time in, showing that group's time first and the others as "also …".
private struct MedRow: View {
    let item: DailyDoseItem
    let group: MedTimeGroup
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.xl) {
                Image(systemName: "pill")
                    .sectionLabel()
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Theme.accent, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.sm) {
                        Text(item.productName ?? CustomSubstanceStore.shared.displayName(for: item.substance))
                            .font(.body)
                            .foregroundStyle(.primary)
                        if item.isQuiet {
                            Text("quiet")
                                .capsuleChip(text: Theme.secondaryLabel, fill: Theme.secondaryLabel)
                        }
                    }
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                }

                Spacer()

                Image(systemName: item.remind && !item.reminderTimesMinutes.isEmpty ? "bell.fill" : "bell.slash")
                    .font(.caption)
                    .foregroundStyle(item.remind && !item.reminderTimesMinutes.isEmpty ? Theme.accent : Theme.secondaryLabel)
                    .accessibilityLabel(item.remind && !item.reminderTimesMinutes.isEmpty ? "Reminders on" : "Reminders off")
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryLabel)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        let dose = item.doseLabel
        if item.isAsNeeded {
            if let limit = item.maxPerDay {
                return "\(dose) · \(String(localized: "up to \(limit)× daily"))"
            }
            return "\(dose) · \(String(localized: "as needed"))"
        }
        let times = item.reminderTimesMinutes
        guard !times.isEmpty else {
            return "\(dose) · \(String(localized: "anytime"))"
        }
        let inGroup = times.filter { MedTimeGroup.group(forMinutes: $0) == group }
        let others = times.filter { MedTimeGroup.group(forMinutes: $0) != group }
        var text = "\(dose) · \(inGroup.map(Self.timeText).joined(separator: " · "))"
        if !others.isEmpty {
            text += " · \(String(localized: "also \(others.map(Self.timeText).joined(separator: ", "))"))"
        }
        if item.frequency != .daily {
            text += " · \(item.frequencyShortLabel)"
        }
        return text
    }

    private static func timeText(_ minutes: Int) -> String {
        let date = Calendar.current.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now,
        ) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
