import SwiftUI
import SwiftData
import UserNotifications

// MARK: - Reminder Time Model

struct ReminderTime: Codable, Identifiable, Equatable {
    var id: Int { hour * 60 + minute }
    var hour: Int
    var minute: Int

    var date: Date {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? .now
    }

    var formatted: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct DailyDoseSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DailyDoseItem.sortOrder) private var items: [DailyDoseItem]

    @AppStorage("dailyDoseReminderEnabled") private var reminderEnabled = false
    @AppStorage("dailyDoseReminderTimes") private var reminderTimesData = Data()

    @State private var reminderTimes: [ReminderTime] = []
    @State private var showingAddSheet = false
    @State private var editingItem: DailyDoseItem?
    @State private var showingTimePicker = false
    @State private var newReminderDate = Date.now

    var body: some View {
        List {
            Section {
                Toggle("Daily Reminders", isOn: $reminderEnabled)
                    .onChange(of: reminderEnabled) { _, enabled in
                        if enabled {
                            requestNotificationPermission()
                        } else {
                            cancelAllReminders()
                        }
                    }

                if reminderEnabled {
                    ForEach(reminderTimes.sorted { $0.id < $1.id }) { time in
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text(time.formatted)
                        }
                    }
                    .onDelete(perform: deleteReminder)

                    Button {
                        newReminderDate = Date.now
                        showingTimePicker = true
                    } label: {
                        Label("Add Reminder", systemImage: "plus.circle")
                    }
                }
            } header: {
                Text("Reminders")
            } footer: {
                if reminderEnabled && !reminderTimes.isEmpty {
                    Text("\(reminderTimes.count) daily reminder\(reminderTimes.count == 1 ? "" : "s") scheduled.")
                }
            }

            if items.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            "No Daily Dose Items",
                            systemImage: "pills",
                            description: Text("Add substances you take every day.")
                        )
                        Button {
                            showingAddSheet = true
                        } label: {
                            Text("Add Item")
                                .font(.body.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Section("\(items.count) item\(items.count == 1 ? "" : "s")") {
                    ForEach(items) { item in
                        Button {
                            editingItem = item
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.substance)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text("\(item.amount.formatted()) \(item.unit) \u{2014} \(item.route.displayName)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                    .onDelete(perform: deleteItems)
                    .onMove(perform: moveItems)
                }
            }
        }
        .navigationTitle("Daily Dose")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            if !items.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            DailyDoseItemFormView()
        }
        .sheet(item: $editingItem) { item in
            DailyDoseItemFormView(item: item)
        }
        .sheet(isPresented: $showingTimePicker) {
            NavigationStack {
                Form {
                    DatePicker("Time", selection: $newReminderDate, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                }
                .navigationTitle("Add Reminder")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingTimePicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") { addReminder() }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .onAppear { loadReminderTimes() }
    }

    // MARK: - Daily Dose Items

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(items[index])
        }
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, item) in reordered.enumerated() {
            item.sortOrder = index
        }
    }

    // MARK: - Reminder Times

    private func loadReminderTimes() {
        guard !reminderTimesData.isEmpty,
              let decoded = try? JSONDecoder().decode([ReminderTime].self, from: reminderTimesData) else {
            // Migrate from old single-reminder format
            if reminderEnabled {
                let oldHour = UserDefaults.standard.integer(forKey: "dailyDoseReminderHour")
                let oldMinute = UserDefaults.standard.integer(forKey: "dailyDoseReminderMinute")
                if oldHour != 0 || oldMinute != 0 {
                    reminderTimes = [ReminderTime(hour: oldHour, minute: oldMinute)]
                    saveReminderTimes()
                    return
                }
            }
            reminderTimes = []
            return
        }
        reminderTimes = decoded
    }

    private func saveReminderTimes() {
        reminderTimesData = (try? JSONEncoder().encode(reminderTimes)) ?? Data()
        scheduleAllReminders()
    }

    private func addReminder() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: newReminderDate)
        let newTime = ReminderTime(hour: components.hour ?? 9, minute: components.minute ?? 0)

        // Don't add duplicates
        guard !reminderTimes.contains(where: { $0.id == newTime.id }) else {
            showingTimePicker = false
            return
        }

        reminderTimes.append(newTime)
        saveReminderTimes()
        showingTimePicker = false
    }

    private func deleteReminder(at offsets: IndexSet) {
        let sorted = reminderTimes.sorted { $0.id < $1.id }
        let idsToRemove = offsets.map { sorted[$0].id }
        reminderTimes.removeAll { idsToRemove.contains($0.id) }
        saveReminderTimes()
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                if granted {
                    if reminderTimes.isEmpty {
                        // Add a default 9:00 AM reminder
                        reminderTimes = [ReminderTime(hour: 9, minute: 0)]
                        saveReminderTimes()
                    } else {
                        scheduleAllReminders()
                    }
                } else {
                    reminderEnabled = false
                }
            }
        }
    }

    private func scheduleAllReminders() {
        let center = UNUserNotificationCenter.current()
        // Remove all existing daily dose reminders
        center.removePendingNotificationRequests(withIdentifiers:
            reminderIdentifiers(count: 20) // Remove up to 20 old ones
        )

        guard reminderEnabled else { return }

        for (index, time) in reminderTimes.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Daily Dose"
            content.body = "Time to take your daily medications."
            content.sound = .default

            var dateComponents = DateComponents()
            dateComponents.hour = time.hour
            dateComponents.minute = time.minute

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(
                identifier: "dailyDoseReminder_\(index)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    private func cancelAllReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: reminderIdentifiers(count: 20)
        )
    }

    private func reminderIdentifiers(count: Int) -> [String] {
        // Include old single-reminder ID for migration cleanup
        ["dailyDoseReminder"] + (0..<count).map { "dailyDoseReminder_\($0)" }
    }
}
