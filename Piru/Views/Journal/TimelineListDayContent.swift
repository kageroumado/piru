import SwiftData
import SwiftUI

/// One day of the timeline with the axis switched off: the day tag, then the
/// dose bubbles stacked as a plain chronological list (newest first), each
/// group led by its time capsule and full width, session runs wrapped in the
/// same envelope the strip draws. Nothing here is positioned in time — the
/// slice's y layout is ignored.
struct TimelineListDayContent: View {
    let day: TimelineDayLayout
    let onEntryTap: (DoseEntry) -> Void
    let onSessionTap: (UUID) -> Void
    @Environment(\.appNavigator) private var navigator

    /// Consecutive groups sharing an envelope, or one group standing alone.
    private struct Run: Identifiable {
        let id: PersistentIdentifier
        let sessionID: UUID?
        let groups: [TimelineDayLayout.CardGroup]
    }

    private var runs: [Run] {
        var runs: [Run] = []
        for group in day.cardGroups {
            if group.inSession, let last = runs.last, last.sessionID == group.sessionID {
                runs[runs.count - 1] = Run(id: last.id, sessionID: last.sessionID, groups: last.groups + [group])
            } else {
                runs.append(Run(id: group.id, sessionID: group.inSession ? group.sessionID : nil, groups: [group]))
            }
        }
        return runs
    }

    /// The notes falling below each group — between it and the next older
    /// one, keyed by group. Notes newer than the newest group are keyed by
    /// `nil` and lead the day.
    private var notesByGroup: [PersistentIdentifier?: [TimelineDayLayout.NoteMark]] {
        var result: [PersistentIdentifier?: [TimelineDayLayout.NoteMark]] = [:]
        for note in day.noteMarks.sorted(by: { $0.timestamp > $1.timestamp }) {
            // Groups run newest first, so the group a note sits below is the
            // oldest one still newer than it.
            let group = day.cardGroups.last { $0.representativeTime > note.timestamp }
            result[group?.id, default: []].append(note)
        }
        return result
    }

    var body: some View {
        let notes = notesByGroup
        VStack(alignment: .leading, spacing: Spacing.lg) {
            TimelineDayHeader(date: day.date, isToday: day.isToday)

            noteRows(notes[nil] ?? [])

            GlassEffectContainer {
                VStack(spacing: TimelineDayLayout.groupGap) {
                    ForEach(runs) { run in
                        if let sessionID = run.sessionID {
                            groupRows(run.groups, notes: notes)
                                .padding(TimelineDayLayout.envelopePad)
                                .padding(.bottom, TimelineDayLayout.envelopeFooterHeight)
                                .background {
                                    SessionEnvelopeButton { onSessionTap(sessionID) }
                                }
                        } else {
                            groupRows(run.groups, notes: notes)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, TimelineGutter.axisX)
        .padding(.top, Spacing.xs)
        .padding(.bottom, Spacing.xxl)
    }

    private func groupRows(
        _ groups: [TimelineDayLayout.CardGroup],
        notes: [PersistentIdentifier?: [TimelineDayLayout.NoteMark]],
    ) -> some View {
        VStack(spacing: TimelineDayLayout.groupGap) {
            ForEach(groups) { group in
                HStack(alignment: .top, spacing: Spacing.md) {
                    TimelineTimeCapsule(date: group.representativeTime, hasDotSlot: false)
                    VStack(spacing: TimelineDayLayout.cardSpacing) {
                        ForEach(group.items) { item in
                            TimelineDoseBubble(
                                item: item,
                                style: day.style.bubbleStyle,
                                pkMode: day.style.pkMode,
                            ) {
                                if let sessionID = group.sessionOpenedByBubble {
                                    onSessionTap(sessionID)
                                } else {
                                    onEntryTap(item.entry)
                                }
                            }
                        }
                    }
                }
                noteRows(notes[group.id] ?? [])
            }
        }
    }

    /// Notes as their own rows between the bubbles, indented past the time
    /// capsule so the dose column stays the spine of the list.
    @ViewBuilder
    private func noteRows(_ marks: [TimelineDayLayout.NoteMark]) -> some View {
        if !marks.isEmpty {
            VStack(alignment: .leading, spacing: TimelineDayLayout.cardSpacing) {
                ForEach(marks) { mark in
                    TimelineNoteMark(mark: mark, textWidth: .infinity) {
                        navigator.present(.sessionNoteEditor(sessionID: mark.sessionID, noteID: mark.id))
                    }
                }
            }
            .padding(.leading, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
