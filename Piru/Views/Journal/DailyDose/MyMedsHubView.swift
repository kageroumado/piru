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
}

// MARK: - Hub

/// The one front door for everything a user takes on a schedule — replaces
/// the Routines screen. Meds auto-group by time of day; add/edit/detail are
/// local sheets so the hub works both as a navigator sheet and pushed.
struct MyMedsHubView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DailyDoseItem.sortOrder) private var items: [DailyDoseItem]

    @State private var showingAddMed = false
    @State private var detailItem: DailyDoseItem?

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
                            MedRow(item: item, group: group) { detailItem = item }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: group.symbol)
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
                } footer: {
                    Text("Quiet meds share one reminder per time of day and stay off the timeline graphs. As-needed meds are never counted against you.")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notification Settings", systemImage: "bell.badge")
                    }
                } footer: {
                    Text("Reminders, Ask Again, quiet hours, and everything else Piru sends.")
                }
                .listRowBackground(CardBackground())
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("My Meds")
        .navigationBarTitleDisplayMode(.large)
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
        .sheet(item: $detailItem) { item in
            MedDetailView(item: item)
        }
    }

    private var emptyState: some View {
        Section {
            VStack(spacing: 16) {
                ContentUnavailableView(
                    "No Meds Yet",
                    systemImage: "pills",
                    description: Text("Keep track of what you take and when — one tap to set up gentle reminders. Prescriptions, supplements, vitamins: anything on a schedule."),
                )
                Button {
                    showingAddMed = true
                } label: {
                    Label("Add a Med", systemImage: "plus")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
            }
        }
        .listRowBackground(CardBackground())
    }

    private var addMedButton: some View {
        Button {
            showingAddMed = true
        } label: {
            Label("Add a Med", systemImage: "plus")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.accent)
    }

    private func belongs(_ item: DailyDoseItem, to group: MedTimeGroup) -> Bool {
        if item.isAsNeeded {
            return group == .asNeeded
        }
        let times = item.reminderTimesMinutes
        guard !times.isEmpty else { return group == .anytime }
        return times.contains { MedTimeGroup.group(forMinutes: $0) == group }
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
            HStack(spacing: 12) {
                Image(systemName: "pill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Theme.accent, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.productName ?? CustomSubstanceStore.shared.displayName(for: item.substance))
                            .font(.body)
                            .foregroundStyle(.primary)
                        if item.isQuiet {
                            Text("quiet")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                                .foregroundStyle(Theme.secondaryLabel)
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
                    .foregroundStyle(Theme.secondaryLabel)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        let dose = "\(item.amount.doseFormatted) \(item.unit)"
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
            text += " · \(String(localized: item.frequency.shortLabel))"
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
