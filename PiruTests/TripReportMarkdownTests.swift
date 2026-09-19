import Foundation
import Testing
@testable import Piru

/// The document a session is shared as: the modeled course to read the notes
/// against, and only the columns the session actually recorded.
@Suite("TripReport markdown")
struct TripReportMarkdownTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let locale = Locale(identifier: "en_US_POSIX")
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func dose(_ name: String, phases: Bool) -> TripReport.Dose {
        TripReport.Dose(
            id: UUID(), timestamp: start, name: name, amount: 10, unit: "mg", route: "Oral",
            phases: phases
                ? TripReport.Phase.reportLabels.enumerated().map { index, label in
                    TripReport.Phase(label: label, at: start.addingTimeInterval(Double(index + 1) * 1_800))
                }
                : [],
        )
    }

    private func note(
        worked: Int? = nil, shulgin: Int? = nil, mood: Int? = nil, social: Int? = nil,
    ) -> TripReport.Note {
        TripReport.Note(
            id: UUID(), timestamp: start.addingTimeInterval(3_600), kind: .checkIn, text: "steady",
            shulgin: shulgin, mood: mood, energy: nil, social: social, worked: worked,
            heartRate: nil, descriptors: [],
        )
    }

    private func report(doses: [TripReport.Dose], notes: [TripReport.Note]) -> TripReport {
        TripReport(title: nil, sessionStart: start, doses: doses, notes: notes, summary: nil)
    }

    @Test
    func `A medication session prints a Worked column and no Shulgin column`() {
        let md = report(doses: [dose("Methylphenidate", phases: true)], notes: [note(worked: 0)])
            .markdown(locale: locale, calendar: calendar)
        #expect(md.contains("| Worked |"))
        #expect(!md.contains("| Shulgin |"))
        #expect(md.contains("about right"))
    }

    @Test
    func `A psychedelic session prints Shulgin and no Worked column`() {
        let md = report(doses: [dose("LSD", phases: true)], notes: [note(shulgin: 2, mood: 2)])
            .markdown(locale: locale, calendar: calendar)
        #expect(md.contains("| Shulgin |"))
        #expect(!md.contains("| Worked |"))
        #expect(md.contains("| Mood / Energy |"))
    }

    @Test
    func `The modeled course is printed when the dose carries phases, and skipped when it does not`() {
        let withPhases = report(doses: [dose("LSD", phases: true)], notes: [note(shulgin: 2)])
            .markdown(locale: locale, calendar: calendar)
        #expect(withPhases.contains("## Modeled course"))
        for label in TripReport.Phase.reportLabels {
            #expect(withPhases.contains(label))
        }

        let without = report(doses: [dose("Kratom", phases: false)], notes: [note(shulgin: 2)])
            .markdown(locale: locale, calendar: calendar)
        #expect(!without.contains("## Modeled course"))
    }

    @Test
    func `A Social column appears only for a session that recorded one`() {
        let with = report(doses: [dose("MDMA", phases: true)], notes: [note(shulgin: 2, social: 3)])
            .markdown(locale: locale, calendar: calendar)
        #expect(with.contains("| Social |"))

        let without = report(doses: [dose("LSD", phases: true)], notes: [note(shulgin: 2)])
            .markdown(locale: locale, calendar: calendar)
        #expect(!without.contains("| Social |"))
    }

    @Test
    func `The structure line carries the medication answer beside the rest`() {
        let line = TripReport.structureLine(
            shulgin: 2, mood: 1, energy: nil, social: 3, worked: -1, heartRate: 84,
        )
        #expect(line == "++ · less than usual · mood +1 · social +3 · ♥ 84")
        #expect(TripReport.structureLine(shulgin: nil, mood: nil, energy: nil, heartRate: nil).isEmpty)
    }
}
