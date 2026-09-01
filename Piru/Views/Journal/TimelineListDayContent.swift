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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TimelineDayHeader(date: day.date, isToday: day.isToday, width: nil)

            GlassEffectContainer {
                VStack(spacing: TimelineDayLayout.groupGap) {
                    ForEach(runs) { run in
                        if let sessionID = run.sessionID {
                            groupRows(run.groups)
                                .padding(TimelineDayLayout.envelopePad)
                                .padding(.bottom, TimelineDayLayout.envelopeFooterHeight)
                                .background {
                                    SessionEnvelopeButton { onSessionTap(sessionID) }
                                }
                        } else {
                            groupRows(run.groups)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, TimelineGutter.axisX)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    private func groupRows(_ groups: [TimelineDayLayout.CardGroup]) -> some View {
        VStack(spacing: TimelineDayLayout.groupGap) {
            ForEach(groups) { group in
                HStack(alignment: .top, spacing: 8) {
                    TimelineTimeCapsule(date: group.representativeTime)
                    VStack(spacing: TimelineDayLayout.cardSpacing) {
                        ForEach(group.items) { item in
                            TimelineDoseBubble(
                                item: item,
                                style: day.style.bubbleStyle,
                                pkMode: day.style.pkMode,
                            ) { onEntryTap(item.entry) }
                        }
                    }
                }
            }
        }
    }
}
