import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Query(sort: \SubstanceColor.substance) private var substanceColors: [SubstanceColor]
    @Query(sort: \DailyDoseItem.sortOrder) private var dailyDoseItems: [DailyDoseItem]
    @Environment(\.modelContext) private var modelContext

    @State private var showingExporter = false
    @State private var showingImporter = false
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false
    @State private var exportDocument: PiruDocument?
    @State private var importMessage: String?
    @State private var showingImportMessage = false

    var body: some View {
        List {
            Section("Daily Dose") {
                NavigationLink {
                    DailyDoseSettingsView()
                } label: {
                    HStack {
                        Label("Manage Daily Dose", systemImage: "pills")
                        Spacer()
                        Text("\(dailyDoseItems.count) item\(dailyDoseItems.count == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Substance Colors") {
                if substanceColors.isEmpty {
                    Text("No substances logged yet. Colors will appear here after you log your first entry.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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

            Section("About") {
                LabeledContent("Substances in Library", value: "\(SubstanceLibrary.all.count)")
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
                                        .foregroundStyle(.secondary)
                                }
                                Text(source.detail)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.accent)
                                Text(source.description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
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
                                .foregroundStyle(.secondary)
                            Text(source.description)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Label("Sources & References", systemImage: "book.closed")
            } footer: {
                Text("Pharmacological data in this app is compiled from the sources listed above. Dosage ranges, half-lives, duration profiles, and interaction data are sourced from peer-reviewed literature, FDA-approved labeling, and established pharmacological databases. This information is provided for harm reduction and educational purposes only. Always consult a qualified healthcare professional before making any decisions about substance use.")
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                }
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: DataExportImport.exportFilename
        ) { result in
            exportDocument = nil
            if case .failure(let error) = result {
                importMessage = "Export failed: \(error.localizedDescription)"
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
                    .foregroundStyle(.secondary)
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
                importMessage = "Couldn't access the selected file."
                showingImportMessage = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                try DataExportImport.importJSON(data: data, context: modelContext)
                importMessage = "Data imported successfully."
                showingImportMessage = true
            } catch {
                importMessage = "Import failed: \(error.localizedDescription)"
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
            importMessage = "Delete failed: \(error.localizedDescription)"
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
        Dictionary(uniqueKeysWithValues:
            substanceColors
                .filter { $0.substance != substance }
                .map { ($0.hexColor, $0.substance) }
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
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    modelContext.delete(substanceColors[index])
                }
            }
        }
        .navigationTitle("Substance Colors")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingSubstance) { sc in
            SubstanceColorPickerView(
                substanceName: sc.substance,
                takenColors: takenColorMap(excluding: sc.substance)
            ) { hex in
                sc.hexColor = hex
            }
            .presentationDetents([.large])
        }
    }
}
