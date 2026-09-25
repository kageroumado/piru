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
    let social: Int?
    let worked: Int?
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
                social: note.social,
                worked: note.worked,
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
        TripReport.structureLine(
            shulgin: display.shulgin, mood: display.mood, energy: display.energy,
            social: display.social, heartRate: display.heartRate,
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            noteContent
            if let worked = display.worked, let label = WorkedScale.label(worked) {
                workedLink(label)
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
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

    /// The one link from the record to the interpretation, and it points that
    /// way only: the row keeps showing the word that was entered, and the
    /// screen it opens is the only place anything is concluded from it.
    private func workedLink(_ label: LocalizedStringResource) -> some View {
        // `.borderless`, and the rest of the row a tap gesture rather than a
        // button: a List row routes every tap to the single control it finds,
        // so two buttons — or a button beside a NavigationLink — both opened
        // the note editor from here.
        Button {
            navigator.push(.insight(.feltPatterns))
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(label)
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Theme.accent)
            .padding(.leading, IconSize.iconMini + Spacing.xl)
            .padding(.vertical, Spacing.xs)
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityHint(Text("Opens how this compares with your other days"))
    }

    private var noteContent: some View {
        HStack(alignment: .top, spacing: Spacing.xl) {
            Image(systemName: glyph)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accent)
                .frame(width: IconSize.iconMini, height: IconSize.iconMini)
                .background(Theme.accent.opacity(Theme.Opacity.tint), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
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
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Text(display.timestamp, style: .time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryLabel)
                if showRelativeTime {
                    Text(display.timestamp, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                        .font(.caption2)
                        .foregroundStyle(Theme.tertiaryLabel)
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        }
        .contentShape(.rect)
        .onTapGesture { navigator.present(.sessionNoteEditor(sessionID: sessionID, noteID: display.id)) }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Edits the note"))
    }
}
