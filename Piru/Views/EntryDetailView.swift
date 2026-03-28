import SwiftUI
import SwiftData
import WidgetKit

struct EntryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var substanceColors: [SubstanceColor]

    let entry: DoseEntry

    @State private var showingEditForm = false
    @State private var showingDeleteConfirmation = false
    @State private var showColorPicker = false

    private var resolvedDuration: DurationProfile? {
        SubstanceLibrary.lookupByNameOrAlias(entry.substance)?
            .resolveDuration(for: entry.route)
    }

    private var hasActiveRampDown: Bool {
        RampDownScheduler.isActive(for: entry.persistentModelID.hashValue)
    }

    private var currentColorHex: String {
        substanceColors.first {
            $0.substance.lowercased() == entry.substance.lowercased()
        }?.hexColor ?? "007AFF"
    }

    private var substanceState: ActiveSubstanceState? {
        ActiveSubstanceState.from(entry: entry, colorHex: currentColorHex)
    }

    var body: some View {
        List {
            if let state = substanceState {
                Section {
                    VStack(spacing: 8) {
                        HStack {
                            Spacer()
                            Button("Live Activity") {
                                LiveActivityManager.shared.restartFromEntries(
                                    [entry],
                                    allColors: Array(substanceColors)
                                )
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.accent)
                        }
                        .padding(.horizontal, 12)
                        TimelineGraphView(
                            substances: [state],
                            currentTime: .now,
                            compact: false
                        )
                        .frame(height: 160)
                    }
                } header: {
                    Label("Timeline", systemImage: "chart.xyaxis.line")
                } footer: {
                    Text("Pinch to zoom in or out")
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
            } else {
                Section {
                    Label("No pharmacokinetic data available for this substance and route.", systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                        .padding(.vertical, 4)
                } header: {
                    Label("Timeline", systemImage: "chart.xyaxis.line")
                }
            }

            Section("Substance") {
                LabeledContent("Name", value: entry.substance)
                Button {
                    showColorPicker = true
                } label: {
                    HStack {
                        Text("Color")
                            .foregroundStyle(.primary)
                        Spacer()
                        Circle()
                            .fill(Color(hex: currentColorHex))
                            .frame(width: 16, height: 16)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
            }

            Section("Dosage") {
                LabeledContent("Amount", value: "\(entry.amount.doseFormatted) \(entry.unit)")
                LabeledContent("Route", value: entry.route.displayName)
            }

            Section("Timing") {
                LabeledContent("Date", value: entry.timestamp.formatted(date: .long, time: .shortened))
            }

            if let notes = entry.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }

            if !entry.tags.isEmpty {
                Section("Tags") {
                    TagChipsView(tags: entry.tags)
                }
            }

            if let duration = resolvedDuration {
                Section {
                    NavigationLink {
                        RampDownView(entry: entry, duration: duration)
                    } label: {
                        HStack {
                            Label("Comedown Alert", systemImage: "bell.badge")
                            Spacer()
                            if hasActiveRampDown {
                                Text("Active")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                } footer: {
                    Text("Get care reminders as effects fade — hydration, rest, and recovery tips.")
                }
            }

            Section {
                Button("Delete Entry", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(entry.substance)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditForm = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                modelContext.delete(entry)
                WidgetCenter.shared.reloadAllTimelines()
                dismiss()
            }
        } message: {
            Text("\(entry.amount.doseFormatted) \(entry.unit) \(entry.substance) on \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))")
        }
        .sheet(isPresented: $showingEditForm) {
            EntryFormView(entry: entry)
        }
        .sheet(isPresented: $showColorPicker) {
            SubstanceColorPickerView(
                substanceName: entry.substance,
                takenColors: Array(substanceColors).takenColorMap
            ) { hex in
                if let existing = substanceColors.first(where: { $0.substance.lowercased() == entry.substance.lowercased() }) {
                    existing.hexColor = hex
                } else {
                    modelContext.insert(SubstanceColor(substance: entry.substance, hexColor: hex))
                }
            }
            .presentationDetents([.large])
        }
    }

}
