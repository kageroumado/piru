import Foundation
import Testing
@testable import Piru

@MainActor
@Suite("DoseTrayModel staging")
struct DoseTrayModelTests {
    private func stage(_ tray: DoseTrayModel, _ name: String, amount: Double, route: RouteOfAdministration = .oral, unit: String = "mg") {
        tray.stage(substance: name, route: route, amount: amount, unit: unit, colorHex: nil, librarySubstance: nil)
    }

    @Test
    func `isEmpty tracks add and remove`() {
        let tray = DoseTrayModel()
        #expect(tray.isEmpty)
        #expect(!tray.isCommittable)

        stage(tray, "Caffeine", amount: 100)
        #expect(!tray.isEmpty)
        #expect(tray.isCommittable)

        let item = tray.staged[0]
        tray.remove(item)
        #expect(tray.isEmpty)
        #expect(!tray.isCommittable)
    }

    /// The crux of the perf fix: editing a staged dose's *amount* (stepping it up
    /// or down) must not flip `isEmpty` — it's the stored flag staying put through
    /// in-place edits that keeps `QuickLogView.body` from re-running per step.
    @Test
    func `editing an amount leaves isEmpty unchanged`() {
        let tray = DoseTrayModel()
        stage(tray, "Caffeine", amount: 100)
        #expect(!tray.isEmpty)

        tray.staged[0].amount = 250
        #expect(!tray.isEmpty)
        #expect(tray.staged[0].totalAmount == 250)

        // Zeroing the amount keeps the row staged (still non-empty) but makes the
        // tray non-committable until it's a real dose again.
        tray.staged[0].amount = 0
        #expect(!tray.isEmpty)
        #expect(!tray.isCommittable)
    }

    @Test
    func `re-staging the same chip increments its count, not the row count`() {
        let tray = DoseTrayModel()
        stage(tray, "Caffeine", amount: 100)
        stage(tray, "Caffeine", amount: 100)
        #expect(tray.staged.count == 1)
        #expect(tray.quantity(substance: "Caffeine", route: .oral, amount: 100, unit: "mg") == 2)
    }

    /// The `Fix #1` value snapshot must match `quantity` exactly — same chip keys,
    /// bucketed by substance — so cards reflect staged state without reading the
    /// live tray.
    @Test
    func `stagedCountsBySubstance matches quantity`() {
        let tray = DoseTrayModel()
        stage(tray, "Caffeine", amount: 100)
        stage(tray, "Caffeine", amount: 100)
        stage(tray, "Caffeine", amount: 50)
        stage(tray, "Melatonin", amount: 1)

        let snapshot = tray.stagedCountsBySubstance()
        let caffeine = snapshot["caffeine"] ?? .empty
        #expect(caffeine.count(route: .oral, amount: 100, unit: "mg") == 2)
        #expect(caffeine.count(route: .oral, amount: 50, unit: "mg") == 1)
        #expect(caffeine.count(route: .oral, amount: 999, unit: "mg") == 0)

        let melatonin = snapshot["melatonin"] ?? .empty
        #expect(melatonin.count(route: .oral, amount: 1, unit: "mg") == 1)

        // An unstaged substance has no slice.
        #expect((snapshot["aspirin"] ?? .empty) == .empty)
    }
}
