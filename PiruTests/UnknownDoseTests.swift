import Foundation
import Testing
@testable import Piru

/// A dose of unknown amount is a record — substance, route, time — with no
/// number. Every numeric engine leaves it out; the surfaces that stage and edit
/// it accept it without one.
@Suite("Unknown dose")
@MainActor
struct UnknownDoseTests {
    static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func unknown(_ substance: String, unit: String = "mg", route: RouteOfAdministration = .oral, at timestamp: Date = now) -> DoseEntry {
        DoseEntry(substance: substance, amount: 0, unit: unit, route: route, timestamp: timestamp, isUnknownDose: true)
    }

    // MARK: - Curves and body load

    @Test
    func `An unknown dose draws no effect curve`() {
        let state = ActiveSubstanceState.from(entry: unknown("Caffeine"), colorHex: "#FF0000")
        #expect(state == nil)
        // The control: the same dose with a number draws.
        let known = DoseEntry(substance: "Caffeine", amount: 100, unit: "mg", route: .oral, timestamp: Self.now)
        #expect(ActiveSubstanceState.from(entry: known, colorHex: "#FF0000") != nil)
    }

    @Test
    func `An unknown dose lands as a timestamp marker, not a curve`() {
        let (states, markers) = ActiveSubstanceState.timeline(for: [unknown("Caffeine")], colors: [])
        #expect(states.isEmpty)
        #expect(markers.count == 1)
    }

    @Test
    func `An unknown dose contributes no body load and does not suppress its neighbors`() {
        let doses = [
            unknown("Caffeine", at: Date.now.addingTimeInterval(-600)),
            DoseEntry(substance: "Caffeine", amount: 100, unit: "mg", route: .oral, timestamp: Date.now.addingTimeInterval(-900)),
        ]
        let active = ActiveSubstanceCalculator.compute(from: doses, colorMap: [:])
        let caffeine = try? #require(active.first)
        #expect(active.count == 1)
        #expect(caffeine?.doses.count == 1)
        #expect(caffeine?.totalDosed == 100)
        #expect(ActiveSubstanceCalculator.compute(from: [doses[0]], colorMap: [:]).isEmpty)
    }

    // MARK: - Tolerance

    @Test
    func `The tolerance replay ignores an unknown dose`() {
        let resolve: (String) -> PharmacologyParameters? = { SubstanceStore.shared.pharmacologyParameters(forSubstanceName: $0) }
        let onlyUnknown = (0 ..< 10).map { day in
            unknown("Caffeine", at: Self.now.addingTimeInterval(-Double(day) * 86_400 - 24 * 3_600))
        }
        #expect(ToleranceStore.simulate(entries: onlyUnknown, now: Self.now, weightKg: 70, resolve: resolve).isEmpty)

        let known = (0 ..< 10).map { day in
            DoseEntry(substance: "Caffeine", amount: 200, unit: "mg", route: .oral, timestamp: Self.now.addingTimeInterval(-Double(day) * 86_400 - 24 * 3_600))
        }
        let alone = ToleranceStore.simulate(entries: known, now: Self.now, weightKg: 70, resolve: resolve)
        let mixed = ToleranceStore.simulate(entries: known + onlyUnknown, now: Self.now, weightKg: 70, resolve: resolve)
        #expect(alone[.adenosine]?.shiftFactor == mixed[.adenosine]?.shiftFactor)
    }

    // MARK: - Row facts

    @Test
    func `A journal row for an unknown dose carries the flag and no tier`() {
        let core = try? #require(DayEntryCore.make(from: [unknown("Caffeine")]).first)
        #expect(core?.isUnknownDose == true)
        #expect(core?.doseLevel == nil)
        #expect(core?.totalMinutes == nil)
    }

    // MARK: - Staging

    @Test
    func `A staged dose declared unknown commits without an amount`() {
        let tray = DoseTrayModel()
        tray.stageDraft(substance: "Cocaine", route: .insufflation, unit: "mg", colorHex: nil, librarySubstance: nil)
        tray.staged[0].amount = 0
        #expect(!tray.isCommittable)

        tray.staged[0].isUnknownAmount = true
        #expect(tray.isCommittable)
        #expect(tray.staged[0].breakdownLabel == nil)
        #expect(tray.staged[0].doseLevel == nil)
    }

    @Test
    func `Declaring a staged amount unknown keeps its components for toggling back`() {
        var dose = StagedDose(substanceName: "Caffeine", amount: 100, unit: "mg", route: .oral)
        dose.isUnknownAmount = true
        #expect(dose.totalAmount == 100)
        dose.isUnknownAmount = false
        #expect(dose.totalAmount == 100)
    }

    // MARK: - Editing

    @Test
    func `An edit draft may commit an unknown dose without a parseable amount`() {
        let draft = EntryDraft()
        draft.amount = ""
        #expect(!draft.canCommit)
        draft.isUnknownDose = true
        #expect(draft.canCommit)
    }

    @Test
    func `An edit draft seeded from an unknown dose opens with the flag set and no amount text`() {
        let draft = EntryDraft()
        draft.begin(from: unknown("Cocaine", route: .insufflation), hasByVolumeCapability: false)
        #expect(draft.isUnknownDose)
        #expect(draft.amount.isEmpty)
        #expect(draft.route == .insufflation)
        #expect(draft.canCommit)
    }
}
