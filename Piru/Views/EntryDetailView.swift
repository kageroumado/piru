import SwiftUI
import SwiftData

struct EntryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var substanceColors: [SubstanceColor]

    let entry: DoseEntry

    @State private var showingEditForm = false
    @State private var showingDeleteConfirmation = false

    private var substanceState: ActiveSubstanceState? {
        guard let matched = SubstanceLibrary.lookupByNameOrAlias(entry.substance),
              let duration = matched.resolveDuration(for: entry.route) else { return nil }

        let boundaries = duration.phaseBoundaries
        let hex = substanceColors.first {
            $0.substance.lowercased() == entry.substance.lowercased()
        }?.hexColor ?? "007AFF"

        return ActiveSubstanceState(
            substanceName: entry.substance,
            colorHex: hex,
            doseTimestamp: entry.timestamp,
            amount: entry.amount,
            unit: entry.unit,
            route: entry.route.displayName,
            onsetEndMinutes: boundaries.onsetEnd,
            comeupEndMinutes: boundaries.comeupEnd,
            peakEndMinutes: boundaries.peakEnd,
            offsetEndMinutes: boundaries.offsetEnd,
            afterglowEndMinutes: duration.afterglow != nil ? boundaries.afterglowEnd : nil,
            totalMinutes: duration.estimatedTotalMinutes
        )
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
