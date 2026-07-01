import ActivityKit
import SwiftData
import SwiftUI

struct LogMedicationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appNavigator) private var navigator

    @Query(sort: \DailyDoseItem.sortOrder) private var allItems: [DailyDoseItem]
    @Query private var substanceColors: [SubstanceColor]
    @Query private var recentEntries: [DoseEntry]

    let category: String

    @State private var toggleStates: [String: Bool] = [:]
    @State private var loggedDoseEntries: [DoseEntry] = []
    @State private var loggedSubstances: [Substance?] = []
    @State private var interactionWarnings: [InteractionResult] = []
    @State private var showInteractionSheet = false
    @State private var proceedAfterWarning = false

    init(category: String) {
        self.category = category
        let cutoff = Date.now.addingTimeInterval(-48 * 3_600)
        _recentEntries = Query(
            filter: #Predicate<DoseEntry> { e in
                e.timestamp >= cutoff
            },
            sort: \DoseEntry.timestamp,
        )
    }

    private var items: [DailyDoseItem] {
        allItems.filter { $0.category == category }
    }

    private var selectedCount: Int {
        items.count(where: { toggleStates[$0.substance + String($0.sortOrder)] ?? true })
    }

    private var selectedSubstanceNames: [String] {
        items.filter { toggleStates[itemKey(for: $0)] ?? true }.map(\.substance)
    }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        ForEach(items) { item in
                            Toggle(isOn: binding(for: item)) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(CustomSubstanceStore.shared.displayName(for: item.substance))
                                        .font(.body)
                                    Text("\(item.amount.doseFormatted) \(item.unit) \u{2014} \(String(localized: item.route.localizedName))")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.secondaryLabel)
                                }
                            }
                        }
                    } header: {
                        Text("Toggle off any you don't want to log today")
                    }

                    Section {
                        Button {
                            attemptLog()
                        } label: {
                            HStack {
                                Spacer()
                                Label("Log \(selectedCount) Item\(selectedCount == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                                    .font(.headline)
                                Spacer()
                            }
                        }
                        .disabled(selectedCount == 0)
                    }
                }
                .listRowBackground(Theme.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(category.isEmpty ? "Log Prescriptions" : "Log \(category)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { navigator.dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
            .sheet(isPresented: $showInteractionSheet) {
                InteractionWarningSheet(
                    warnings: interactionWarnings,
                    onProceed: {
                        showInteractionSheet = false
                        logSelected()
                    },
                    onCancel: {
                        showInteractionSheet = false
                    },
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func itemKey(for item: DailyDoseItem) -> String {
        item.substance + String(item.sortOrder)
    }

    private func binding(for item: DailyDoseItem) -> Binding<Bool> {
        let key = itemKey(for: item)
        return Binding(
            get: { toggleStates[key] ?? true },
            set: { toggleStates[key] = $0 },
        )
    }

    private func hasColor(for name: String) -> Bool {
        Array(substanceColors).hasColor(for: name)
    }

    /// Persist the substance's stable deterministic colour if it has none yet,
    /// so a first-time medication is coloured the moment it's logged — no extra
    /// picker step. Editable later from the entry detail's colour picker.
    private func ensureColor(for name: String) {
        guard !hasColor(for: name) else { return }
        modelContext.insert(SubstanceColor(substance: name, hexColor: PresetColor.deterministic(for: name).hex))
    }

    private func attemptLog() {
        let active = InteractionChecker.activeEntries(from: recentEntries)
        let warnings = InteractionChecker.checkBatch(selectedSubstanceNames, against: active)

        if warnings.isEmpty {
            logSelected()
        } else {
            interactionWarnings = warnings
            showInteractionSheet = true
        }
    }

    private func logSelected() {
        let now = Date.now
        var affected: Set<String> = []

        for item in items {
            let isOn = toggleStates[itemKey(for: item)] ?? true
            guard isOn else { continue }
            affected.insert(item.substance)

            let entry = DoseEntry(
                substance: item.substance,
                amount: item.amount,
                unit: item.unit,
                route: item.route,
                timestamp: now,
                isBackgroundMed: item.isBackgroundMed,
            )
            modelContext.insert(entry)
            SessionService.assignSession(for: entry, in: modelContext)

            let matchedSubstance = SubstanceLibrary.search(item.substance).first {
                $0.name.lowercased() == item.substance.lowercased()
            }
            loggedDoseEntries.append(entry)
            loggedSubstances.append(matchedSubstance)

            // Auto-assign a stable palette colour for a first-time medication so
            // it's coloured immediately — no follow-up colour-picker queue.
            ensureColor(for: item.substance)
        }

        startLiveActivityForBatch()
        DoseLogService.shared.changed()

        // Refresh the affected items' stock cache + the widget off the commit
        // path, through the shared deferred funnel — a tracked daily med's
        // consumption should reflect in inventory without blocking the dismissal.
        DoseLogService.shared.scheduleDeferredBookkeeping(forSubstances: affected, in: modelContext)

        // Medication log completes a logging flow; clear the entire chain back
        // to root.
        navigator.dismissAll()
    }

    private func startLiveActivityForBatch() {
        guard !loggedDoseEntries.isEmpty else { return }
        let entries = zip(loggedDoseEntries, loggedSubstances).map { (entry: $0, substance: $1) }
        ActiveSessionManager.shared.addDoses(
            entries: entries,
            allColors: Array(substanceColors),
        )
    }
}

// MARK: - Interaction Warning Sheet (for batch logging)

struct InteractionWarningSheet: View {
    let warnings: [InteractionResult]
    let onProceed: () -> Void
    let onCancel: () -> Void

    private var worstSeverity: InteractionSeverity {
        warnings.first?.severity ?? .caution
    }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                            InteractionWarningRow(warning: warning)
                        }
                    } header: {
                        Text("\(warnings.count) interaction\(warnings.count == 1 ? "" : "s") detected")
                    }

                    Section {
                        Button(role: .destructive) {
                            onProceed()
                        } label: {
                            HStack {
                                Spacer()
                                Label("Log Anyway", systemImage: "exclamationmark.triangle")
                                    .font(.headline)
                                Spacer()
                            }
                        }
                    }
                }
                .listRowBackground(Theme.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Interaction Warning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { onCancel() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
    }
}
