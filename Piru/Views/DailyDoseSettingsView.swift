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

struct MedicationsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DailyDoseItem.sortOrder) private var items: [DailyDoseItem]

    @AppStorage("dailyDoseReminderEnabled") private var reminderEnabled = false
    @AppStorage("dailyDoseReminderTimes") private var reminderTimesData = Data()
    @AppStorage("dailyDoseCategories") private var categoriesData = Data()

    @State private var reminderTimes: [ReminderTime] = []
    @State private var categories: [String] = []
    @State private var isEditing = false
    @State private var showingAddSheet = false
    @State private var showingAddSheetCategory = ""
    @State private var editingItem: DailyDoseItem?
    @State private var showingTimePicker = false
    @State private var newReminderDate = Date.now
    @State private var showingAddCategory = false
    @State private var newCategoryName = ""
    @State private var editingCategory: String?
    @State private var editedCategoryName = ""

    var body: some View {
        List {
            Group {
            // MARK: - Reminders
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
                                .foregroundStyle(Theme.secondaryLabel)
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

            // MARK: - Categories
            Section {
                ForEach(categories, id: \.self) { cat in
                    HStack {
                        Label(cat, systemImage: iconForCategory(cat))
                        Spacer()
                        Text("\(items.filter { $0.category == cat }.count)")
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    .contentShape(Rectangle())
                    .dropDestination(for: String.self) { droppedKeys, _ in
                        assignItems(keys: droppedKeys, toCategory: cat)
                        return true
                    }
                    .contextMenu {
                        Button {
                            editingCategory = cat
                            editedCategoryName = cat
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            deleteCategory(cat)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: deleteCategories)
                .onMove(perform: moveCategories)

                Button {
                    newCategoryName = ""
                    showingAddCategory = true
                } label: {
                    Label("Add Category", systemImage: "plus.circle")
                }
            } header: {
                Text("Categories")
            } footer: {
                Text("Organize prescriptions by time of day or purpose. Drag items onto a category to assign them.")
            }

            // MARK: - Items
            if items.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            "No Prescriptions",
                            systemImage: "pills",
                            description: Text("Add prescriptions you take regularly.")
                        )
                        Button {
                            showingAddSheetCategory = ""
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
                // Categorized items
                ForEach(categories, id: \.self) { cat in
                    let catItems = items.filter { $0.category == cat }
                    Section("\(cat) \u{2014} \(catItems.count) prescription\(catItems.count == 1 ? "" : "s")") {
                        ForEach(catItems) { item in
                            itemRow(item)
                                .draggable(itemKey(for: item))
                        }
                        .onDelete { offsets in
                            deleteItems(catItems, at: offsets)
                        }

                        Button {
                            showingAddSheetCategory = cat
                            showingAddSheet = true
                        } label: {
                            Label("Add to \(cat)", systemImage: "plus.circle")
                                .font(.subheadline)
                        }
                    }
                }

                // Uncategorized items
                let uncategorized = items.filter { $0.category.isEmpty }
                if !uncategorized.isEmpty {
                    Section(categories.isEmpty ? "\(items.count) prescription\(items.count == 1 ? "" : "s")" : "Uncategorized \u{2014} \(uncategorized.count) prescription\(uncategorized.count == 1 ? "" : "s")") {
                        ForEach(uncategorized) { item in
                            itemRow(item)
                                .draggable(itemKey(for: item))
                        }
                        .onDelete { offsets in
                            deleteItems(uncategorized, at: offsets)
                        }
                    }
                }
            }
            }
            .listRowBackground(Theme.cardBackground)
        }
        .environment(\.editMode, isEditing ? .constant(.active) : .constant(.inactive))
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Prescriptions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheetCategory = ""
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            if !items.isEmpty || !categories.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation { isEditing.toggle() }
                    } label: {
                        Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            MedicationItemFormView(initialCategory: showingAddSheetCategory)
        }
        .sheet(item: $editingItem) { item in
            MedicationItemFormView(item: item)
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
                        Button { showingTimePicker = false } label: { Image(systemName: "xmark") }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button { addReminder() } label: { Image(systemName: "checkmark").fontWeight(.semibold) }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .alert("Add Category", isPresented: $showingAddCategory) {
            TextField("Category name", text: $newCategoryName)
            Button("Add") { addCategory() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("e.g. Morning, Noon, Night")
        }
        .alert("Rename Category", isPresented: Binding(
            get: { editingCategory != nil },
            set: { if !$0 { editingCategory = nil } }
        )) {
            TextField("Category name", text: $editedCategoryName)
            Button("Save") { renameCategory() }
            Button("Cancel", role: .cancel) { editingCategory = nil }
        }
        .onAppear {
            loadReminderTimes()
            loadCategories()
        }
    }

    // MARK: - Item Row

    private func itemRow(_ item: DailyDoseItem) -> some View {
        Button {
            editingItem = item
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.substance)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text("\(item.amount.doseFormatted) \(item.unit) \u{2014} \(item.route.displayName)")
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
            }
            .contentShape(Rectangle())
        }
    }

    // MARK: - Category Helpers

    private func iconForCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "morning": return "sunrise"
        case "afternoon": return "sun.max"
        case "noon", "midday": return "sun.max"
        case "evening": return "sunset"
        case "night", "bedtime": return "moon"
        default: return "tag"
        }
    }

    // MARK: - Drag & Drop

    private func itemKey(for item: DailyDoseItem) -> String {
        item.substance + "|" + String(item.sortOrder)
    }

    private func findItem(byKey key: String) -> DailyDoseItem? {
        let parts = key.split(separator: "|", maxSplits: 1)
        guard parts.count == 2,
              let order = Int(parts[1]) else { return nil }
        let name = String(parts[0])
        return items.first { $0.substance == name && $0.sortOrder == order }
    }

    private func assignItems(keys: [String], toCategory category: String) {
        for key in keys {
            if let item = findItem(byKey: key) {
                item.category = category
            }
        }
    }

    private func deleteCategories(at offsets: IndexSet) {
        for index in offsets {
            deleteCategory(categories[index])
        }
    }

    // MARK: - Categories Management

    private func loadCategories() {
        guard !categoriesData.isEmpty,
              let decoded = try? JSONDecoder().decode([String].self, from: categoriesData) else {
            categories = []
            return
        }
        categories = decoded
    }

    private func saveCategories() {
        categoriesData = (try? JSONEncoder().encode(categories)) ?? Data()
    }

    private func addCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !categories.contains(trimmed) else { return }
        categories.append(trimmed)
        saveCategories()
    }

    private func deleteCategory(_ category: String) {
        // Reset items in this category to uncategorized
        for item in items where item.category == category {
            item.category = ""
        }
        categories.removeAll { $0 == category }
        saveCategories()
    }

    private func renameCategory() {
        guard let old = editingCategory else { return }
        let trimmed = editedCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !categories.contains(trimmed) else {
            editingCategory = nil
            return
        }
        // Update items with the old category name
        for item in items where item.category == old {
            item.category = trimmed
        }
        if let idx = categories.firstIndex(of: old) {
            categories[idx] = trimmed
        }
        saveCategories()
        editingCategory = nil
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
        saveCategories()
    }

    // MARK: - Daily Dose Items

    private func deleteItems(_ subset: [DailyDoseItem], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(subset[index])
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
        // ForEach displays reminderTimes sorted by id, so offsets index into the sorted array
        let sorted = reminderTimes.sorted { $0.id < $1.id }
        let idsToRemove = Set(offsets.map { sorted[$0].id })
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
            content.title = "Prescriptions"
            content.body = "Time to take your prescriptions."
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
