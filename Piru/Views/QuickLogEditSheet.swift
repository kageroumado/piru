import SwiftData
import SwiftUI

// MARK: - Quick-Log Edit Sheet

/// The Log screen's single Edit surface: routines & prescriptions, the
/// favorites order, and drink presets, one sheet. The list is permanently in edit mode so rows
/// show the standard reorder grabbers and delete controls — a bare long-press
/// drag technically reorders outside edit mode, but nothing advertises it.
/// Edit mode disables `NavigationLink` rows, so the routine row is a `Button`
/// that pushes its Reminders-style detail editor through a typed path; the
/// `editMode` environment stays scoped to the `List` (with
/// `navigationDestination` registered outside it) so the pushed editor doesn't
/// inherit edit mode. Local sheet, so `@Environment(\.dismiss)` (NOT
/// `navigator.dismiss()`, which would pop the whole Log cover).
struct QuickLogEditSheet: View {
    @Query(sort: \DoseRoutine.sortOrder) private var routines: [DoseRoutine]
    @Query(sort: \DailyDoseItem.sortOrder) private var items: [DailyDoseItem]
    @Query(sort: [SortDescriptor(\FavoriteSubstance.sortOrder), SortDescriptor(\FavoriteSubstance.createdAt, order: .reverse)]) private var favorites: [FavoriteSubstance]
    @Query(sort: [SortDescriptor(\CustomDrinkPreset.sortOrder), SortDescriptor(\CustomDrinkPreset.createdAt)]) private var drinkPresets: [CustomDrinkPreset]
    @Query private var substanceColors: [SubstanceColor]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var customStore = CustomSubstanceStore.shared

    @State private var showingNewRoutine = false
    @State private var newRoutineName = ""
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                routinesSection
                if !favorites.isEmpty {
                    favoritesSection
                }
                drinksSections
            }
            .environment(\.editMode, .constant(.active))
            .navigationDestination(for: DoseRoutine.self) { routine in
                RoutineDetailView(routine: routine)
            }
            .navigationDestination(for: CustomDrinkPreset.self) { preset in
                DrinkPresetForm(preset: preset, substanceName: preset.substanceName)
            }
            .navigationDestination(for: NewDrinkRoute.self) { route in
                DrinkPresetForm(preset: nil, substanceName: route.substanceName)
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityLabel("Done")
                }
            }
            .alert("New Routine", isPresented: $showingNewRoutine) {
                TextField("Name", text: $newRoutineName)
                Button("Add") { addRoutine() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("e.g. Morning, Pre-workout, Night")
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Routines

    private var routinesSection: some View {
        Section {
            ForEach(routines) { routine in
                Button {
                    path.append(routine)
                } label: {
                    HStack {
                        routineRow(routine)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
            }
            .onMove(perform: moveRoutines)
            .onDelete(perform: deleteRoutines)

            Button {
                newRoutineName = ""
                showingNewRoutine = true
            } label: {
                Label("New Routine", systemImage: "plus.circle")
            }
        } header: {
            Text("Routines & Prescriptions")
                .textCase(nil)
        }
    }

    /// Name + item count and reminder time — plain rows, matching the
    /// favorites section below.
    private func routineRow(_ routine: DoseRoutine) -> some View {
        let count = items.count(where: { $0.category == routine.name })
        return VStack(alignment: .leading, spacing: 2) {
            Text(routine.name)
            HStack(spacing: 4) {
                Text("^[\(count) item](inflect: true)")
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
            .accessibilityElement(children: .combine)
        }
    }

    // Every mutation below saves explicitly — this sheet can be torn down the
    // moment the handler returns (Done, swipe), and an edit still sitting in
    // the context when the container is released is silently lost.

    private func addRoutine() {
        let trimmed = newRoutineName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !routines.contains(where: { $0.name == trimmed }) else { return }
        let maxOrder = routines.map(\.sortOrder).max() ?? -1
        modelContext.insert(DoseRoutine(name: trimmed, sortOrder: maxOrder + 1))
        try? modelContext.save()
    }

    private func moveRoutines(from source: IndexSet, to destination: Int) {
        var ordered = routines
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, routine) in ordered.enumerated() {
            routine.sortOrder = index
        }
        try? modelContext.save()
    }

    private func deleteRoutines(at offsets: IndexSet) {
        // The @Query snapshot doesn't refresh mid-handler, so sync against the
        // survivors — passing `routines` would re-schedule the deleted
        // routine's reminder.
        let remaining = routines.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)
        for index in offsets {
            let routine = routines[index]
            // Items survive the routine — they fall to Unassigned (visible in
            // the full routines manager).
            for item in items where item.category == routine.name {
                item.category = ""
            }
            modelContext.delete(routine)
        }
        try? modelContext.save()
        DoseNotificationManager.syncRoutineReminders(routines: remaining)
    }

    // MARK: Favorites

    private var favoritesSection: some View {
        Section {
            ForEach(favorites) { favorite in
                HStack(spacing: 10) {
                    Circle()
                        .fill(color(for: favorite.substance))
                        .frame(width: 10, height: 10)
                    Text(customStore.displayName(for: favorite.substance))
                }
            }
            .onMove(perform: moveFavorites)
            .onDelete(perform: deleteFavorites)
        } header: {
            Text("Favorites")
                .textCase(nil)
        } footer: {
            Text("Drag to reorder. Swipe left to remove.")
        }
    }

    private func color(for substance: String) -> Color {
        Array(substanceColors).hexColorMap[substance.lowercased()]
            .map { Color(hex: $0) } ?? .gray
    }

    private func moveFavorites(from source: IndexSet, to destination: Int) {
        var ordered = favorites
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, favorite) in ordered.enumerated() {
            favorite.sortOrder = index
        }
        try? modelContext.save()
    }

    private func deleteFavorites(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(favorites[index])
        }
        try? modelContext.save()
    }

    // MARK: Drinks

    /// Presets grouped by their substance, preserving the query's sort inside
    /// each group. Alcohol is the only by-drink substance in v1, but the model
    /// carries a substance column — group so a future second substance gets its
    /// own section instead of an interleaved mess. With no presets at all, a
    /// single empty alcohol group keeps the section (and its New Drink row)
    /// discoverable.
    private var drinkGroups: [(substance: String, presets: [CustomDrinkPreset])] {
        var order: [String] = []
        var groups: [String: [CustomDrinkPreset]] = [:]
        for preset in drinkPresets {
            if groups[preset.substanceName] == nil { order.append(preset.substanceName) }
            groups[preset.substanceName, default: []].append(preset)
        }
        if order.isEmpty {
            order = ["alcohol"]
            groups["alcohol"] = []
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    private var drinksSections: some View {
        let groups = drinkGroups
        return ForEach(groups, id: \.substance) { group in
            Section {
                ForEach(group.presets) { preset in
                    Button {
                        path.append(preset)
                    } label: {
                        DrinkPresetRow(preset: preset)
                    }
                    .foregroundStyle(.primary)
                }
                .onMove { source, destination in
                    moveDrinks(in: group.presets, from: source, to: destination)
                }
                .onDelete { offsets in
                    deleteDrinks(in: group.presets, at: offsets)
                }

                Button {
                    path.append(NewDrinkRoute(substanceName: group.substance))
                } label: {
                    Label("New Drink", systemImage: "plus.circle")
                }
            } header: {
                drinksHeader(for: group.substance, soleGroup: groups.count == 1)
            }
        }
    }

    /// "Drinks" alone while alcohol is the only group; disambiguated with the
    /// substance's display name if a second by-drink substance ever appears.
    private func drinksHeader(for substance: String, soleGroup: Bool) -> some View {
        Group {
            if soleGroup {
                Text("Drinks")
            } else {
                Text("Drinks") + Text(verbatim: " · \(customStore.displayName(for: substance))")
            }
        }
        .textCase(nil)
    }

    private func moveDrinks(in presets: [CustomDrinkPreset], from source: IndexSet, to destination: Int) {
        var ordered = presets
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, preset) in ordered.enumerated() {
            preset.sortOrder = Double(index)
        }
        try? modelContext.save()
    }

    private func deleteDrinks(in presets: [CustomDrinkPreset], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(presets[index])
        }
        try? modelContext.save()
    }
}

/// Push target for creating a new drink preset in a given substance's group —
/// `CustomDrinkPreset` itself routes to the edit form.
private struct NewDrinkRoute: Hashable {
    let substanceName: String
}
