import SwiftUI
import SwiftData

struct EntryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var substanceColors: [SubstanceColor]

    let entry: DoseEntry

    @State private var showingEditForm = false
    @State private var showingDeleteConfirmation = false
    @State private var substanceState: ActiveSubstanceState?

    var body: some View {
        List {
            if let state = substanceState {
                Section {
                    TimelineGraphView(
                        substances: [state],
                        currentTime: .now,
                        compact: false
                    )
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
        .task {
            await buildSubstanceState()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    showingEditForm = true
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
        .sheet(isPresented: $showingEditForm) {
            EntryFormView(entry: entry)
        }
    }

    private func buildSubstanceState() async {
        guard let matched = SubstanceLibrary.search(entry.substance).first(where: {
            $0.name.lowercased() == entry.substance.lowercased()
        }),
        let duration = matched.duration(for: entry.route) else { return }

        let boundaries = duration.phaseBoundaries
        let hex = substanceColors.first {
            $0.substance.lowercased() == entry.substance.lowercased()
        }?.hexColor ?? "007AFF"

        self.substanceState = ActiveSubstanceState(
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
}
