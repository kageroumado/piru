import SwiftData
import SwiftUI

// MARK: - Quick-Log Edit Sheet

/// The Log screen's single Edit surface: routines & prescriptions and the
/// favorites order, one sheet. Rows reorder with a native long-press drag and
/// swipe to delete; a routine row opens its Reminders-style detail editor.
/// Local sheet, so `@Environment(\.dismiss)` (NOT `navigator.dismiss()`,
/// which would pop the whole Log cover).
struct QuickLogEditSheet: View {
    @Query(sort: \DoseRoutine.sortOrder) private var routines: [DoseRoutine]
    @Query(sort: \DailyDoseItem.sortOrder) private var items: [DailyDoseItem]
    @Query(sort: [SortDescriptor(\FavoriteSubstance.sortOrder), SortDescriptor(\FavoriteSubstance.createdAt, order: .reverse)]) private var favorites: [FavoriteSubstance]
    @Query private var substanceColors: [SubstanceColor]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var customStore = CustomSubstanceStore.shared

    @State private var showingNewRoutine = false
    @State private var newRoutineName = ""

    var body: some View {
        NavigationStack {
            List {
                routinesSection
                if !favorites.isEmpty {
                    favoritesSection
                }
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
                NavigationLink {
                    RoutineDetailView(routine: routine)
                } label: {
                    routineRow(routine)
                }
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
                Text("\(count) item\(count == 1 ? "" : "s")")
                if let time = routine.timeAsDate {
                    Text(verbatim: "·")
                    Text(time, style: .time)
                    if routine.remind {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryLabel)
        }
    }

    private func addRoutine() {
        let trimmed = newRoutineName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !routines.contains(where: { $0.name == trimmed }) else { return }
        let maxOrder = routines.map(\.sortOrder).max() ?? -1
        modelContext.insert(DoseRoutine(name: trimmed, sortOrder: maxOrder + 1))
    }

    private func moveRoutines(from source: IndexSet, to destination: Int) {
        var ordered = routines
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, routine) in ordered.enumerated() {
            routine.sortOrder = index
        }
    }

    private func deleteRoutines(at offsets: IndexSet) {
        for index in offsets {
            let routine = routines[index]
            // Items survive the routine — they fall to Unassigned (visible in
            // the full routines manager).
            for item in items where item.category == routine.name {
                item.category = ""
            }
            modelContext.delete(routine)
        }
        DoseNotificationManager.syncRoutineReminders(routines: routines)
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
    }

    private func deleteFavorites(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(favorites[index])
        }
    }
}
