import SwiftData
import SwiftUI

/// Choose when this session's "How is it going?" prompts fire.
///
/// Times are **relative to the session's latest dose**, not to the clock: a
/// session's shape is set by when the dose landed, and a dose logged late keeps
/// the same arc as one logged early. The rows restate each as a wall-clock time
/// so the relative number can be checked against the evening it will land in.
struct CheckInScheduleEditor: View {
    @Bindable var session: Session
    @Environment(\.appNavigator) private var navigator

    /// The draft hours/minutes in the add row.
    @State private var hours = 1
    @State private var minutes = 0
    /// Times suggested from the modeled phases of what this session logged.
    @State private var suggested: [Int] = []

    private var offsets: [Int] {
        session.checkInOffsetMinutes
    }

    private var draftMinutes: Int {
        hours * 60 + minutes
    }

    var body: some View {
        NavigationStack {
            Form {
                timesSection
                addSection
            }
            .insetGroupedListStyle()
            .task {
                await SubstanceStore.shared.ensureAllLoaded()
                suggested = CheckInLadder.suggestedOffsets(for: session)
            }
            .navigationTitle("Check-in times")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { navigator.dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Sections

    private var timesSection: some View {
        Section {
            if offsets.isEmpty {
                Text("No times yet. Add one below and the prompts start from your latest dose.")
                    .captionSecondary()
            } else {
                ForEach(offsets, id: \.self) { offset in
                    HStack {
                        Text(verbatim: CheckInOffsets.label(offset))
                            .font(.body.monospacedDigit())
                        Spacer()
                        Text(verbatim: clock(offset))
                            .captionSecondary()
                            .monospacedDigit()
                    }
                }
                .onDelete { indexSet in
                    remove(indexSet.map { offsets[$0] })
                }
            }
            // A way back to the suggestion from any edited or emptied list.
            if !suggested.isEmpty, offsets.sorted() != suggested.sorted() {
                Button {
                    apply(suggested)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(
                            offsets.isEmpty ? "Use the suggested times" : "Reset to the suggested times",
                            systemImage: "wand.and.sparkles",
                        )
                        Text(verbatim: CheckInLadder.summary(suggested))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
            }
        } header: {
            Text("After your latest dose")
        } footer: {
            Text("Up to \(CheckInOffsets.maximumCount) prompts, from \(CheckInOffsets.minimumMinutes) minutes to 24 hours after the dose. The suggested times come from the modeled phases of what you logged. Each one opens a timestamped note; none of them is required.")
        }
    }

    private var addSection: some View {
        Section {
            HStack(spacing: 0) {
                Picker("Hours", selection: $hours) {
                    ForEach(0 ..< 25) { Text("\($0) h").tag($0) }
                }
                .wheelPickerStyle()
                .frame(maxWidth: .infinity)
                Picker("Minutes", selection: $minutes) {
                    ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { Text("\($0) m").tag($0) }
                }
                .wheelPickerStyle()
                .frame(maxWidth: .infinity)
            }
            #if os(iOS)
            .frame(height: 120)
            #endif
            .labelsHidden()

            Button {
                add(draftMinutes)
            } label: {
                Label("Add \(CheckInOffsets.label(draftMinutes))", systemImage: "plus.circle.fill")
            }
            .disabled(!CheckInOffsets.canAdd(draftMinutes, to: offsets))
        } header: {
            Text("Add a time")
        } footer: {
            addFooter
        }
    }

    @ViewBuilder
    private var addFooter: some View {
        if offsets.contains(draftMinutes) {
            Text("\(CheckInOffsets.label(draftMinutes)) is already on the list.")
        } else if offsets.count >= CheckInOffsets.maximumCount {
            Text("You've reached the limit for check-in times in this session. Remove one to add another.")
        } else if draftMinutes < CheckInOffsets.minimumMinutes {
            Text("The first prompt arrives at least \(CheckInOffsets.minimumMinutes) minutes after the dose.")
        }
    }

    // MARK: Edits

    private func add(_ minutes: Int) {
        apply(offsets + [minutes])
    }

    private func remove(_ minutes: [Int]) {
        apply(offsets.filter { !minutes.contains($0) })
    }

    /// Every edit rewrites the list and reschedules, so closing the sheet is
    /// never the thing that commits — there is no draft to lose.
    private func apply(_ minutes: [Int]) {
        withAnimation(.smooth(duration: 0.2)) {
            session.checkInOffsetMinutes = minutes
            session.checkInIntervalMinutes = CheckInScheduler.Cadence.custom.storedMinutes
            session.checkInOffered = true
        }
        Task {
            _ = await DoseNotificationManager.requestAuthorization()
            CheckInScheduler.sync(session: session)
        }
    }

    /// The wall-clock time an offset lands at, from the same anchor the
    /// scheduler uses — so the sheet and the notification cannot disagree.
    private func clock(_ offset: Int) -> String {
        CheckInScheduler.anchor(for: session)
            .addingTimeInterval(Double(offset) * 60)
            .formatted(date: .omitted, time: .shortened)
    }
}
