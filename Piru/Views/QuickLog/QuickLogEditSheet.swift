import SwiftData
import SwiftUI

// MARK: - Quick-Log Edit Sheet

/// The Log screen's single Edit surface: the meds order, the favorites
/// order, drink presets, and the dock's shortcuts and label, one sheet. The list is permanently in edit mode
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
    @AppStorage(QuickLogManager.fixedOrderDefaultsKey) private var quickLogFixedOrder = false
    /// The "Now" pill's quick offsets — the same shared-suite key the pill
    /// reads and `DoseTimeSettingsView` writes.
    @AppStorage(DoseTimeDefaults.choicesKey, store: UserDefaults(suiteName: DoseTimeDefaults.suite))
    private var doseTimeChoicesRaw = DoseTimeDefaults.defaultRaw

    @State private var path = NavigationPath()
    /// The "Now" pill offsets, edited inline (mirrors ``DoseTimeSettingsView``);
    /// persisted back to `doseTimeChoicesRaw` on change.
    @State private var doseTimeChoices: [Int] = []
    @State private var showAddDoseTime = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                medsSection
                favoritesSection
                drinksSections
                doseTimesSection
                DockShortcutsSection(path: $path)
                    .listRowBackground(CardBackground())
                DockLabelsSection(path: $path)
                    .listRowBackground(CardBackground())
                orderSection
            }
            .permanentEditMode()
            .themedPage()
            .sheet(isPresented: $showAddDoseTime) {
                DoseTimeAddSheet(existing: doseTimeChoices) { minutes in
                    doseTimeChoices.append(minutes)
                }
            }
            .onAppear { doseTimeChoices = DoseTimeDefaults.parse(doseTimeChoicesRaw) }
            .onChange(of: doseTimeChoices) { _, new in
                doseTimeChoicesRaw = DoseTimeDefaults.format(new)
            }
            .navigationDestination(for: AddFavoriteRoute.self) { _ in
                AddFavoriteView()
            }
            .navigationDestination(for: DockEditRoute.self) { route in
                switch route {
                case .addShortcut:
                    DockShortcutPicker()
                case .addLabel:
                    DockLabelForm(index: nil, existing: nil)
                case let .editLabel(index):
                    let labels = DockPreferences.shared.labels
                    DockLabelForm(index: index, existing: labels.indices.contains(index) ? labels[index] : nil)
                }
            }
            .navigationDestination(for: CustomDrinkPreset.self) { preset in
                DrinkPresetForm(preset: preset, substanceName: preset.substanceName)
            }
            .navigationDestination(for: NewDrinkRoute.self) { route in
                DrinkPresetForm(preset: nil, substanceName: route.substanceName)
            }
            .navigationTitle("Edit")
            .inlineNavigationTitle()
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
                // This sheet lives on top of the navigator's Log cover, which is
                // the app's single sheet — so open the hub by swapping the cover,
                // not by stacking a third sheet (which SwiftUI refuses).
                dismiss()
                navigator.present(.dailyDoseSettings, replacingTop: true)
            } label: {
                Label("Manage Meds…", systemImage: "pills")
            }
        } header: {
            Text("My Meds")
                .textCase(nil)
        }
        .listRowBackground(CardBackground())
    }

    /// Name + dose and reminder times — plain rows, matching the favorites
    /// section below. Editing schedules lives in the My Meds hub.
    private func medRow(_ item: DailyDoseItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(item.productName ?? customStore.displayName(for: item.substance))
            HStack(spacing: Spacing.xs) {
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
            .captionSecondary()
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
                HStack(spacing: Spacing.lg) {
                    Circle()
                        .fill(color(for: favorite.substance))
                        .frame(width: 10, height: 10)
                    Text(customStore.displayName(for: favorite.substance))
                }
            }
            .onMove(perform: moveFavorites)
            .onDelete(perform: deleteFavorites)

            Button {
                path.append(AddFavoriteRoute())
            } label: {
                Label("Add Favorite…", systemImage: "star")
            }
        } header: {
            Text("Favorites")
                .textCase(nil)
        }
        .listRowBackground(CardBackground())
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
        #if os(iOS)
            PhoneSyncCoordinator.shared.pushManifest()
        #endif
    }

    private func deleteFavorites(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(favorites[index])
        }
        try? modelContext.save()
        #if os(iOS)
            PhoneSyncCoordinator.shared.pushManifest()
        #endif
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
                    Label("New Drink…", systemImage: "plus.circle")
                }
            } header: {
                drinksHeader(for: group.substance, soleGroup: groups.count == 1)
            }
            .listRowBackground(CardBackground())
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

    // MARK: Order

    private var orderSection: some View {
        Section {
            Toggle(isOn: $quickLogFixedOrder) {
                Label("Keep Order", systemImage: "pin")
            }
            .tint(Theme.accent)
        } footer: {
            Text("Keep doses in a fixed order. When off, logging a dose moves it to the front.")
        }
        .listRowBackground(CardBackground())
    }

    // MARK: Dose times

    /// The offsets the tray's "Now" pill offers, with the editor Settings also
    /// pushes — the pill is edited where it's used, not only under Settings.
    private var doseTimesSection: some View {
        Section {
            ForEach(doseTimeChoices, id: \.self) { minutes in
                Label(TrayTime.offsetLabel(minutes: minutes), systemImage: "clock.arrow.circlepath")
            }
            .onDelete(perform: deleteDoseTimes)
            .onMove(perform: moveDoseTimes)

            if doseTimeChoices.count < DoseTimeDefaults.maxCount {
                Button {
                    showAddDoseTime = true
                } label: {
                    Label("Add Preset…", systemImage: "plus.circle")
                }
            }
        } header: {
            Text("Dose Times")
                .textCase(nil)
        } footer: {
            Text("The quick offsets in the “Now” menu when logging a dose.")
        }
        .listRowBackground(CardBackground())
    }

    private func deleteDoseTimes(at offsets: IndexSet) {
        // Keep at least one preset so the "Now" menu never empties out.
        guard doseTimeChoices.count - offsets.count >= 1 else { return }
        doseTimeChoices.remove(atOffsets: offsets)
    }

    private func moveDoseTimes(from source: IndexSet, to destination: Int) {
        doseTimeChoices.move(fromOffsets: source, toOffset: destination)
    }
}

/// Push target for adding a favorite substance from the Edit sheet.
private struct AddFavoriteRoute: Hashable {}

/// Push target for creating a new drink preset in a given substance's group —
/// `CustomDrinkPreset` itself routes to the edit form.
private struct NewDrinkRoute: Hashable {
    let substanceName: String
}

// MARK: - Add favorite

/// A substance picker pushed from the Edit sheet's Favorites section: choosing a
/// substance stars it (creates a ``FavoriteSubstance``) and pops back.
private struct AddFavoriteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FavoriteSubstance.sortOrder) private var favorites: [FavoriteSubstance]
    @State private var query = ""

    private var favoriteNames: Set<String> {
        Set(favorites.map { $0.substance.lowercased() })
    }

    var body: some View {
        List {
            Section {
                SubstanceSearchField(text: $query, favoriteNames: favoriteNames) { substance, _ in
                    add(substance)
                }
            } footer: {
                Text("Star a substance to keep it in your quick-log favorites.")
            }
            .listRowBackground(CardBackground())
        }
        .themedPage()
        .navigationTitle("Add Favorite")
        .inlineNavigationTitle()
    }

    private func add(_ substance: Substance) {
        guard !favoriteNames.contains(substance.name.lowercased()) else {
            dismiss()
            return
        }
        let favorite = FavoriteSubstance(substance: substance.name)
        favorite.sortOrder = favorites.count
        favorite.substanceUID = substance.substanceUID
        modelContext.insert(favorite)
        try? modelContext.save()
        #if os(iOS)
            PhoneSyncCoordinator.shared.pushManifest()
        #endif
        dismiss()
    }
}
