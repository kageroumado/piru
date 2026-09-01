import SwiftData
import SwiftUI

/// The session detail's ⋯ toolbar menu: title/note editing, graph controls, Live
/// Activity, and the split/merge session-level overrides. Reads its own editing
/// service, model context, and graph `@AppStorage` rather than having the detail
/// view thread them down; content mutations that touch the parent's edit state
/// (rename, note) come in as closures.
struct SessionMenu: View {
    let session: Session
    /// Whether the timeline drew at least one curve — gates the graph controls.
    let hasCurves: Bool
    let isToday: Bool
    let hasOngoingDose: Bool
    /// The dose immediately after the session's widest interior gap, with a
    /// formatted gap label — the pivot "Split at Longest Break" cuts at. `nil` when
    /// there's no gap worth splitting.
    let longestBreakPivot: (dose: DoseEntry, gapText: String)?
    let onRename: () -> Void
    let onAddNote: () -> Void
    let onEditSummary: () -> Void
    let onToggleLiveActivity: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.sessionEditingService) private var editing
    @AppStorage(SessionGraphDefaults.enlargedKey, store: UserDefaults(suiteName: SessionGraphDefaults.suite))
    private var timelineEnlarged = SessionGraphDefaults.enlargedDefault
    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var stackRedoses = true

    var body: some View {
        Menu {
            Button {
                onRename()
            } label: {
                Label(session.title == nil ? "Add Title" : "Rename", systemImage: "pencil")
            }
            Button {
                onAddNote()
            } label: {
                Label("Add Note", systemImage: "quote.opening")
            }
            Button {
                onEditSummary()
            } label: {
                Label(session.note == nil ? "Add Summary" : "Edit Summary", systemImage: "text.alignleft")
            }
            if hasOngoingDose || session.checkInIntervalMinutes != nil {
                checkInMenu
            }
            if hasCurves {
                Divider()
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) { timelineEnlarged.toggle() }
                } label: {
                    Label(
                        timelineEnlarged ? "Shrink Graph" : "Expand Graph",
                        systemImage: timelineEnlarged ? "arrow.down.right.and.arrow.up.left" : "arrow.up.backward.and.arrow.down.forward",
                    )
                }
                Toggle(isOn: $stackRedoses) {
                    Label("Stack Redoses", systemImage: "chart.line.uptrend.xyaxis")
                }
                if isToday, hasOngoingDose {
                    let isRunning = LiveActivityManager.shared.isLiveActivityRunning
                    Button {
                        onToggleLiveActivity()
                    } label: {
                        Label(
                            isRunning ? "Stop Live Activity" : "Start Live Activity",
                            systemImage: isRunning ? "stop.fill" : "dot.radiowaves.up.forward",
                        )
                    }
                }
            }
            if let pivot = longestBreakPivot {
                Divider()
                Button {
                    withAnimation { editing.split(at: pivot.dose, in: modelContext) }
                } label: {
                    Label(
                        "Split at Longest Break (\(pivot.gapText))",
                        systemImage: "scissors",
                    )
                }
            }
            if let previous = fetchPreviousSession() {
                Divider()
                Button {
                    withAnimation { SessionService.merge(previous, into: session, in: modelContext) }
                } label: {
                    Label("Merge with Previous", systemImage: "arrow.triangle.merge")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(Text("Session options"))
    }

    /// Per-session check-in cadence: off, or one of the cadences. Changing it
    /// reschedules from the latest dose.
    private var checkInMenu: some View {
        Menu {
            Picker("Check-ins", selection: cadenceSelection) {
                Text("Off").tag(CheckInScheduler.Cadence?.none)
                ForEach(CheckInScheduler.Cadence.allCases) { cadence in
                    Text(cadence.title).tag(CheckInScheduler.Cadence?.some(cadence))
                }
            }
        } label: {
            Label("Check-ins", systemImage: "quote.bubble")
        }
    }

    private var cadenceSelection: Binding<CheckInScheduler.Cadence?> {
        Binding(
            get: { CheckInScheduler.Cadence(storedMinutes: session.checkInIntervalMinutes) },
            set: { cadence in
                session.checkInOffered = true
                session.checkInIntervalMinutes = cadence?.storedMinutes
                Task {
                    if cadence != nil { _ = await DoseNotificationManager.requestAuthorization() }
                    CheckInScheduler.sync(session: session)
                }
            },
        )
    }

    /// The session immediately before this one in time — the target for "Merge with
    /// previous". A bounded one-row fetch resolved when the menu opens, rather than a
    /// whole-table `@Query` that would re-run the detail view's body on every change
    /// to any session. `startDate < session.startDate` already excludes self.
    private func fetchPreviousSession() -> Session? {
        let cutoff = session.startDate
        var descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.startDate < cutoff },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)],
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}
