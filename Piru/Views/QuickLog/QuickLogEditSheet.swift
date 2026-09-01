import SwiftData
import SwiftUI

// MARK: - Quick-Log Edit Sheet

/// The Log screen's single Edit surface: the meds order, the favorites
/// order, and drink presets, one sheet. The list is permanently in edit mode
/// so rows show the standard reorder grabbers and delete controls — a bare
/// long-press drag technically reorders outside edit mode, but nothing
/// advertises it. The `editMode` environment stays scoped to the `List`
/// (with `navigationDestination` registered outside it) so pushed editors
/// don't inherit edit mode. Local sheet, so `@Environment(\.dismiss)` (NOT
/// `navigator.dismiss()`, which would pop the whole Log cover).
struct QuickLogEditSheet: View {
    @Query(sort: \DailyDoseItem.sortOrder) private var items: [DailyDoseItem]
    @Query(sort: [SortDescriptor(\FavoriteSubstance.sortOrder), SortDescriptor(\FavoriteSubstance.createdAt, order: .reverse)]) private var favorites: [FavoriteSubstance]
    @Query(sort: [SortDescriptor(\CustomDrinkPreset.sortOrder), SortDescriptor(\CustomDrinkPreset.createdAt)]) private var drinkPresets: [CustomDrinkPreset]
    @Query private var substanceColors: [SubstanceColor]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appNavigator) private var navigator
    @State private var customStore = CustomSubstanceStore.shared
    /// The "Now" pill's quick offsets — the same shared-suite key the pill
    /// reads and `DoseTimeSettingsView` writes.
    @AppStorage(DoseTimeDefaults.choicesKey, store: UserDefaults(suiteName: DoseTimeDefaults.suite))
    private var doseTimeChoicesRaw = DoseTimeDefaults.defaultRaw

    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                medsSection
                if !favorites.isEmpty {
                    favoritesSection
                }
                drinksSections
                doseTimesSection
            }
            .environment(\.editMode, .constant(.active))
            .navigationDestination(for: CustomDrinkPreset.self) { preset in
                DrinkPresetForm(preset: preset, substanceName: preset.substanceName)
            }
            .navigationDestination(for: NewDrinkRoute.self) { route in
                DrinkPresetForm(preset: nil, substanceName: route.substanceName)
            }
            .navigationDestination(for: DoseTimesRoute.self) { _ in
                DoseTimeSettingsView()
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
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Meds

    private var medsSection: some View {
        Section {
            ForEach(items) { item in
                medRow(item)
            }
            .onMove(perform: moveMeds)
            .onDelete(perform: deleteMeds)

            Button {
                navigator.present(.dailyDoseSettings)
            } label: {
                Label("Manage Meds…", systemImage: "pills")
            }
        } header: {
            Text("My Meds")
                .textCase(nil)
        }
    }

    /// Name + dose and reminder times — plain rows, matching the favorites
    /// section below. Editing schedules lives in the My Meds hub.
    private func medRow(_ item: DailyDoseItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.productName ?? customStore.displayName(for: item.substance))
            HStack(spacing: 4) {
                Text(verbatim: "\(item.amount.doseFormatted) \(item.unit)")
                if let first = item.reminderTimesMinutes.sorted().first,
                   let time = Calendar.current.date(
                       bySettingHour: first / 60, minute: first % 60, second: 0, of: .now,
                   ) {
                    Middot()
                    Text(time, style: .time)
                    if item.reminderTimesMinutes.count > 1 {
                        Text(verbatim: "+\(item.reminderTimesMinutes.count - 1)")
                    }
                    if item.remind {
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

    private func moveMeds(from source: IndexSet, to destination: Int) {
        var ordered = items
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, item) in ordered.enumerated() {
            item.sortOrder = index
        }
        try? modelContext.save()
    }

    private func deleteMeds(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(items[index])
        }
        try? modelContext.save()
        DoseNotificationManager.syncMedReminders(in: modelContext)
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
        PhoneSyncCoordinator.shared.pushManifest()
    }

    private func deleteFavorites(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(favorites[index])
        }
        try? modelContext.save()
        PhoneSyncCoordinator.shared.pushManifest()
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
                // Composed as a String so the localized "Drinks" and the verbatim
                // name join without the deprecated `Text + Text` operator.
                Text(verbatim: "\(String(localized: "Drinks")) · \(customStore.displayName(for: substance))")
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

    // MARK: Dose times

    /// The offsets the tray's "Now" pill offers, with the editor Settings also
    /// pushes — the pill is edited where it's used, not only under Settings.
    private var doseTimesSection: some View {
        Section {
            Button {
                path.append(DoseTimesRoute())
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Edit Dose Times…")
                        Text(doseTimesSummary)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
        } header: {
            Text("Dose Times")
                .textCase(nil)
        } footer: {
            Text("The quick offsets in the “Now” menu when logging a dose.")
        }
    }

    private var doseTimesSummary: String {
        DoseTimeDefaults.parse(doseTimeChoicesRaw)
            .map { TrayTime.offsetLabel(minutes: $0) }
            .joined(separator: " · ")
    }
}

/// Push target for the "Now" pill's offset editor.
private struct DoseTimesRoute: Hashable {}

/// Push target for creating a new drink preset in a given substance's group —
/// `CustomDrinkPreset` itself routes to the edit form.
private struct NewDrinkRoute: Hashable {
    let substanceName: String
}
