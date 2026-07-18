import SwiftData
import SwiftUI
import UserNotifications

/// Reminders-style management for routines: a list of named routines (like
/// Reminders' lists), each opening a detail screen with its name, optional
/// time of day + daily reminder, and its items.
struct RoutinesSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DoseRoutine.sortOrder) private var routines: [DoseRoutine]
    @Query(sort: \DailyDoseItem.sortOrder) private var items: [DailyDoseItem]

    @State private var showingNewRoutine = false
    @State private var newRoutineName = ""
    @State private var editingItem: DailyDoseItem?

    /// Items whose category doesn't match any routine (deleted routine,
    /// import) — kept visible so nothing is unreachable.
    private var unassignedItems: [DailyDoseItem] {
        let names = Set(routines.map(\.name))
        return items.filter { !names.contains($0.category) }
    }

    var body: some View {
        List {
            if routines.isEmpty, items.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            "No Routines",
                            systemImage: "repeat",
                            description: Text("Group the meds and supplements you take together — Pre-workout, Night — and stage a whole set with one tap."),
                        )
                        Button {
                            promptNewRoutine()
                        } label: {
                            Text("New Routine")
                                .font(.body.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .listRowBackground(CardBackground())
            } else {
                Section {
                    ForEach(routines) { routine in
                        NavigationLink {
                            RoutineDetailView(routine: routine)
                        } label: {
                            routineRow(routine)
                        }
                    }
                    .onMove(perform: moveRoutines)
                    .onDelete(perform: deleteRoutines)

                    Button {
                        promptNewRoutine()
                    } label: {
                        Label("New Routine", systemImage: "plus.circle")
                    }
                }
                .listRowBackground(CardBackground())

                if !unassignedItems.isEmpty {
                    Section("Unassigned") {
                        ForEach(unassignedItems) { item in
                            RoutineItemRow(item: item) { editingItem = item }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                modelContext.delete(unassignedItems[index])
                            }
                        }
                    }
                    .listRowBackground(CardBackground())
                }
            }

            Section {
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    Label("Notification Settings", systemImage: "bell.badge")
                }
            } footer: {
                Text("Choose which notifications Piru sends — routine reminders, session alerts, safety warnings, and low-stock alerts.")
            }
            .listRowBackground(CardBackground())
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Routines")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    promptNewRoutine()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Routine")
            }
        }
        .alert("New Routine", isPresented: $showingNewRoutine) {
            TextField("Name", text: $newRoutineName)
            Button("Add") { addRoutine() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("e.g. Morning, Pre-workout, Night")
        }
        .sheet(item: $editingItem) { item in
            MedicationItemFormView(item: item)
        }
    }

    /// Reminders-style row: tinted icon disc, name, item count + time.
    private func routineRow(_ routine: DoseRoutine) -> some View {
        let count = items.count(where: { $0.category == routine.name })
        return HStack(spacing: 12) {
            Image(systemName: RoutineIcon.symbol(for: routine.name))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Theme.accent, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(routine.name)
                    .font(.body)
                HStack(spacing: 4) {
                    Text("\(count) item\(count == 1 ? "" : "s")")
                    if let time = routine.timeAsDate {
                        Middot()
                        Text(time, style: .time)
                        if routine.remind {
                            Image(systemName: "bell.fill")
                                .font(.caption2)
                                .accessibilityLabel("Reminder on")
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }

    private func promptNewRoutine() {
        newRoutineName = ""
        showingNewRoutine = true
    }

    private func addRoutine() {
        let trimmed = newRoutineName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !routines.contains(where: { $0.name == trimmed }) else { return }
        let nextOrder = (routines.map(\.sortOrder).max() ?? -1) + 1
        modelContext.insert(DoseRoutine(name: trimmed, sortOrder: nextOrder))
    }

    private func moveRoutines(from source: IndexSet, to destination: Int) {
        var ordered = routines
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, routine) in ordered.enumerated() {
            routine.sortOrder = index
        }
    }

    private func deleteRoutines(at offsets: IndexSet) {
        for index in offsets {
            let routine = routines[index]
            // Items survive the routine — they fall to Unassigned.
            for item in items where item.category == routine.name {
                item.category = ""
            }
            modelContext.delete(routine)
        }
        DoseNotificationManager.syncRoutineReminders(in: modelContext)
    }
}

// MARK: - Routine Detail

/// One routine, Reminders-detail-style: rename field, time-of-day toggle +
/// picker with an optional daily reminder, and the routine's items.
struct RoutineDetailView: View {
    @Bindable var routine: DoseRoutine

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DailyDoseItem.sortOrder) private var allItems: [DailyDoseItem]
    @Query(sort: \DoseRoutine.sortOrder) private var routines: [DoseRoutine]

    /// Renames are staged and applied on commit so every keystroke doesn't
    /// cascade through the items' category strings (and half-typed names
    /// can't collide with the unique constraint).
    @State private var name = ""
    @State private var showingAddItem = false
    @State private var editingItem: DailyDoseItem?
    @State private var prefs = NotificationPreferencesStore.shared
    /// Whether the OS-level grant is denied — the reminder then can't be
    /// delivered no matter what the per-type toggle says.
    @State private var systemDenied = false

    private var routineItems: [DailyDoseItem] {
        allItems.filter { $0.category == routine.name }
    }

    var body: some View {
        List {
            Section {
                TextField("Routine Name", text: $name)
                    .onSubmit(applyRename)
            }
            .listRowBackground(CardBackground())

            Section {
                Toggle(isOn: hasTime) {
                    Label("Time", systemImage: "clock")
                }
                if routine.timeMinutes != nil {
                    DatePicker(
                        "Time of day",
                        selection: timeAsDate,
                        displayedComponents: .hourAndMinute,
                    )
                    Toggle(isOn: $routine.remind) {
                        Label("Remind Me", systemImage: "bell")
                    }
                    if routine.remind {
                        Picker(selection: $routine.followUpMinutes) {
                            Text("Never").tag([Int]())
                            Text("10 minutes later").tag([10])
                            Text("10 and 30 minutes later").tag([10, 30])
                        } label: {
                            Label("Ask Again", systemImage: "clock.arrow.circlepath")
                        }
                        NavigationLink {
                            NotificationSettingsView()
                        } label: {
                            Label("Notification Settings", systemImage: "bell.badge")
                        }
                    }
                }
            } footer: {
                if routine.remind, routine.timeMinutes != nil {
                    if !prefs.isEffectivelyEnabled(.routine) {
                        Text("Routine reminders are turned off in Notification Settings, so this reminder won't be delivered.")
                            .foregroundStyle(.orange)
                    } else if systemDenied {
                        Text("Notifications for Piru are off in the system Settings, so this reminder won't be delivered.")
                            .foregroundStyle(.orange)
                    } else {
                        Text("A notification repeats daily at this time.")
                    }
                }
            }
            .listRowBackground(CardBackground())

            Section("Items") {
                ForEach(routineItems) { item in
                    RoutineItemRow(item: item) { editingItem = item }
                }
                .onDelete { offsets in
                    for index in offsets {
                        modelContext.delete(routineItems[index])
                    }
                }

                Button {
                    showingAddItem = true
                } label: {
                    Label("Add Item", systemImage: "plus.circle")
                }
            }
            .listRowBackground(CardBackground())

            Section {
                Button("Delete Routine", role: .destructive) {
                    deleteRoutine()
                }
            }
            .listRowBackground(CardBackground())
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(routine.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddItem) {
            MedicationItemFormView(initialCategory: routine.name)
        }
        .sheet(item: $editingItem) { item in
            MedicationItemFormView(item: item)
        }
        .onAppear { name = routine.name }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            systemDenied = settings.authorizationStatus == .denied
        }
        .onDisappear {
            applyRename()
            DoseNotificationManager.syncRoutineReminders(in: modelContext)
        }
        .onChange(of: routine.remind) { syncReminders() }
        .onChange(of: routine.timeMinutes) { syncReminders() }
        .onChange(of: routine.followUpMinutes) { syncReminders() }
    }

    // MARK: Bindings

    private var hasTime: Binding<Bool> {
        Binding(
            get: { routine.timeMinutes != nil },
            set: { on in
                withAnimation(.snappy) {
                    if on {
                        routine.timeMinutes = routine.timeMinutes ?? 9 * 60
                    } else {
                        routine.timeMinutes = nil
                        routine.remind = false
                    }
                }
            },
        )
    }

    private var timeAsDate: Binding<Date> {
        Binding(
            get: { routine.timeAsDate ?? .now },
            set: { routine.timeAsDate = $0 },
        )
    }

    // MARK: Actions

    private func applyRename() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != routine.name else { return }
        guard !routines.contains(where: { $0.name == trimmed && $0.persistentModelID != routine.persistentModelID }) else {
            name = routine.name
            return
        }
        // Items join by name — the rename must cascade.
        for item in allItems where item.category == routine.name {
            item.category = trimmed
        }
        routine.name = trimmed
    }

    private func deleteRoutine() {
        for item in routineItems {
            item.category = ""
        }
        modelContext.delete(routine)
        DoseNotificationManager.syncRoutineReminders(in: modelContext)
        dismiss()
    }

    private func syncReminders() {
        DoseNotificationManager.syncRoutineReminders(in: modelContext)
    }
}

// MARK: - Shared bits

/// Item row used by both the routine detail and the Unassigned section.
private struct RoutineItemRow: View {
    let item: DailyDoseItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.productName ?? CustomSubstanceStore.shared.displayName(for: item.substance))
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text("\(item.amount.doseFormatted) \(item.unit) \u{2014} \(String(localized: item.route.localizedName))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                    if item.frequency != .daily {
                        Text(item.frequency.shortLabel)
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Symbol for a routine pill/row, inferred from common names.
enum RoutineIcon {
    static func symbol(for name: String) -> String {
        switch name.lowercased() {
        case "morning": "sunrise"
        case "afternoon", "noon", "midday": "sun.max"
        case "evening": "sunset"
        case "night", "bedtime": "moon"
        default: "pills"
        }
    }
}
