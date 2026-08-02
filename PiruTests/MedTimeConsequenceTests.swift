import Foundation
import Testing
@testable import Piru

/// What a scheduled med time says about itself — the onset/wear-off/sleep
/// readout under each row of `MedFormView`.
@Suite("MedTimeConsequence")
@MainActor
struct MedTimeConsequenceTests {
    /// A typical oral stimulant: effects at 30 min, peak through 4 h, done at 8 h.
    private func stimulant(
        category: SubstanceCategory = .stimulant,
        duration: DurationProfile? = DurationProfile(
            onset: DurationRange(min: 20, max: 40),
            comeup: DurationRange(min: 20, max: 40),
            peak: DurationRange(min: 150, max: 210),
            offset: DurationRange(min: 90, max: 150),
            afterglow: nil,
            total: DurationRange(min: 420, max: 540),
        ),
    ) -> Substance {
        Substance(
            name: "Testine",
            aliases: [],
            category: category,
            defaultRoute: .oral,
            routes: [SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(common: 10 ... 20), duration: duration)],
            effects: [],
        )
    }

    /// 9:00 AM on an arbitrary but fixed day, so the clock math is deterministic.
    private var nineAM: Date {
        Calendar.current.date(from: DateComponents(year: 2_026, month: 3, day: 12, hour: 9))!
    }

    @Test
    func `Onset and wear-off come off the substance's own duration profile`() throws {
        let consequence = try #require(MedTimeConsequence.resolve(substance: stimulant(), route: .oral))
        #expect(consequence.onsetMinutes == 30)
        // Onset 30 + come-up 30 + peak 180 — the offset limb starts at 4 h.
        #expect(consequence.wearOffMinutes == 240)
        #expect(consequence.effectsEndMinutes == 480)
        #expect(consequence.statesWearOff)
    }

    @Test
    func `A substance with no acute profile says nothing`() {
        // The chronic-med case: an SSRI has a half-life and no onset→peak→offset
        // table, and inventing a "kicks in at 9:35" for it would be a fiction.
        #expect(MedTimeConsequence.resolve(substance: stimulant(duration: nil), route: .oral) == nil)
    }

    @Test
    func `A hand-typed custom substance says nothing`() {
        #expect(MedTimeConsequence.resolve(substance: nil, route: .oral) == nil)
    }

    @Test
    func `Clock times are anchored to the scheduled minute of day`() throws {
        let consequence = try #require(MedTimeConsequence.resolve(substance: stimulant(), route: .oral))
        let times = consequence.clockTimes(minutesOfDay: 9 * 60, on: nineAM)
        #expect(times.onset == nineAM.addingTimeInterval(30 * 60))
        #expect(times.wearOff == nineAM.addingTimeInterval(240 * 60))
        #expect(times.effectsEnd == nineAM.addingTimeInterval(480 * 60))
    }

    // MARK: - The sleep clause

    @Test
    func `Only wake-promoting classes get a sleep line`() throws {
        for category in [SubstanceCategory.stimulant, .empathogen, .eugeroic] {
            let consequence = try #require(MedTimeConsequence.resolve(substance: stimulant(category: category), route: .oral))
            #expect(consequence.affectsSleep, "\(category) holds sleep off")
        }
        for category in [SubstanceCategory.antidepressant, .supplement, .antihistamine, .opioid] {
            let consequence = try #require(MedTimeConsequence.resolve(substance: stimulant(category: category), route: .oral))
            #expect(!consequence.affectsSleep, "\(category) makes no wakefulness claim")
        }
    }

    @Test
    func `A morning dose clears well before the night`() throws {
        let consequence = try #require(MedTimeConsequence.resolve(substance: stimulant(), route: .oral))
        // 9:00 + 8 h = 5 PM.
        #expect(!consequence.landsInNight(minutesOfDay: 9 * 60, on: nineAM))
    }

    @Test
    func `An afternoon dose that runs into the night is flagged`() throws {
        let consequence = try #require(MedTimeConsequence.resolve(substance: stimulant(), route: .oral))
        // 4 PM + 8 h = midnight; 6 PM + 8 h = 2 AM. Both sit in most people's night.
        #expect(consequence.landsInNight(minutesOfDay: 16 * 60, on: nineAM))
        #expect(consequence.landsInNight(minutesOfDay: 18 * 60, on: nineAM))
        // 1 PM + 8 h = 9 PM — before it.
        #expect(!consequence.landsInNight(minutesOfDay: 13 * 60, on: nineAM))
    }

    @Test
    func `A profile with no offset limb does not print the same time twice`() throws {
        let flat = DurationProfile(
            onset: DurationRange(min: 20, max: 40),
            comeup: nil,
            peak: DurationRange(min: 90, max: 90),
            offset: nil,
            afterglow: nil,
            total: nil,
        )
        let consequence = try #require(MedTimeConsequence.resolve(substance: stimulant(duration: flat), route: .oral))
        #expect(!consequence.statesWearOff)
    }
}
