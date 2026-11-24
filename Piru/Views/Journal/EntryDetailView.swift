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
    @Environment(\.appNavigator) private var navigator
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

    private var currentTint: P3Color {
        substanceColors.first {
            $0.substance.lowercased() == entry.substance.lowercased()
        }?.tint ?? SubstancePalette.fallback(for: entry.substance)
    }

    private var substanceColor: Color {
        currentTint.color
    }

    private var byVolumeCapability: ByVolumeDosing? {
        substanceInfo?.byVolumeDosing
    }

    /// Read-mode PK state driving the hero graph and live progress. Never reads
    /// the draft — edit mode's live preview is owned by ``EntryEditContent``.
    private var readState: ActiveSubstanceState? {
        ActiveSubstanceState.from(entry: entry, tint: currentTint)
    }

    /// Whether the dose's effect window still includes the current moment — gates
    /// the ⋯ menu's Live Activity toggle.
    private var isSessionActive: Bool {
        guard let state = readState else { return false }
        return Date.now < state.doseTimestamp.addingTimeInterval(state.totalMinutes * 60)
    }

    /// A deleted entry's attributes trap on read, and SwiftUI can re-render this
    /// screen after the delete commits (its own ⋯ Delete, or one from another
    /// surface) while the pop is still animating. `isDeleted` covers the unsaved
    /// delete; a saved one leaves `isDeleted` false and detaches the context.
    private var entryIsGone: Bool {
        entry.isDeleted || entry.modelContext == nil
    }

    // MARK: - Body

    var body: some View {
        if entryIsGone {
            Color.clear.skinBackdrop()
        } else {
            content
        }
    }

    private var content: some View {
        List {
            Group {
                if isEditing {
                    EntryEditContent(
                        draft: draft,
                        entry: entry,
                        substance: substanceInfo,
                        substanceColor: substanceColor,
                        tint: currentTint,
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
            .skinBackdrop()
            .readableWidth()
            // Keep the draft amount/unit synced with the by-volume fields in drink mode.
            .onChange(of: draft.byVolumeGrams(capability: byVolumeCapability)) { draft.syncByVolumeAmount(capability: byVolumeCapability) }
            .onChange(of: draft.byVolumeMode) { if draft.byVolumeMode { draft.syncByVolumeAmount(capability: byVolumeCapability) } }
            .onChange(of: draft.volumeUnit) { old, new in
                ByVolumeDefaults.preferredVolumeUnit = new
                guard let value = DecimalInput.parse(draft.volumeText), value > 0 else { return }
                draft.volumeText = ByVolumeDefaults.format(Measurement(value: value, unit: old).converted(to: new).value)
            }
            .navigationTitle(DoseTitle.resolve(for: entry))
            .largeNavigationTitle()
            .animation(.snappy(duration: 0.28), value: isEditing)
            // Opening another record beside the list would drop the draft; the
            // navigator asks first while this is set.
            .onChange(of: isEditing) { _, editing in navigator.setEditing(editing, record: entry.id) }
            .onDisappear { navigator.setEditing(false, record: entry.id) }
            .toolbar { toolbarContent }
            // Editing owns the leading slot: its Cancel (an X) is the way out, so a
            // pushed screen's Back beside it would be a second, unsaved exit.
            .navigationBarBackButtonHidden(isEditing)
            .confirmationDialog(
                "Delete this entry?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible,
            ) {
                Button("Delete", role: .destructive) {
                    deleteEntry()
                }
            } message: {
                Text("\(entry.amountDisplay) \(entry.unit) \(DoseTitle.resolve(for: entry)) on \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))")
            }
            .sheet(isPresented: $showColorPicker) {
                SubstanceColorPickerView(substanceName: entry.substance) { showColorPicker = false }
            }
            .sheet(isPresented: $showLocationPicker) {
                LocationPickerView { picked in draft.location = picked }
            }
            .task {
                // Resolve the substance once — it feeds the dose ladder, unit/route/salt
                // lists, and live preview, all of which the batch projection carries:
                // this screen shows no mechanism, bindings or chemistry, so it never
                // pays the full record's per-substance SQL. The `substanceInfo == nil`
                // guard skips re-resolving when the screen reappears (e.g. after a
                // pushed child pops).
                await SubstanceStore.shared.ensureAllLoaded()
                if substanceInfo == nil {
                    substanceInfo = SubstanceLibrary.lookup(entry.substance)
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
                Button(role: .cancel) { isEditing = false }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .confirm) { commitEdits() }
                    .fontWeight(.semibold)
                    .disabled(!draft.canCommit)
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

    private func commitEdits() {
        guard editing.commit(draft, to: entry, substance: substanceInfo, in: modelContext) else { return }
        isEditing = false
    }

    private func deleteEntry() {
        // Read before the delete: the entry is invalid afterwards.
        let id = entry.id
        editing.delete(entry, in: modelContext)
        // Beside a list, `dismiss()` cannot reach the open record: take its route out instead.
        let removed = navigator.removeDeletedRecord {
            if case let .entry(_, routeID) = $0 { routeID == id } else { false }
        }
        if !removed { dismiss() }
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
