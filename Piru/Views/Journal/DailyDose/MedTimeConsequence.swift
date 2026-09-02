import SwiftUI

// Consequences at pick-time (`Specs/archive/meds-ux-review.md` §9).
//
// A time picker that says only "morning" makes the user do the pharmacology in
// their head: they choose 4 PM without any way to see that this particular med
// is still working at midnight. Piru already models onset, peak and offset for
// every dose it draws — the same numbers behind the journal curve — so the form
// can simply *state* them against the clock the user is setting.
//
// Reference, not instruction: it says what the model says the med does, and
// never that a time is wrong or that a different one would be better.

/// When a scheduled dose starts working, starts easing off, and — for the
/// classes that hold sleep off — when it is out of the way of it.
///
/// Minutes are relative to the scheduled time. All three come from the profile
/// the timeline itself draws (``Substance/timelineDuration(for:)``, phase-filled
/// exactly as the curve is), so the form and the graph can never disagree about
/// the same med.
struct MedTimeConsequence: Equatable {
    /// End of the onset phase — the modeled moment effects begin.
    let onsetMinutes: Double
    /// End of the peak plateau — where the offset limb starts.
    let wearOffMinutes: Double
    /// End of acute effects, the same value the entry rail calls "effects ended".
    let effectsEndMinutes: Double
    /// Whether this med's class is one that holds sleep off, making the
    /// effects-end time worth stating against bedtime rather than left implicit.
    let affectsSleep: Bool

    /// Local hours the sleep clause treats as "most people's night". Used only
    /// to decide whether the effects-end time is worth flagging — never to
    /// prescribe a bedtime, which Piru does not know and does not ask for.
    static let nightStartHour = 22
    static let nightEndHour = 6

    /// `nil` — say nothing — whenever the model has no acute answer: a custom
    /// substance, or a chronic med (SSRIs, thyroid, GLP-1s) whose
    /// ``Substance/timelineDuration(for:)`` is deliberately absent because an
    /// onset→peak→offset shape is the wrong model for it. A med that steadies a
    /// level over weeks does not "kick in" at 9:35, and inventing a time for it
    /// would be worse than the silence this replaces.
    static func resolve(substance: Substance?, route: RouteOfAdministration) -> MedTimeConsequence? {
        guard let substance, let raw = substance.timelineDuration(for: route) else { return nil }
        // Same phase fill the curve is drawn with, so endpoint-only source data
        // (a `total` with no come-up/peak) still yields a peak boundary instead
        // of collapsing onto the onset.
        let profile = raw.fillingMissingPhases(for: substance.category)
        let bounds = profile.phaseBoundaries
        let end = profile.estimatedTotalMinutes
        let onset = max(0, bounds.onsetEnd)
        guard end > onset else { return nil }
        return MedTimeConsequence(
            onsetMinutes: onset,
            wearOffMinutes: min(max(bounds.peakEnd, onset), end),
            effectsEndMinutes: end,
            affectsSleep: SubstanceCategory.wakePromoting.contains(substance.category),
        )
    }

    /// Whether the easing-off moment is far enough from the end to be worth its
    /// own clause. A profile with no offset phase puts both at the same minute,
    /// where printing them twice reads as a rendering bug.
    var statesWearOff: Bool {
        effectsEndMinutes - wearOffMinutes >= 1 && wearOffMinutes - onsetMinutes >= 1
    }

    /// The three moments as absolute dates, anchored to `minutesOfDay` on
    /// `reference`'s day. Crossing midnight is ordinary here (a 4 PM stimulant
    /// routinely clears the next morning), so the dates simply run forward.
    func clockTimes(
        minutesOfDay: Int,
        on reference: Date = .now,
        calendar: Calendar = .current,
    ) -> (onset: Date, wearOff: Date, effectsEnd: Date) {
        let base = calendar.date(
            bySettingHour: minutesOfDay / 60, minute: minutesOfDay % 60, second: 0, of: reference,
        ) ?? reference
        return (
            base.addingTimeInterval(onsetMinutes * 60),
            base.addingTimeInterval(wearOffMinutes * 60),
            base.addingTimeInterval(effectsEndMinutes * 60),
        )
    }

    /// Whether effects run into the hours most people are asleep. A population
    /// statement, and the only kind available: Piru holds no bedtime for anyone.
    func landsInNight(minutesOfDay: Int, on reference: Date = .now, calendar: Calendar = .current) -> Bool {
        let end = clockTimes(minutesOfDay: minutesOfDay, on: reference, calendar: calendar).effectsEnd
        let hour = calendar.component(.hour, from: end)
        return hour >= Self.nightStartHour || hour < Self.nightEndHour
    }
}

/// The line under one time row: what that time does.
///
/// Its own `View` so a keystroke in the amount field doesn't re-evaluate it, and
/// so the (pure) formatting stays testable apart from the form's draft state.
struct MedTimeConsequenceLine: View {
    let consequence: MedTimeConsequence
    let minutesOfDay: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Label {
                effectText
            } icon: {
                Image(systemName: "clock")
                    .accessibilityHidden(true)
            }
            if consequence.affectsSleep {
                Label {
                    sleepText
                } icon: {
                    Image(systemName: "moon.zzz")
                        .foregroundStyle(landsInNight ? .orange : Theme.secondaryLabel)
                        .accessibilityHidden(true)
                }
            }
        }
        .captionSecondary()
        .padding(.top, Spacing.xxs)
    }

    private var times: (onset: Date, wearOff: Date, effectsEnd: Date) {
        consequence.clockTimes(minutesOfDay: minutesOfDay)
    }

    private var landsInNight: Bool {
        consequence.landsInNight(minutesOfDay: minutesOfDay)
    }

    @ViewBuilder
    private var effectText: some View {
        let moments = times
        if consequence.statesWearOff {
            Text("Kicks in ~\(Self.clock(moments.onset)) · easing off ~\(Self.clock(moments.wearOff))")
        } else {
            Text("Kicks in ~\(Self.clock(moments.onset))")
        }
    }

    @ViewBuilder
    private var sleepText: some View {
        let end = Self.clock(times.effectsEnd)
        if landsInNight {
            Text("Clear for sleep ~\(end) — after most bedtimes.")
        } else {
            Text("Clear for sleep ~\(end)")
        }
    }

    private static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
