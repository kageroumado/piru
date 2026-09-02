import SwiftUI

/// Render-ready facts for one note row — every vocabulary lookup resolved
/// upstream so the row does no store access in `body`. Value type + `Equatable`
/// so the list diffs cheaply.
struct SessionNoteDisplay: Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let kind: SessionNote.Kind
    let text: String
    let shulgin: Int?
    let mood: Int?
    let energy: Int?
    let heartRate: Int?
    /// Descriptor names, in the order chosen; ids the vocabulary no longer
    /// resolves are dropped.
    let descriptors: [String]

    @MainActor
    static func make(from notes: [SessionNote]) -> [SessionNoteDisplay] {
        let ontology = SubjectiveEffectOntology.shared
        return notes.map { note in
            SessionNoteDisplay(
                id: note.id,
                timestamp: note.timestamp,
                kind: note.kind,
                text: note.text,
                shulgin: note.shulgin,
                mood: note.mood,
                energy: note.energy,
                heartRate: note.heartRate.map { Int($0.rounded()) },
                descriptors: note.descriptors.compactMap(ontology.name(for:)),
            )
        }
    }
}

/// One note in the session's entry list — visually distinct from a dose row: a
/// quote glyph, muted text, no dose chips. Tap opens the editor; swipe deletes.
struct SessionNoteRow: View, Equatable {
    /// The model — read only by the swipe/menu *actions*, never in `body`, and
    /// excluded from `==` (see `DayEntryRow`).
    let note: SessionNote
    let display: SessionNoteDisplay
    let sessionID: UUID
    let showRelativeTime: Bool

    @Environment(\.appNavigator) private var navigator

    static func == (lhs: SessionNoteRow, rhs: SessionNoteRow) -> Bool {
        lhs.display == rhs.display && lhs.showRelativeTime == rhs.showRelativeTime && lhs.sessionID == rhs.sessionID
    }

    private var glyph: String {
        TimelineGraphView.glyph(for: display.kind)
    }

    private var structure: String {
        TripReport.structureLine(shulgin: display.shulgin, mood: display.mood, energy: display.energy, heartRate: display.heartRate)
    }

    var body: some View {
        Button {
            navigator.present(.sessionNoteEditor(sessionID: sessionID, noteID: display.id))
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: glyph)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 22, height: 22)
                    .background(Theme.accent.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    if display.kind != .observation {
                        Text(display.kind == .summary ? "Summary" : "Check-in")
                            .font(.caption2.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    if !display.text.isEmpty {
                        Text(display.text)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                            .lineLimit(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !structure.isEmpty {
                        Text(verbatim: structure)
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    if !display.descriptors.isEmpty {
                        Text(verbatim: display.descriptors.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                // Each time label stays on one line: the column keeps its natural
                // width against the text column and never wraps "1 hr. ago" under
                // the clock time.
                VStack(alignment: .trailing, spacing: 2) {
                    Text(display.timestamp, style: .time)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondaryLabel)
                    if showRelativeTime {
                        Text(display.timestamp, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        .accessibilityHint(Text("Edits the note"))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation { SessionNoteService.delete(note) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                navigator.present(.sessionNoteEditor(sessionID: sessionID, noteID: display.id))
            } label: {
                Label("Edit Note", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                withAnimation { SessionNoteService.delete(note) }
            } label: {
                Label("Delete Note", systemImage: "trash")
            }
        }
    }
}
