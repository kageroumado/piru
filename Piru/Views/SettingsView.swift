import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Query(sort: \SubstanceColor.substance) private var substanceColors: [SubstanceColor]
    @Query(sort: \DailyDoseItem.sortOrder) private var dailyDoseItems: [DailyDoseItem]
    @State private var customSubstanceStore = CustomSubstanceStore.shared
    @Environment(\.modelContext) private var modelContext

    @AppStorage("liveActivityEnabled") private var autoLiveActivity = false
    @AppStorage("wellnessNotificationsEnabled") private var wellnessNotificationsEnabled = false
    @AppStorage("phaseNotificationsEnabled") private var phaseNotificationsEnabled = false
    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var stackRedoses = false
    @AppStorage(Calendar.dayBoundaryHourKey, store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var dayBoundaryHour = 4

    @State private var showingExporter = false
    @State private var showingReport = false
    @State private var showingImporter = false
    @Environment(\.appNavigator) private var navigator
    @State private var showingDeleteConfirmation = false
    @State private var exportDocument: PiruDocument?
    @State private var importMessage: String?
    @State private var showingImportMessage = false

    var body: some View {
        List {
            Group {
            Section {
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
            } header: {
                Text("Profile")
            } footer: {
                Text(SubstanceStore.shared.userProfile.summary)
            }

            Section("Prescriptions") {
                NavigationLink {
                    MedicationsSettingsView()
                } label: {
                    HStack {
                        Label("Prescriptions", systemImage: "pills")
                        Spacer()
                        Text("\(dailyDoseItems.count) prescription\(dailyDoseItems.count == 1 ? "" : "s")")
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
            }

            Section("Custom Substances") {
                NavigationLink {
                    CustomSubstancesListView()
                } label: {
                    HStack {
                        Label("Custom Substances", systemImage: "flask")
                        Spacer()
                        Text("\(customSubstanceStore.all.count)")
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
            }

            Section {
                Toggle(isOn: $autoLiveActivity) {
                    Label("Automatic Live Activity", systemImage: "bolt.heart")
                }
                .tint(Theme.accent)
            } header: {
                Text("Live Activity")
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
            } header: {
                Text("Harm Reduction")
            } footer: {
                Text("Wellness reminders send hydration and sleep nudges automatically. Phase notifications alert you at onset, come-up, and peak — requires a substance with duration data.")
            }

            Section {
                Toggle(isOn: $stackRedoses) {
                    Label("Stack Redoses", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tint(Theme.accent)
            } header: {
                Text("Timeline")
            } footer: {
                Text("Combine repeat doses of the same substance into a single curve, where each redose adds to the combined intensity. When off, each dose is drawn as its own line.")
            }

            Section {
                Stepper(value: $dayBoundaryHour, in: 0...12) {
                    HStack {
                        Label("Day Starts At", systemImage: "moon.stars")
                        Spacer()
                        Text(boundaryHourLabel)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
            } header: {
                Text("Session Day")
            } footer: {
                Text("Doses logged before this hour are grouped with the previous day's session — so a 02:00 dose joins the night before instead of starting a new day at midnight. Set to 12 AM for classic calendar-day grouping.")
            }

            Section("Substance Colors") {
                if substanceColors.isEmpty {
                    Text("No substances logged yet. Colors will appear here after you log your first entry.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                } else {
                    NavigationLink {
                        SubstanceColorsListView()
                    } label: {
                        HStack {
                            Label("Change Substance Colors", systemImage: "paintpalette")
                            Spacer()
                            colorsPreview
                        }
                    }
                }
            }

            Section {
                Button {
                    showingReport = true
                } label: {
                    Label("Generate Medical Report", systemImage: "doc.richtext")
                        .foregroundStyle(Theme.accent)
                }

                Button {
                    exportData()
                } label: {
                    Label("Export Data", systemImage: "square.and.arrow.up.on.square")
                        .foregroundStyle(Theme.accent)
                }

                Button {
                    showingImporter = true
                } label: {
                    Label("Import Data", systemImage: "square.and.arrow.down.on.square")
                        .foregroundStyle(Theme.accent)
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Everything", systemImage: "trash")
                }
            } header: {
                Text("Journal Data")
            }

            Section {
                NavigationLink {
                    SourcePriorityView()
                } label: {
                    HStack {
                        Label("Data Sources", systemImage: "books.vertical")
                        Spacer()
                        Text("\(SubstanceStore.shared.enabledSourceOrder.count) enabled")
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
                LabeledContent("Substances", value: "\(SubstanceStore.shared.count)")
                SubstanceDBUpdateRow()
            } header: {
                Text("Substance Database")
            } footer: {
                Text("All substance data ships with the app. Reorder sources to choose which one wins when they disagree on a fact. Updates are opt-in and verified by sha256.")
            }

            Section("About") {
                LabeledContent("Version", value: "1.0")
            }

            Section {
                ForEach(AppSources.all, id: \.name) { source in
                    if !source.url.isEmpty, let url = URL(string: source.url) {
                        Link(destination: url) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(source.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryLabel)
                                }
                                Text(source.detail)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.accent)
                                Text(source.description)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.secondaryLabel)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 2)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.name)
                                .font(.subheadline.weight(.medium))
                            Text(source.detail)
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                            Text(source.description)
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Label("Sources & References", systemImage: "book.closed")
            } footer: {
                Text("Pharmacological data in this app is compiled from the sources listed above. Dosage ranges, half-lives, duration profiles, mechanisms of action, and interaction data are sourced from peer-reviewed literature, FDA-approved labeling, and established pharmacological databases. Mechanism of action descriptions are based on human pharmacological research only. This information is provided for harm reduction and educational purposes only. Always consult a qualified healthcare professional before making any decisions about substance use.")
            }
            }
            .listRowBackground(Theme.cardBackground)
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
            }
        }
        .sheet(isPresented: $showingReport) {
            ReportView()
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: DataExportImport.exportFilename
        ) { result in
            exportDocument = nil
            if case .failure(let error) = result {
                importMessage = String(localized: "Export failed: \(error.localizedDescription)")
                showingImportMessage = true
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json]
        ) { result in
            importData(result: result)
        }
        .alert("Delete Everything", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete all your data? This action cannot be undone.")
        }
        .alert("Import", isPresented: $showingImportMessage) {
            Button("OK") {}
        } message: {
            Text(importMessage ?? "")
        }
    }

    // MARK: - Bindings

    private var profileBinding: Binding<UserProfile> {
        Binding(
            get: { SubstanceStore.shared.userProfile },
            set: { SubstanceStore.shared.setUserProfile($0) }
        )
    }

    // MARK: - Colors Preview

    private var boundaryHourLabel: String {
        var components = DateComponents()
        components.hour = dayBoundaryHour
        let date = Calendar.current.date(from: components) ?? .now
        return date.formatted(.dateTime.hour())
    }

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

    // MARK: - Data Actions

    private func exportData() {
        do {
            let data = try DataExportImport.exportJSON(context: modelContext)
            exportDocument = PiruDocument(data: data)
            showingExporter = true
        } catch {
            importMessage = "Export failed: \(error.localizedDescription)"
            showingImportMessage = true
        }
    }

    private func importData(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                importMessage = String(localized: "Couldn't access the selected file.")
                showingImportMessage = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                try DataExportImport.importJSON(data: data, context: modelContext)
                importMessage = String(localized: "Data imported successfully.")
                showingImportMessage = true
            } catch {
                importMessage = String(localized: "Import failed: \(error.localizedDescription)")
                showingImportMessage = true
            }
        case .failure(let error):
            importMessage = "Import failed: \(error.localizedDescription)"
            showingImportMessage = true
        }
    }

    private func deleteAllData() {
        do {
            try DataExportImport.deleteAll(context: modelContext)
        } catch {
            importMessage = String(localized: "Delete failed: \(error.localizedDescription)")
            showingImportMessage = true
        }
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
            uniquingKeysWith: { first, _ in first }
        )
    }

    var body: some View {
        List {
            ForEach(substanceColors) { sc in
                Button {
                    editingSubstance = sc
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(sc.color)
                            .frame(width: 24, height: 24)
                        Text(sc.substance)
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
            .listRowBackground(Theme.cardBackground)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Substance Colors")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingSubstance) { sc in
            SubstanceColorPickerView(
                substanceName: sc.substance,
                takenColors: takenColorMap(excluding: sc.substance)
            ) { hex in
                sc.hexColor = hex
                editingSubstance = nil
            }
            .presentationDetents([.large])
        }
    }
}
