import SwiftData
import SwiftUI

/// The intents a session card's context menu raises in the Journal list. The
/// list owns one instance and hangs the matching alert/sheets off itself via
/// ``View/sessionCardActions(_:colors:)``; the menu rows only write here.
@MainActor
@Observable
final class SessionCardActionModel {
    var renameTarget: Session?
    var renameDraft = ""
    /// A multi-dose session to pick a dose from before moving it.
    var moveTarget: Session?
    /// A session's only dose — goes straight to the move picker.
    var moveDose: DoseEntry?
    var shareTarget: Session?

    func rename(_ session: Session) {
        renameDraft = session.title ?? ""
        renameTarget = session
    }

    func moveDoses(of session: Session) {
        let doses = session.orderedDoses
        if doses.count == 1, let only = doses.first {
            moveDose = only
        } else {
            moveTarget = session
        }
    }
}

/// Context-menu rows for a session card — the same mutations the session
/// detail's ⋯ menu performs (`SessionEditingService.split`, `SessionService`
/// rename, the per-dose move picker, the share sheet), reachable without
/// opening the session.
struct SessionCardContextMenu: View {
    let session: Session
    let actions: SessionCardActionModel

    @Environment(\.modelContext) private var modelContext
    @Environment(\.sessionEditingService) private var editing

    var body: some View {
        Button {
            actions.rename(session)
        } label: {
            Label(session.title == nil ? "Add Title…" : "Rename…", systemImage: "pencil")
        }
        if let pivot = SessionMenu.longestBreakPivot(in: session.orderedDoses) {
            Button {
                editing.split(at: pivot.dose, in: modelContext)
            } label: {
                Label("Split at Longest Break (\(pivot.gapText))", systemImage: "scissors")
            }
        }
        Button {
            actions.moveDoses(of: session)
        } label: {
            Label("Move Doses…", systemImage: "arrow.right.arrow.left")
        }
        Button {
            actions.shareTarget = session
        } label: {
            Label("Share Report", systemImage: "square.and.arrow.up")
        }
    }
}

extension View {
    /// Attaches the rename alert and the move/share sheets that
    /// ``SessionCardContextMenu`` drives through `model`.
    func sessionCardActions(_ model: SessionCardActionModel, colors: [SubstanceColor]) -> some View {
        modifier(SessionCardActionsModifier(model: model, colors: colors))
    }
}

private struct SessionCardActionsModifier: ViewModifier {
    @Bindable var model: SessionCardActionModel
    let colors: [SubstanceColor]

    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var stackRedoses = true

    private var renameIsPresented: Binding<Bool> {
        Binding(
            get: { model.renameTarget != nil },
            set: { if !$0 { model.renameTarget = nil } },
        )
    }

    func body(content: Content) -> some View {
        content
            .alert("Rename Session", isPresented: renameIsPresented, presenting: model.renameTarget) { session in
                TextField("Session title", text: $model.renameDraft)
                Button("Cancel", role: .cancel) {}
                Button("Save") { SessionService.setTitle(model.renameDraft, for: session) }
            }
            .sheet(item: $model.moveDose) { dose in
                MoveToSessionView(dose: dose)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $model.moveTarget) { session in
                MoveDosesSheet(session: session)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $model.shareTarget) { session in
                SessionShareSheet(
                    title: session.title ?? "",
                    dateText: Self.dateText(for: session.startDate),
                    entries: session.orderedDoses,
                    colors: colors,
                    stackRedoses: stackRedoses,
                )
            }
    }

    /// "Saturday, August 30" — the session detail's navigation title, so the
    /// report shared from the card reads the same as one shared from inside.
    private static func dateText(for date: Date) -> String {
        let base = Date.FormatStyle.dateTime.day().month(.wide)
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        let dateTitle = date.formatted(sameYear ? base : base.year())
        return "\(date.formatted(.dateTime.weekday(.wide))), \(dateTitle)"
    }
}

/// Which of a session's doses to move: one row per dose, tapping one opens the
/// per-dose ``MoveToSessionView``. Closes itself once the session has no doses
/// left (the last move deletes the emptied session).
private struct MoveDosesSheet: View {
    let session: Session

    @Environment(\.dismiss) private var dismiss
    @Query private var substanceColors: [SubstanceColor]
    @State private var doseToMove: DoseEntry?

    private static let clock = Date.FormatStyle.dateTime.hour().minute()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(session.orderedDoses) { dose in
                        Button {
                            doseToMove = dose
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Array(substanceColors).colorMap[dose.substance.lowercased()] ?? Theme.accent)
                                    .frame(width: 12, height: 12)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(CustomSubstanceStore.shared.displayName(for: dose.substance))
                                        .font(.headline)
                                    Text(dose.timestamp.formatted(Self.clock))
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryLabel)
                                }
                                Spacer()
                                Text("\(dose.amount.doseFormatted) \(dose.unit)")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondaryLabel)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(CardBackground())
                    }
                } footer: {
                    Text("Pick a dose to move to another session.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Move Doses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Cancel"))
                }
            }
        }
        .sheet(item: $doseToMove) { dose in
            MoveToSessionView(dose: dose)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: DoseLogService.shared.revision) {
            if session.isDeleted || (session.doses ?? []).isEmpty {
                dismiss()
            }
        }
    }
}
