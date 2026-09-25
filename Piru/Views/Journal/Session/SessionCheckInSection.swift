import SwiftUI

/// The session's check-in schedule, said out loud.
///
/// Turning prompts on from the ⋯ menu used to leave no trace on the screen: the
/// schedule existed, would fire, and appeared nowhere. This is the section that
/// answers "what did I just turn on, and when does it arrive" — and it is the
/// only place that can say the two things the list would otherwise get wrong: a
/// prompt whose hour has gone is not coming, and one inside quiet hours is
/// never scheduled at all.
struct SessionCheckInSection: View {
    @Bindable var session: Session
    @Environment(\.appNavigator) private var navigator

    @State private var plan: [CheckInScheduler.Planned] = []
    @State private var isMuted = false

    private var cadence: CheckInScheduler.Cadence? {
        CheckInScheduler.Cadence(storedMinutes: session.checkInIntervalMinutes)
    }

    /// Recompute when the cadence, the times, or the anchoring dose moves.
    private var signature: String {
        "\(session.checkInIntervalMinutes ?? .nan)|\(session.checkInOffsetMinutes)|\(CheckInScheduler.anchor(for: session).timeIntervalSince1970)"
    }

    private var passed: [CheckInScheduler.Planned] {
        plan.filter { $0.state == .passed }
    }

    private var upcoming: [CheckInScheduler.Planned] {
        plan.filter { $0.state != .passed }
    }

    var body: some View {
        Section {
            // The times that have gone collapse to one line once there is more
            // than one: by the end of a long session every row would be a
            // past one, and the section would push the doses off the screen
            // to say nothing.
            if passed.count > 1 {
                Text("\(passed.count) earlier")
                    .font(.subheadline)
                    .foregroundStyle(Theme.tertiaryLabel)
            } else {
                ForEach(passed) { PlannedCheckInRow(planned: $0) }
            }
            ForEach(upcoming) { PlannedCheckInRow(planned: $0) }
            if cadence == .custom {
                Button {
                    navigator.present(.checkInSchedule(sessionID: session.id))
                } label: {
                    Label("Edit times", systemImage: "slider.horizontal.3")
                }
            }
        } header: {
            HStack {
                Text("Check-ins")
                Spacer()
                if let cadence {
                    Text(cadence.title)
                        .textCase(nil)
                }
            }
        } footer: {
            Text(footer)
        }
        .task(id: signature) {
            plan = CheckInScheduler.plan(for: session) ?? []
            isMuted = CheckInScheduler.isMutedByPreferences
        }
    }

    private var footer: LocalizedStringKey {
        if isMuted {
            "Check-in notifications are off in Settings, so none of these will arrive."
        } else if plan.isEmpty {
            "No times on this schedule yet."
        } else if upcoming.isEmpty {
            "All of these have passed. Times are measured from your latest dose."
        } else {
            "Times are measured from your latest dose, so logging another moves them."
        }
    }
}

// MARK: - One row

/// The offset, the wall-clock time it lands at, and what will happen to it.
private struct PlannedCheckInRow: View {
    let planned: CheckInScheduler.Planned

    var body: some View {
        HStack {
            Text(verbatim: CheckInOffsets.label(planned.offsetMinutes))
                .font(.body.monospacedDigit())
            Spacer()
            Text(planned.date, format: .dateTime.hour().minute())
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.secondaryLabel)
            if let note = stateNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryLabel)
            }
        }
        .foregroundStyle(planned.state == .passed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
        .accessibilityElement(children: .combine)
    }

    private var stateNote: LocalizedStringKey? {
        switch planned.state {
        case .scheduled: nil
        case .quietHours: "Quiet hours"
        case .passed: "Passed"
        }
    }
}
