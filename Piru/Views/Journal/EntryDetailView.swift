import SwiftData
import SwiftUI

/// Detail screen for a single logged dose, reached by tapping a journal intake
/// row. The session screen's language, scoped to one substance: the hero is the
/// large-title name + the timeline graph, the dose card beneath explains the
/// curve, then body load, session context, journaling context, and — last — the
/// substance's reference card with a "Show All" hop to its full page.
///
/// Editing is **in place**, and this is the app's only dose-edit surface: the
/// toolbar's *Edit* (or a day row's Edit action, via
/// ``SessionEditingService/requestEdit(_:)``) flips the hero's facts into
/// editable controls — the graph stays visible and live-previews the
/// ``EntryDraft`` — and *Done* commits the session/notification re-sync at a
/// single deliberate point.
struct EntryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sessionEditingService) private var editing
    @Query private var substanceColors: [SubstanceColor]

    let entry: DoseEntry

    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false
    @State private var showColorPicker = false
    @State private var showLocationPicker = false

    /// All the dose's editable facts, consolidated into one `@Observable` unit —
    /// seeded on Edit, committed on Done, discarded on Cancel.
    @State private var draft = EntryDraft()

    /// The substance record for this entry, resolved **once** on appear. The
    /// dose-ladder tint, unit list, salt forms, route list, and live-preview all
    /// read it; `entry.substance` never changes here, so caching it avoids a
    /// blocking `lookupByNameOrAlias` per body pass.
    @State private var substanceInfo: Substance?

    /// The worst interaction among the parent session's substances, resolved once
    /// alongside ``substanceInfo`` — the "Part of Session" echo row. `nil` for a
    /// solo dose or an interaction-free combination.
    @State private var sessionInteraction: InteractionResult?

    // MARK: - Derived

    private var currentColorHex: String {
        substanceColors.first {
            $0.substance.lowercased() == entry.substance.lowercased()
        }?.hexColor ?? PresetColor.defaultHex
    }

    private var substanceColor: Color {
        Color(hex: currentColorHex)
    }

    private var byVolumeCapability: ByVolumeDosing? {
        substanceInfo?.byVolumeDosing
    }

    /// Read-mode PK state driving the hero graph and live progress. Never reads
    /// the draft — edit mode's live preview is owned by ``EntryEditContent``.
    private var readState: ActiveSubstanceState? {
        ActiveSubstanceState.from(entry: entry, colorHex: currentColorHex)
    }

    /// Whether the dose's effect window still includes the current moment — gates
    /// the ⋯ menu's Live Activity toggle.
    private var isSessionActive: Bool {
        guard let state = readState else { return false }
        return Date.now < state.doseTimestamp.addingTimeInterval(state.totalMinutes * 60)
    }

    // MARK: - Body

    var body: some View {
        List {
            Group {
                if isEditing {
                    EntryEditContent(
                        draft: draft,
                        entry: entry,
                        substance: substanceInfo,
                        substanceColor: substanceColor,
                        colorHex: currentColorHex,
                        showColorPicker: $showColorPicker,
                        showLocationPicker: $showLocationPicker,
                        showingDeleteConfirmation: $showingDeleteConfirmation,
                    )
                } else {
                    EntryReadContent(
                        entry: entry,
                        substance: substanceInfo,
                        state: readState,
                        substanceColor: substanceColor,
                        colorMap: Array(substanceColors).colorMap,
                        sessionInteraction: sessionInteraction,
                    )
                }
            }
            .listRowBackground(CardBackground())
        }
        .insetGroupedListStyle()
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        #if canImport(UIKit)
            .listSectionSpacing(20)
        #endif
            .background(Theme.background)
            .readableWidth()
            // Keep the draft amount/unit synced with the by-volume fields in drink mode.
            .onChange(of: draft.byVolumeGrams(capability: byVolumeCapability)) { draft.syncByVolumeAmount(capability: byVolumeCapability) }
            .onChange(of: draft.byVolumeMode) { if draft.byVolumeMode { draft.syncByVolumeAmount(capability: byVolumeCapability) } }
            .onChange(of: draft.volumeUnit) { old, new in
                ByVolumeDefaults.preferredVolumeUnit = new
                guard let value = Double(draft.volumeText.replacingOccurrences(of: ",", with: ".")), value > 0 else { return }
                draft.volumeText = ByVolumeDefaults.format(Measurement(value: value, unit: old).converted(to: new).value)
            }
            .navigationTitle(DoseTitle.resolve(for: entry))
        #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.large)
        #endif
            .animation(.snappy(duration: 0.28), value: isEditing)
            .toolbar { toolbarContent }
            .confirmationDialog(
                "Delete this entry?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible,
            ) {
                Button("Delete", role: .destructive) {
                    deleteEntry()
                }
            } message: {
                Text("\(entry.amount.doseFormatted) \(entry.unit) \(DoseTitle.resolve(for: entry)) on \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))")
            }
            .sheet(isPresented: $showColorPicker) {
                SubstanceColorPickerView(
                    substanceName: entry.substance,
                    takenColors: Array(substanceColors).takenColorMap,
                ) { hex in
                    if let existing = substanceColors.first(where: { $0.substance.lowercased() == entry.substance.lowercased() }) {
                        existing.hexColor = hex
                    } else {
                        modelContext.insert(SubstanceColor(substance: entry.substance, hexColor: hex))
                    }
                    showColorPicker = false
                }
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showLocationPicker) {
                LocationPickerView { picked in draft.location = picked }
            }
            .task {
                // Resolve the full substance record once — it feeds the dose ladder,
                // unit/route/salt lists, and live preview. The `substanceInfo == nil`
                // guard below keeps this from re-running on every body pass and every
                // keystroke while editing — `resolveFull` is a blocking lookup.
                await SubstanceStore.shared.ensureAllLoaded()
                if substanceInfo == nil {
                    substanceInfo = SubstanceLibrary.resolveFull(entry.substance)
                }
                // A row's Edit action opens this screen straight into edit mode.
                // Consumed only after `substanceInfo` resolves — the draft's
                // by-volume seeding reads it.
                if editing.pendingEditEntryID == entry.id {
                    editing.pendingEditEntryID = nil
                    beginEditing()
                }
                // The session's worst interaction, for the "Part of Session" echo.
                // One batch check per screen — not per body pass.
                if sessionInteraction == nil, let doses = entry.session?.doses, doses.count >= 2 {
                    let names = Array(Set(doses.map(\.substance)))
                    if names.count >= 2 {
                        sessionInteraction = InteractionChecker.checkBatch(names, against: [])
                            .max { $0.severity.rawValue < $1.severity.rawValue }
                    }
                }
            }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { isEditing = false }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { commitEdits() }
                    .fontWeight(.semibold)
                    .disabled(draft.parsedAmount == nil)
            }
        } else {
            // Two explicit trailing buttons in the same accent tint — "Edit"
            // (Apple's convention over a pencil glyph) and a separate ⋯ menu,
            // split into their own glass groups by a ToolbarSpacer.
            ToolbarItem(placement: .platformTopBarTrailing) {
                Button("Edit") { beginEditing() }
                    .tint(Theme.accent)
            }
            ToolbarSpacer(.fixed, placement: .platformTopBarTrailing)
            ToolbarItem(placement: .platformTopBarTrailing) {
                EntryDoseMenu(
                    entry: entry,
                    colors: Array(substanceColors),
                    isSessionActive: isSessionActive,
                    showingDeleteConfirmation: $showingDeleteConfirmation,
                )
            }
        }
    }

    // MARK: - Actions

    private func beginEditing() {
        draft.begin(from: entry, hasByVolumeCapability: byVolumeCapability != nil)
        isEditing = true
    }

    /// Commit drafts to the entry and re-sync the active session / Live Activity
    /// + widgets.
    private func commitEdits() {
        guard let parsed = draft.parsedAmount else { return }
        let sub = substanceInfo

        // Normalize a colloquial alias (e.g. "drink") to its canonical physical
        // unit so cumulative dose, level chips, and PK scaling see the right number.
        let (storedAmount, storedUnit): (Double, String) = {
            if let sub, let alias = sub.unitAliases.first(where: { $0.label == draft.unit }) {
                return (parsed * alias.amountPerUnit, alias.unit)
            }
            return (parsed, draft.unit)
        }()

        let previousTimestamp = entry.timestamp
        let previousSubstanceName = entry.substance

        entry.amount = storedAmount
        entry.unit = storedUnit
        entry.route = draft.route
        entry.saltForm = draft.saltForm
        entry.isomer = draft.isomer
        entry.substanceUID = substanceInfo?.substanceUID
        // The edit can't rename the substance, so the dose keeps its release form
        // and only the isomer is in play — but the snapshot still composes across
        // both, so a Focalin XR dose stays "Dexmethylphenidate XR" after an edit.
        entry.displayNameSnapshot = DoseTitle.snapshot(canonicalName: entry.substance, isomer: draft.isomer, releaseForm: entry.releaseForm)
        entry.timestamp = draft.timestamp
        entry.session?.refreshDoseBounds()
        entry.isApproximate = draft.isApproximate
        entry.notes = draft.notes.isEmpty ? nil : draft.notes
        // By-volume metadata, set when logged as a drink, cleared otherwise.
        entry.volumeML = draft.byVolumeMode ? draft.enteredVolumeML : nil
        entry.abv = draft.byVolumeMode ? draft.enteredABV : nil
        entry.drinkName = draft.byVolumeMode ? draft.trimmedDrinkName : nil
        entry.tags = Array(Set(draft.tags + TagExtractor.extractTags(from: draft.notes)))
        entry.locationName = draft.location?.name
        entry.latitude = draft.location?.latitude
        entry.longitude = draft.location?.longitude

        // The session accessory & Live Activity read ActiveSessionManager's
        // snapshot, not SwiftData — sync it so they reflect the edit immediately.
        let colorHex = SubstancePalette.hex(for: entry.substance, hexMap: Array(substanceColors).hexColorMap)
        ActiveSessionManager.shared.updateDose(
            previousSubstanceName: previousSubstanceName,
            previousTimestamp: previousTimestamp,
            entry: entry,
            substance: sub,
            colorHex: colorHex,
            allColors: Array(substanceColors),
        )

        // Pending reminders are keyed to the old timestamp — a moved dose must
        // drop them and reschedule from its new time.
        DoseNotificationManager.doseRescheduled(entry: entry, previousTimestamp: previousTimestamp, in: modelContext)

        // Inventory recompute (scoped to the old + new substance) and the widget
        // reload are deferred off the edit-commit path — neither is on screen.
        DoseLogService.shared.scheduleDeferredBookkeeping(
            forSubstances: [entry.substance, previousSubstanceName],
            in: modelContext,
        )
        isEditing = false
    }

    private func deleteEntry() {
        // Capture before delete — the entry is invalid afterwards.
        let id = entry.id
        let name = entry.substance
        let timestamp = entry.timestamp
        let session = entry.session
        DoseNotificationManager.doseDeleted(entryID: id, timestamp: timestamp)
        modelContext.delete(entry)
        session?.refreshDoseBounds()
        // Tear the dose out of the active session / Live Activity too; otherwise a
        // deleted "taking now" dose leaves the Live Activity and progress accessory
        // stuck on screen, uncancellable even after the app is quit.
        ActiveSessionManager.shared.removeDose(
            id: id,
            substanceName: name,
            timestamp: timestamp,
            allColors: Array(substanceColors),
        )
        DoseLogService.shared.changed()
        // Scoped inventory recompute + widget reload deferred past the dismissal.
        DoseLogService.shared.scheduleDeferredBookkeeping(forSubstances: [name], in: modelContext)
        dismiss()
    }
}

/// The ⋯ overflow: the Live Activity toggle (while the dose is live) and a
/// destructive delete — the dose-level equivalents of the session menu.
struct EntryDoseMenu: View {
    let entry: DoseEntry
    let colors: [SubstanceColor]
    let isSessionActive: Bool
    @Binding var showingDeleteConfirmation: Bool

    var body: some View {
        Menu {
            if isSessionActive {
                EntryLiveActivityButton(entry: entry, colors: colors)
            }
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete Entry", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .tint(Theme.accent)
        .accessibilityLabel(Text("More"))
    }
}

/// Live Activity toggle — the session screen keeps this in its ⋯ menu, so the
/// hero graph carries no chrome of its own.
struct EntryLiveActivityButton: View {
    let entry: DoseEntry
    let colors: [SubstanceColor]

    var body: some View {
        let isRunning = LiveActivityManager.shared.isLiveActivityRunning
        Button {
            if isRunning {
                LiveActivityManager.shared.hideLiveActivity()
            } else {
                ActiveSessionManager.shared.restartFromEntries(
                    [entry],
                    allColors: colors,
                )
                LiveActivityManager.shared.startLiveActivity()
            }
        } label: {
            Label(
                isRunning ? "Stop Live Activity" : "Start Live Activity",
                systemImage: isRunning ? "stop.fill" : "dot.radiowaves.up.forward",
            )
        }
    }
}
