import SwiftUI
import SwiftData
import ActivityKit

struct LogDailyDoseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \DailyDoseItem.sortOrder) private var items: [DailyDoseItem]
    @Query private var substanceColors: [SubstanceColor]
    @Query private var recentEntries: [DoseEntry]

    @State private var toggleStates: [String: Bool] = [:]
    @State private var showColorPicker = false
    @State private var colorQueue: [String] = []
    @State private var currentColorSubstance = ""
    @State private var loggedDoseEntries: [DoseEntry] = []
    @State private var loggedSubstances: [Substance?] = []
    @State private var interactionWarnings: [InteractionResult] = []
    @State private var showInteractionSheet = false
    @State private var proceedAfterWarning = false

    init() {
        let cutoff = Date.now.addingTimeInterval(-48 * 3600)
        _recentEntries = Query(
            filter: #Predicate<DoseEntry> { e in
                e.timestamp >= cutoff
            },
            sort: \DoseEntry.timestamp
        )
    }

    private var selectedCount: Int {
        items.filter { toggleStates[$0.substance + String($0.sortOrder)] ?? true }.count
    }

    private var selectedSubstanceNames: [String] {
        items.filter { toggleStates[itemKey(for: $0)] ?? true }.map(\.substance)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items) { item in
                        Toggle(isOn: binding(for: item)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.substance)
                                    .font(.body)
                                Text("\(item.amount.formatted()) \(item.unit) \u{2014} \(item.route.displayName)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
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
            .navigationTitle("Log Daily Dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showColorPicker, onDismiss: showNextColorPicker) {
                SubstanceColorPickerView(
                    substanceName: currentColorSubstance,
                    takenColors: takenColorMap
                ) { hex in
                    let sc = SubstanceColor(substance: currentColorSubstance, hexColor: hex)
                    modelContext.insert(sc)
                }
                .presentationDetents([.large])
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
                    }
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
            set: { toggleStates[key] = $0 }
        )
    }

    private var takenColorMap: [String: String] {
        Array(substanceColors).takenColorMap
    }

    private func hasColor(for name: String) -> Bool {
        Array(substanceColors).hasColor(for: name)
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
        var needsColor: [String] = []

        for item in items {
            let isOn = toggleStates[itemKey(for: item)] ?? true
            guard isOn else { continue }

            let entry = DoseEntry(
                substance: item.substance,
                amount: item.amount,
                unit: item.unit,
                route: item.route,
                timestamp: now
            )
            modelContext.insert(entry)

            let matchedSubstance = SubstanceLibrary.shared.search(item.substance).first {
                $0.name.lowercased() == item.substance.lowercased()
            }
            loggedDoseEntries.append(entry)
            loggedSubstances.append(matchedSubstance)

            if !hasColor(for: item.substance) && !needsColor.contains(item.substance) {
                needsColor.append(item.substance)
            }
        }

        if needsColor.isEmpty {
            startLiveActivityForBatch()
            dismiss()
        } else {
            colorQueue = needsColor
            showNextColorPicker()
        }
    }

    private func startLiveActivityForBatch() {
        guard !loggedDoseEntries.isEmpty else { return }
        let entries = zip(loggedDoseEntries, loggedSubstances).map { (entry: $0, substance: $1) }
        LiveActivityManager.shared.addDoses(
            entries: entries,
            allColors: Array(substanceColors)
        )
    }

    private func showNextColorPicker() {
        guard !colorQueue.isEmpty else {
            startLiveActivityForBatch()
            dismiss()
            return
        }
        currentColorSubstance = colorQueue.removeFirst()
        showColorPicker = true
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
            .navigationTitle("Interaction Warning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
    }
}
