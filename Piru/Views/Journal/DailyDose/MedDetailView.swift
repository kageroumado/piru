import SwiftData
import SwiftUI

/// The per-med depth sheet of the My Meds hub: schedule at a glance, live
/// reminder controls (including the Ask Again override), and delete. Editing
/// the med itself (substance, dose, times) goes through ``MedFormView``.
struct MedDetailView: View {
    @Bindable var item: DailyDoseItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingEdit = false
    @State private var showingDeleteConfirmation = false

    /// The Ask Again override choices. `nil` = follow the global default;
    /// `[]` = opted out. Encoded through a tag string because `[Int]?` makes
    /// an awkward picker tag.
    private enum AskAgainChoice: String, CaseIterable, Identifiable {
        case globalDefault
        case off
        case ten
        case tenThirty

        var id: String {
            rawValue
        }

        var override: [Int]? {
            switch self {
            case .globalDefault: nil
            case .off: []
            case .ten: [10]
            case .tenThirty: [10, 30]
            }
        }

        var label: LocalizedStringResource {
            switch self {
            case .globalDefault: "Default"
            case .off: "Off"
            case .ten: "10 min later"
            case .tenThirty: "10 and 30 min later"
            }
        }

        static func from(_ override: [Int]?) -> AskAgainChoice {
            switch override {
            case nil: .globalDefault
            case []: .off
            case [10]: .ten
            case [10, 30]: .tenThirty
            default: .globalDefault
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection

                if !item.isAsNeeded {
                    timesSection
                    remindersSection
                }

                quietSection

                Section {
                    Button("Delete Med", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                    .frame(maxWidth: .infinity)
                }
                .listRowBackground(CardBackground())
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { showingEdit = true }
                }
            }
            .sheet(isPresented: $showingEdit) {
                MedFormView(item: item)
            }
            // Live toggles (remind, Ask Again, quiet) edit the model directly;
            // one resync on close covers them all.
            .onDisappear {
                DoseNotificationManager.syncMedReminders(in: modelContext)
            }
            .confirmationDialog(
                "Delete this med?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible,
            ) {
                Button("Delete Med", role: .destructive) {
                    modelContext.delete(item)
                    dismiss()
                }
            } message: {
                Text("Reminders and adherence tracking stop. Doses you already logged stay in your journal.")
            }
        }
    }

    // MARK: Sections

    private var headerSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "pill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.productName ?? CustomSubstanceStore.shared.displayName(for: item.substance))
                        .font(.headline)
                    Text(scheduleSummary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
        .listRowBackground(CardBackground())
    }

    private var timesSection: some View {
        Section("Times") {
            if item.reminderTimesMinutes.isEmpty {
                Text("Anytime — no set times")
                    .foregroundStyle(Theme.secondaryLabel)
            } else {
                ForEach(item.reminderTimesMinutes, id: \.self) { minutes in
                    HStack {
                        Text(Self.timeText(minutes))
                        Spacer()
                        Text(MedTimeGroup.group(forMinutes: minutes).label)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
            }
        }
        .listRowBackground(CardBackground())
    }

    private var remindersSection: some View {
        Section {
            Toggle(isOn: $item.remind) {
                Label("Remind Me", systemImage: "bell")
            }
            .disabled(item.reminderTimesMinutes.isEmpty)

            if item.remind, !item.reminderTimesMinutes.isEmpty {
                Picker(selection: askAgainBinding) {
                    ForEach(AskAgainChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                } label: {
                    Label("Ask Again", systemImage: "clock.arrow.circlepath")
                }
            }

            Toggle(isOn: $item.nextDoseReminder) {
                Label("Next-Dose Window", systemImage: "timer")
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Ask Again re-asks if a dose isn't logged — \u{201C}Default\u{201D} follows the cadence in Notification Settings. Never a scold, just a nudge.")
        }
        .listRowBackground(CardBackground())
    }

    private var quietSection: some View {
        Section {
            Toggle(isOn: $item.isQuiet) {
                Label("Quiet med", systemImage: "leaf")
            }
            .onChange(of: item.isQuiet) {
                // Quiet meds are also background meds (session folding).
                item.isBackgroundMed = item.isQuiet
            }
        } footer: {
            Text("Folds into the \u{201C}Supplements\u{201D} row, shares one reminder per time of day, and stays off the timeline graphs.")
        }
        .listRowBackground(CardBackground())
    }

    // MARK: Helpers

    private var askAgainBinding: Binding<AskAgainChoice> {
        Binding(
            get: { AskAgainChoice.from(item.askAgainOverrideMinutes) },
            set: { item.askAgainOverrideMinutes = $0.override },
        )
    }

    private var scheduleSummary: String {
        let dose = "\(item.amount.doseFormatted) \(item.unit) · \(String(localized: item.route.localizedName))"
        if item.isAsNeeded {
            if let limit = item.maxPerDay {
                return "\(dose) · \(String(localized: "up to \(limit)× daily"))"
            }
            return "\(dose) · \(String(localized: "as needed"))"
        }
        let count = item.reminderTimesMinutes.count
        if count > 1 {
            return "\(dose) · \(String(localized: "\(count)× daily"))"
        }
        return "\(dose) · \(String(localized: item.frequency.shortLabel))"
    }

    private static func timeText(_ minutes: Int) -> String {
        let date = Calendar.current.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now,
        ) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
