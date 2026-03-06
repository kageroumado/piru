import SwiftUI
import SwiftData

struct EntryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var substanceColors: [SubstanceColor]

    let entry: DoseEntry

    @AppStorage("rampDownEnabled") private var rampDownEnabled = true
    @State private var showingEditForm = false
    @State private var showingDeleteConfirmation = false

    private var resolvedDuration: DurationProfile? {
        SubstanceLibrary.lookupByNameOrAlias(entry.substance)?
            .resolveDuration(for: entry.route)
    }

    private var hasActiveRampDown: Bool {
        RampDownScheduler.isActive(for: entry.persistentModelID.hashValue)
    }

    private var substanceState: ActiveSubstanceState? {
        let hex = substanceColors.first {
            $0.substance.lowercased() == entry.substance.lowercased()
        }?.hexColor ?? "007AFF"
        return ActiveSubstanceState.from(entry: entry, colorHex: hex)
    }

    var body: some View {
        List {
            if let state = substanceState {
                Section {
                    TimelineGraphView(
                        substances: [state],
                        currentTime: .now,
                        compact: false
                    )
                    .frame(height: 160)
                } header: {
                    Label("Timeline", systemImage: "chart.xyaxis.line")
                }
            }

            Section("Substance") {
                LabeledContent("Name", value: entry.substance)
            }

            Section("Dosage") {
                LabeledContent("Amount", value: "\(entry.amount.formatted()) \(entry.unit)")
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

            if rampDownEnabled, let duration = resolvedDuration {
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
                    Text("Get notified before the comedown to soften the landing.")
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
                HStack(spacing: 12) {
                    if substanceState != nil {
                        Button {
                            LiveActivityManager.shared.restartFromEntries(
                                [entry],
                                allColors: Array(substanceColors)
                            )
                        } label: {
                            Image(systemName: "timer")
                        }
                    }
                    Button("Edit") {
                        showingEditForm = true
                    }
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
                dismiss()
            }
        } message: {
            Text("\(entry.amount.formatted()) \(entry.unit) \(entry.substance) on \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))")
        }
        .navigationDestination(isPresented: $showingEditForm) {
            EntryFormView(entry: entry)
        }
    }

}
