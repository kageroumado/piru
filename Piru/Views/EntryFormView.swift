import SwiftUI
import SwiftData
import ActivityKit
import WidgetKit

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
    @State private var entryTags: [String] = []

    @State private var selectedSubstance: Substance?
    @State private var availableRoutes: [RouteOfAdministration] = RouteOfAdministration.allCases
    @State private var showColorPicker = false
    @State private var savedSubstanceName = ""
    @State private var savedEntry: DoseEntry?
    @State private var interactionWarnings: [InteractionResult] = []
    @State private var substanceLocked = false
    @FocusState private var amountFocused: Bool

    @Query private var substanceColors: [SubstanceColor]
    @Query private var recentEntries: [DoseEntry]
    @Query private var favorites: [FavoriteSubstance]

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
            let aliasLabels = sub.unitAliases.map(\.label)
            let unique = Array(Set(routeUnits + aliasLabels + defaultUnits))
            let defaultUnit = sub.unit(for: route)
            // Native unit first, then substance-specific aliases (so a drink/joint
            // sits near the natural unit, not buried under mg/IU/etc.), then the rest.
            let ordered = [defaultUnit] + aliasLabels.filter { $0 != defaultUnit }
            return ordered + unique.filter { !ordered.contains($0) }
        }
        return defaultUnits
    }

    private var parsedAmount: Double? {
        guard let value = Double(amount.replacingOccurrences(of: ",", with: ".")),
              value > 0 else { return nil }
        return value
    }

    private var currentDoseRange: DoseRange? {
        selectedSubstance?.doseRange(for: route)
    }

    /// The user's input converted to the substance's native unit for accurate dose level comparison.
    private var normalizedAmount: Double? {
        guard let parsedAmount, let sub = selectedSubstance else { return parsedAmount }
        return sub.convert(amount: parsedAmount, from: unit, toRoute: route) ?? parsedAmount
    }

    private var currentDoseLevel: DoseLevel? {
        guard let normalizedAmount, let currentDoseRange else { return nil }
        return currentDoseRange.level(for: normalizedAmount)
    }

    private var worstSeverity: InteractionSeverity? {
        interactionWarnings.first?.severity
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
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
                    SubstanceSearchField(text: $substance, locked: substanceLocked, favoriteNames: Array(favorites).favoriteSet) { selected in
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
                        .foregroundStyle(Theme.secondaryLabel)
                    }
                }

                Section("Dosage") {
                    HStack {
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                            .focused($amountFocused)
                            .foregroundStyle(currentDoseLevel?.swiftUIColor ?? .primary)
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
                    Picker("Route", selection: $route) {
                        ForEach(availableRoutes) { r in
                            Text(r.localizedName).tag(r)
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
                            currentDose: normalizedAmount
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

                Section("Tags") {
                    TagEditorView(tags: $entryTags)
                }
                }
                .listRowBackground(Theme.cardBackground)
            }
            .onChange(of: substance) { checkInteractions() }
            .onChange(of: notes) {
                let extracted = TagExtractor.extractTags(from: notes)
                for tag in extracted where !entryTags.contains(tag) {
                    entryTags.append(tag)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(isEditing ? "Edit Entry" : "New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Image(systemName: "checkmark").fontWeight(.semibold) }
                        .disabled(substance.isEmpty || amount.isEmpty)
                }
            }
            .onAppear(perform: loadEntry)
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
        availableRoutes = sub.orderedRoutes
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
            entryTags = entry.tags

            if let match = SubstanceLibrary.search(entry.substance).first,
               match.name.lowercased() == entry.substance.lowercased() {
                selectedSubstance = match
                availableRoutes = match.orderedRoutes
            }
            return
        }

        if let prefillName = prefillSubstanceName, !prefillName.isEmpty {
            substance = prefillName
            if let match = SubstanceLibrary.search(prefillName).first,
               match.name.lowercased() == prefillName.lowercased() {
                selectSubstance(match)
            }
            if let r = prefillRoute { route = r }
            if let u = prefillUnit { unit = u }
            substanceLocked = true
            checkInteractions()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                amountFocused = true
            }
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

        // If the user picked a colloquial alias (e.g. "drink" for alcohol),
        // normalise to the canonical physical unit at save time so cumulative
        // dose, dose-level chips, and PK scaling all see the right number.
        let (storedAmount, storedUnit): (Double, String) = {
            if let sub = selectedSubstance,
               let alias = sub.unitAliases.first(where: { $0.label == unit }) {
                return (parsedAmount * alias.amountPerUnit, alias.unit)
            }
            return (parsedAmount, unit)
        }()

        if let entry {
            entry.substance = substance
            entry.amount = storedAmount
            entry.unit = storedUnit
            entry.route = route
            entry.timestamp = timestamp
            entry.notes = notes.isEmpty ? nil : notes
            let allTags = Array(Set(entryTags + TagExtractor.extractTags(from: notes)))
            entry.tags = allTags
        } else {
            let allTags = Array(Set(entryTags + TagExtractor.extractTags(from: notes)))
            let newEntry = DoseEntry(
                substance: substance,
                amount: storedAmount,
                unit: storedUnit,
                route: route,
                timestamp: timestamp,
                notes: notes.isEmpty ? nil : notes,
                tags: allTags
            )
            modelContext.insert(newEntry)
            savedEntry = newEntry

            // Schedule wellness notifications & check cumulative dose
            let category = selectedSubstance?.category
            let duration = selectedSubstance?.resolveDuration(for: route)
            let stimHours = RampDownScheduler.stimulantSessionHours(from: Array(recentEntries))

            RampDownScheduler.scheduleWellnessNotifications(
                substanceName: substance,
                category: category,
                doseTime: timestamp,
                duration: duration,
                recentStimHours: stimHours
            )
            RampDownScheduler.schedulePhaseNotifications(
                substanceName: substance,
                doseTime: timestamp,
                duration: duration
            )

            let (total, shouldAlert) = RampDownScheduler.checkCumulativeDose(
                substanceName: substance,
                newAmount: parsedAmount,
                unit: unit,
                route: route,
                existingEntries: Array(recentEntries)
            )
            if shouldAlert {
                RampDownScheduler.scheduleCumulativeDoseNotification(
                    substanceName: substance,
                    totalAmount: total,
                    unit: unit,
                    category: category
                )
            }
        }

        WidgetCenter.shared.reloadAllTimelines()

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

        ActiveSessionManager.shared.addDose(
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
                HStack(spacing: 6) {
                    Text("\(warning.severity.label): \(warning.substanceA) + \(warning.substanceB)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(warning.severity.color)
                    if warning.source != .classRule {
                        Text(warning.source.label)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(warning.severity.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(warning.severity.color)
                    }
                }
                Text(warning.description)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .padding(.vertical, 2)
    }
}
