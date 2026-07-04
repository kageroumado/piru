import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Query(sort: \SubstanceColor.substance) private var substanceColors: [SubstanceColor]
    @Query(sort: \DailyDoseItem.sortOrder) private var dailyDoseItems: [DailyDoseItem]
    @State private var customSubstanceStore = CustomSubstanceStore.shared
    @State private var profileStore = UserProfileStore.shared

    @Environment(\.appNavigator) private var navigator

    var body: some View {
        List {
            Group {
                Section {
                    NavigationLink {
                        RoutinesSettingsView()
                    } label: {
                        // The count is rendered through `Text`'s LocalizedStringKey
                        // path so automatic grammar agreement runs; `String(localized:)`
                        // here left the raw `^[…](inflect: true)` markup on screen.
                        HStack {
                            Label("Routines", systemImage: "repeat")
                            Spacer()
                            Text("^[\(dailyDoseItems.count) item](inflect: true)")
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }

                    NavigationLink {
                        CustomSubstancesListView()
                    } label: {
                        countRow(
                            "My Substances",
                            systemImage: "flask",
                            value: "\(customSubstanceStore.all.count)",
                        )
                    }

                    NavigationLink {
                        SubstanceColorsListView()
                    } label: {
                        HStack {
                            Label("Substance Colors", systemImage: "paintpalette")
                            Spacer()
                            if substanceColors.isEmpty {
                                Text("None yet")
                                    .foregroundStyle(Theme.secondaryLabel)
                            } else {
                                colorsPreview
                            }
                        }
                    }
                } header: {
                    Text("Substances")
                } footer: {
                    Text("Create or personalize substances — adjust dose ranges, duration, and units to match your own data and tolerance.")
                }

                Section {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notifications", systemImage: "bell.badge")
                    }

                    NavigationLink {
                        JournalSettingsView()
                    } label: {
                        Label("Journal", systemImage: "book")
                    }

                    Picker(selection: profileBinding) {
                        ForEach(UserProfile.allCases) { profile in
                            Label {
                                Text(profile.displayName)
                            } icon: {
                                Image(systemName: profile.icon)
                            }
                            .tag(profile)
                        }
                    } label: {
                        Label("Disclosure Tier", systemImage: "slider.horizontal.3")
                    }

                    NavigationLink {
                        BodyWeightView()
                    } label: {
                        HStack {
                            Label("Body Weight", systemImage: "figure")
                            Spacer()
                            Text(weightSummary)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                } header: {
                    Text("Preferences")
                } footer: {
                    Text(UserProfileStore.shared.disclosureTier.summary)
                }

                Section {
                    Toggle(isOn: smokesBinding) {
                        Label("I smoke tobacco regularly", systemImage: "smoke")
                    }
                    .tint(Theme.accent)

                    Toggle(isOn: grapefruitBinding) {
                        Label("Grapefruit dose logging", systemImage: "carrot")
                    }
                    .tint(Theme.accent)

                    Toggle(isOn: aldh2Binding) {
                        Label("I get the alcohol flush", systemImage: "wineglass")
                    }
                    .tint(Theme.accent)
                } header: {
                    Text("Metabolism")
                } footer: {
                    Text("Tobacco smoke speeds up CYP1A2, so it lowers the levels of some drugs (like caffeine and olanzapine). Grapefruit slows down CYP3A4, raising the levels of others — turn on grapefruit logging to mark it on individual doses of affected substances. The alcohol flush (facial redness, fast heartbeat, nausea after a little alcohol) signals the ALDH2 variant — turn it on to see acetaldehyde, the toxic by-product it lets build up, on alcohol entries. All three are shown only where they actually change a drug's levels or risk.")
                }

                Section("Data") {
                    NavigationLink {
                        DataStorageView()
                    } label: {
                        Label("Data & Backup", systemImage: "lock.icloud")
                    }

                    NavigationLink {
                        SubstanceDatabaseView()
                    } label: {
                        countRow(
                            "Substance Database",
                            systemImage: "books.vertical",
                            value: "\(SubstanceStore.shared.count)",
                        )
                    }
                }

                Section {
                    EmptyView()
                } footer: {
                    Text(verbatim: appVersionString)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            .listRowBackground(CardBackground())
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    navigator.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel(Text("Close"))
            }
        }
    }

    // MARK: - Row Helpers

    private func countRow(_ title: LocalizedStringKey, systemImage: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    // MARK: - Bindings

    private var profileBinding: Binding<UserProfile> {
        Binding(
            get: { profileStore.disclosureTier },
            set: { profileStore.setDisclosureTier($0) },
        )
    }

    private var smokesBinding: Binding<Bool> {
        Binding(
            get: { profileStore.smokesTobacco },
            set: { profileStore.setSmokesTobacco($0) },
        )
    }

    private var grapefruitBinding: Binding<Bool> {
        Binding(
            get: { profileStore.grapefruitLoggingEnabled },
            set: { profileStore.setGrapefruitLoggingEnabled($0) },
        )
    }

    private var aldh2Binding: Binding<Bool> {
        Binding(
            get: { profileStore.aldh2Deficient },
            set: { profileStore.setALDH2Deficient($0) },
        )
    }

    /// Trailing summary for the Body Weight row — the value, or "Estimated" when unset.
    private var weightSummary: String {
        guard let kg = profileStore.weightKg else { return String(localized: "Estimated") }
        let value = kg.rounded() == kg ? String(Int(kg)) : String(format: "%.1f", kg)
        return "\(value) kg"
    }

    // MARK: - Version

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Piru \(version) (\(build))"
    }

    // MARK: - Colors Preview

    private var colorsPreview: some View {
        HStack(spacing: -4) {
            ForEach(substanceColors.prefix(5)) { sc in
                Circle()
                    .fill(sc.color)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(.background, lineWidth: 1.5))
            }
            if substanceColors.count > 5 {
                Text("+\(substanceColors.count - 5)")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
                    .padding(.leading, 6)
            }
        }
    }
}

// MARK: - Notifications

/// Live Activity and reminder toggles, grouped away from the main Settings
/// screen for progressive disclosure.
struct NotificationSettingsView: View {
    @AppStorage("liveActivityEnabled") private var autoLiveActivity = false
    @AppStorage("wellnessNotificationsEnabled") private var wellnessNotificationsEnabled = false
    @AppStorage("phaseNotificationsEnabled") private var phaseNotificationsEnabled = false

    var body: some View {
        List {
            Group {
                Section {
                    Toggle(isOn: $autoLiveActivity) {
                        Label("Automatic Live Activity", systemImage: "bolt.heart")
                    }
                    .tint(Theme.accent)
                } footer: {
                    Text("Automatically show a Live Activity on the Lock Screen and Dynamic Island when you start tracking a substance. You can also start one manually from a day or entry's detail view.")
                }

                Section {
                    Toggle(isOn: $wellnessNotificationsEnabled) {
                        Label("Wellness Reminders", systemImage: "heart.text.clipboard")
                    }
                    .tint(Theme.accent)
                    Toggle(isOn: $phaseNotificationsEnabled) {
                        Label("Phase Notifications", systemImage: "bell.badge.waveform")
                    }
                    .tint(Theme.accent)
                } footer: {
                    Text("Wellness reminders send hydration and sleep nudges automatically. Phase notifications alert you at onset, come-up, and peak — requires a substance with duration data.")
                }
            }
            .listRowBackground(CardBackground())
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Journal

/// Day-grouping, timeline, and quick-log preferences.
struct JournalSettingsView: View {
    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var stackRedoses = true
    @AppStorage(LaneModeDefaults.enabledKey, store: UserDefaults(suiteName: LaneModeDefaults.suite)) private var stackedLanesEnabled = LaneModeDefaults.enabledDefault
    @AppStorage(LaneModeDefaults.thresholdKey, store: UserDefaults(suiteName: LaneModeDefaults.suite)) private var laneModeThreshold = LaneModeDefaults.thresholdDefault
    @AppStorage(QuickLogManager.fixedOrderDefaultsKey) private var quickLogFixedOrder = false
    @AppStorage(Calendar.dayBoundaryHourKey, store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var dayBoundaryHour = 4

    var body: some View {
        List {
            Group {
                Section {
                    Stepper(value: $dayBoundaryHour, in: 0 ... 12) {
                        HStack {
                            Label("Day Starts At", systemImage: "moon.stars")
                            Spacer()
                            Text(boundaryHourLabel)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                } header: {
                    Text("Day Grouping")
                } footer: {
                    Text("Doses logged before this hour count toward the previous day — so a 2 AM dose stays with the night before instead of starting a new day at midnight. Set to 12 AM for standard calendar days.")
                }

                Section {
                    Toggle(isOn: $stackRedoses) {
                        Label("Stack Redoses", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .tint(Theme.accent)
                } footer: {
                    Text("Combine repeat doses of the same substance into a single curve, where each redose adds to the combined intensity. When off, each dose is drawn as its own line.")
                }

                Section {
                    Toggle(isOn: $stackedLanesEnabled) {
                        Label("Stack Busy Sessions", systemImage: "square.stack.3d.up")
                    }
                    .tint(Theme.accent)

                    if stackedLanesEnabled {
                        Stepper(value: $laneModeThreshold, in: LaneModeDefaults.thresholdRange) {
                            HStack {
                                Text("Stack From")
                                Spacer()
                                Text(laneModeThreshold, format: .number)
                                    .foregroundStyle(Theme.secondaryLabel)
                            }
                        }
                    }
                } footer: {
                    Text("When a session reaches this many different substances, the timeline splits overlapping curves into separate stacked lanes — one per substance — so a busy session stays readable. When off, every curve is always overlaid on one graph.")
                }

                Section {
                    Toggle(isOn: $quickLogFixedOrder) {
                        Label("Keep Quick-Log Order", systemImage: "pin")
                    }
                    .tint(Theme.accent)
                } footer: {
                    Text("Keep your quick-log doses in a fixed order. When off, logging a dose moves it to the front so your most-used doses stay on top.")
                }
            }
            .listRowBackground(CardBackground())
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var boundaryHourLabel: String {
        var components = DateComponents()
        components.hour = dayBoundaryHour
        let date = Calendar.current.date(from: components) ?? .now
        return date.formatted(.dateTime.hour())
    }
}

// MARK: - Substance Database

/// Everything about the bundled substance dataset: which sources win when they
/// disagree, how many substances ship, and opt-in database updates. The single
/// authoritative home for data-source information — there is no separate
/// "Sources & References" list elsewhere.
struct SubstanceDatabaseView: View {
    var body: some View {
        List {
            Group {
                Section {
                    NavigationLink {
                        SourcePriorityView()
                    } label: {
                        HStack {
                            Label("Data Sources", systemImage: "list.bullet.rectangle")
                            Spacer()
                            Text("\(SubstanceStore.shared.enabledSourceOrder.count) enabled")
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                    LabeledContent("Substances", value: "\(SubstanceStore.shared.count)")
                    SubstanceDBUpdateRow()
                } footer: {
                    Text("All substance data ships with the app. Reorder sources to choose which one wins when they disagree on a fact. Updates are opt-in and verified by sha256.")
                }

                Section {
                    EmptyView()
                } footer: {
                    Text("Pharmacological data is compiled from the sources above — community harm-reduction databases, FDA labeling, and peer-reviewed literature. Provided for harm-reduction and educational purposes only. Always consult a qualified healthcare professional before making decisions about substance use.")
                }
            }
            .listRowBackground(CardBackground())
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Substance Database")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Substance Colors List

struct SubstanceColorsListView: View {
    @Query(sort: \SubstanceColor.substance) private var substanceColors: [SubstanceColor]
    @Environment(\.modelContext) private var modelContext
    @State private var editingSubstance: SubstanceColor?

    private func takenColorMap(excluding substance: String) -> [String: String] {
        // Use uniquingKeysWith — two substances may legitimately share a hex
        // (we have ~1700 substances and ~30 preset colors). Without it, this
        // crashed in build 11 when the user opened the colour picker with
        // any duplicate-hex assignment present.
        Dictionary(
            substanceColors
                .filter { $0.substance != substance }
                .map { ($0.hexColor, $0.substance) },
            uniquingKeysWith: { first, _ in first },
        )
    }

    var body: some View {
        List {
            if substanceColors.isEmpty {
                ContentUnavailableView(
                    "No Substance Colors",
                    systemImage: "paintpalette",
                    description: Text("Colors appear here after you log your first entry. Tap one to change it."),
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(substanceColors) { sc in
                    Button {
                        editingSubstance = sc
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(sc.color)
                                .frame(width: 24, height: 24)
                            Text(CustomSubstanceStore.shared.displayName(for: sc.substance))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("Change")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        modelContext.delete(substanceColors[index])
                    }
                }
                .listRowBackground(CardBackground())
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Substance Colors")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingSubstance) { sc in
            SubstanceColorPickerView(
                substanceName: sc.substance,
                takenColors: takenColorMap(excluding: sc.substance),
            ) { hex in
                sc.hexColor = hex
                editingSubstance = nil
            }
            .presentationDetents([.large])
        }
    }
}
