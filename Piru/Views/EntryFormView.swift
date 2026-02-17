import SwiftUI
import SwiftData
import ActivityKit

struct EntryFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var entry: DoseEntry?
    private var prefillSubstanceName: String?
    private var prefillRoute: RouteOfAdministration?
    private var prefillUnit: String?

    @State private var substance = ""
    @State private var amount = ""
    @State private var unit = "mg"
    @State private var route: RouteOfAdministration = .oral
    @State private var timestamp = Date.now
    @State private var notes = ""

    @State private var selectedSubstance: Substance?
    @State private var availableRoutes: [RouteOfAdministration] = RouteOfAdministration.allCases
    @State private var showFatalAlert = false
    @State private var showColorPicker = false
    @State private var savedSubstanceName = ""
    @State private var savedEntry: DoseEntry?
    @State private var interactionWarnings: [InteractionResult] = []

    @Query private var substanceColors: [SubstanceColor]
    @Query private var recentEntries: [DoseEntry]

    init(entry: DoseEntry? = nil) {
        self.entry = entry
        self.prefillSubstanceName = nil
        self.prefillRoute = nil
        self.prefillUnit = nil
        let cutoff = Date.now.addingTimeInterval(-48 * 3600)
        _recentEntries = Query(
            filter: #Predicate<DoseEntry> { e in
                e.timestamp >= cutoff
            },
            sort: \DoseEntry.timestamp
        )
    }

    init(prefillSubstance: String, prefillRoute: RouteOfAdministration? = nil, prefillUnit: String? = nil) {
        self.entry = nil
        self.prefillSubstanceName = prefillSubstance
        self.prefillRoute = prefillRoute
        self.prefillUnit = prefillUnit
        let cutoff = Date.now.addingTimeInterval(-48 * 3600)
        _recentEntries = Query(
            filter: #Predicate<DoseEntry> { e in
                e.timestamp >= cutoff
            },
            sort: \DoseEntry.timestamp
        )
    }

    private var isEditing: Bool { entry != nil }

    private let defaultUnits = ["mg", "g", "µg", "mL", "IU", "drops", "puffs"]

    private var currentUnits: [String] {
        if let sub = selectedSubstance {
            let routeUnits = sub.routes.map(\.unit)
            let unique = Array(Set(routeUnits + defaultUnits))
            let defaultUnit = sub.unit(for: route)
            return [defaultUnit] + unique.filter { $0 != defaultUnit }
        }
        return defaultUnits
    }

    private var parsedAmount: Double? {
        Double(amount.replacingOccurrences(of: ",", with: "."))
    }

    private var currentDoseRange: DoseRange? {
        selectedSubstance?.doseRange(for: route)
    }

    private var currentDoseLevel: DoseLevel? {
        guard let parsedAmount, let currentDoseRange else { return nil }
        return currentDoseRange.level(for: parsedAmount)
    }

    private var worstSeverity: InteractionSeverity? {
        interactionWarnings.first?.severity
    }

    var body: some View {
        NavigationStack {
            Form {
                // Interaction warnings — shown at top
                if !interactionWarnings.isEmpty {
                    Section {
                        ForEach(Array(interactionWarnings.enumerated()), id: \.offset) { _, warning in
                            InteractionWarningRow(warning: warning)
                        }
                    } header: {
                        Label(
                            interactionWarnings.count == 1 ? "Interaction Warning" : "\(interactionWarnings.count) Interaction Warnings",
                            systemImage: worstSeverity == .dangerous ? "exclamationmark.triangle.fill" : "exclamationmark.triangle"
                        )
                        .foregroundStyle((worstSeverity ?? .caution).color)
                    }
                }

                Section("Substance") {
                    SubstanceSearchField(text: $substance) { selected in
                        selectSubstance(selected)
                    } onCustom: {
                        useCustomSubstance()
                    }
                    if selectedSubstance == nil && !substance.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                            Text("Custom substance - enter dose details manually")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Section("Dosage") {
                    HStack {
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                            .foregroundStyle(currentDoseLevel.map { colorFor($0) } ?? .primary)
                        if let level = currentDoseLevel {
                            DoseLevelBadge(level: level)
                                .transition(.opacity.combined(with: .scale))
                                .animation(.easeInOut(duration: 0.2), value: level)
                        }
                        Picker("Unit", selection: $unit) {
                            ForEach(currentUnits, id: \.self) { Text($0) }
                        }
                        .labelsHidden()
                    }
                    .onChange(of: amount) {
                        if currentDoseLevel == .fatal {
                            showFatalAlert = true
                        }
                    }
                    Picker("Route", selection: $route) {
                        ForEach(availableRoutes) { r in
                            Text(r.displayName).tag(r)
                        }
                    }
                    .onChange(of: route) {
                        if let sub = selectedSubstance {
                            unit = sub.unit(for: route)
                        }
                    }
                }

                if let selectedSubstance {
                    Section("Dose Reference") {
                        DoseInfoView(
                            substance: selectedSubstance,
                            route: route,
                            currentDose: parsedAmount
                        )
                        .padding(.vertical, 4)
                    }
                }

                Section("Timing") {
                    DatePicker("Date & Time", selection: $timestamp)
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .onChange(of: substance) { checkInteractions() }
            .navigationTitle(isEditing ? "Edit Entry" : "New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(substance.isEmpty || amount.isEmpty)
                }
            }
            .onAppear(perform: loadEntry)
            .alert("Fatal Overdose Warning", isPresented: $showFatalAlert) {
                Button("I understand the risk", role: .destructive) { }
                Button("Clear dose", role: .cancel) { amount = "" }
            } message: {
                Text("The dose you entered is in the potentially fatal range for \(substance). This amount may be life-threatening. Please do not consume this dose.")
            }
            .sheet(isPresented: $showColorPicker, onDismiss: {
                startLiveActivityIfNeeded()
                dismiss()
            }) {
                SubstanceColorPickerView(
                    substanceName: savedSubstanceName,
                    takenColors: takenColorMap
                ) { hex in
                    let sc = SubstanceColor(substance: savedSubstanceName, hexColor: hex)
                    modelContext.insert(sc)
                }
                .presentationDetents([.large])
            }
        }
    }

    private func useCustomSubstance() {
        selectedSubstance = nil
        availableRoutes = RouteOfAdministration.allCases
        checkInteractions()
    }

    private func selectSubstance(_ sub: Substance) {
        selectedSubstance = sub
        route = sub.defaultRoute
        unit = sub.unit(for: sub.defaultRoute)

        let subRoutes = sub.routes.map(\.route)
        let otherRoutes = RouteOfAdministration.allCases.filter { !subRoutes.contains($0) }
        availableRoutes = subRoutes + otherRoutes

        checkInteractions()
    }

    private func checkInteractions() {
        guard !substance.isEmpty, !isEditing else {
            interactionWarnings = []
            return
        }
        let active = InteractionChecker.activeEntries(from: recentEntries)
        interactionWarnings = InteractionChecker.check(substance, against: active)
    }

    private func loadEntry() {
        if let entry {
            substance = entry.substance
            amount = String(entry.amount)
            unit = entry.unit
            route = entry.route
            timestamp = entry.timestamp
            notes = entry.notes ?? ""

            if let match = SubstanceLibrary.search(entry.substance).first,
               match.name.lowercased() == entry.substance.lowercased() {
                selectedSubstance = match
                let subRoutes = match.routes.map(\.route)
                let otherRoutes = RouteOfAdministration.allCases.filter { !subRoutes.contains($0) }
                availableRoutes = subRoutes + otherRoutes
            }
            return
        }

        if let prefillName = prefillSubstanceName {
            substance = prefillName
            if let match = SubstanceLibrary.search(prefillName).first,
               match.name.lowercased() == prefillName.lowercased() {
                selectSubstance(match)
            }
            if let r = prefillRoute { route = r }
            if let u = prefillUnit { unit = u }
            checkInteractions()
        }
    }

    private var takenColorMap: [String: String] {
        Array(substanceColors).takenColorMap
    }

    private func hasColor(for name: String) -> Bool {
        Array(substanceColors).hasColor(for: name)
    }

    private func save() {
        guard let parsedAmount else { return }

        if let entry {
            entry.substance = substance
            entry.amount = parsedAmount
            entry.unit = unit
            entry.route = route
            entry.timestamp = timestamp
            entry.notes = notes.isEmpty ? nil : notes
        } else {
            let newEntry = DoseEntry(
                substance: substance,
                amount: parsedAmount,
                unit: unit,
                route: route,
                timestamp: timestamp,
                notes: notes.isEmpty ? nil : notes
            )
            modelContext.insert(newEntry)
            savedEntry = newEntry
        }

        if !hasColor(for: substance) {
            savedSubstanceName = substance
            showColorPicker = true
        } else {
            startLiveActivityIfNeeded()
            dismiss()
        }
    }

    private func startLiveActivityIfNeeded() {
        guard let savedEntry, entry == nil else { return }
        let colorHex = substanceColors.first {
            $0.substance.lowercased() == savedEntry.substance.lowercased()
        }?.hexColor ?? "007AFF"

        LiveActivityManager.shared.addDose(
            entry: savedEntry,
            substance: selectedSubstance,
            colorHex: colorHex,
            allColors: Array(substanceColors)
        )
    }

}

// MARK: - Interaction Warning Row

struct InteractionWarningRow: View {
    let warning: InteractionResult

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: warning.severity == .dangerous ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                .foregroundStyle(warning.severity.color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(warning.severity.label): \(warning.substanceA) + \(warning.substanceB)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(warning.severity.color)
                Text(warning.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
