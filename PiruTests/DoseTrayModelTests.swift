import Foundation
import Testing
@testable import Piru

@MainActor
@Suite("DoseTrayModel staging")
struct DoseTrayModelTests {
    private func stage(_ tray: DoseTrayModel, _ name: String, amount: Double, route: RouteOfAdministration = .oral, unit: String = "mg") {
        tray.stage(substance: name, route: route, amount: amount, unit: unit, tint: nil, librarySubstance: nil)
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

    @Test
    func `The tray row prints an estimate as ~ or with its deviation`() {
        let tray = DoseTrayModel()
        stage(tray, "Ketamine", amount: 10)
        #expect(tray.staged[0].amountLabel == "10 mg")

        tray.staged[0].isApproximate = true
        #expect(tray.staged[0].amountLabel == "~10 mg")

        tray.staged[0].amountDeviation = 1.5
        #expect(tray.staged[0].amountLabel == "10 ± 1.5 mg")

        // Clearing the amount field outranks the estimate: there is no number.
        tray.staged[0].isUnknownAmount = true
        #expect(tray.staged[0].amountLabel == "? mg")
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

    /// The sliders pill: one staging event, the draft expanded and asking for
    /// the amount field. Both facts land in the same mutation, which is what
    /// the dock's detent policy resolves to a single move to `.medium`.
    @Test
    func `stageDraft opens the draft for editing in one staging event`() {
        let tray = DoseTrayModel()
        let tickBefore = tray.stageTick
        tray.stageDraft(substance: "Caffeine", route: .oral, unit: "mg", tint: nil, librarySubstance: nil)

        #expect(tray.staged.count == 1)
        #expect(tray.stageTick == tickBefore + 1)
        #expect(!tray.isEmpty)
        let draft = tray.staged[0]
        #expect(tray.expandedItemIDs == [draft.id])
        #expect(draft.wantsAmountFocus)
    }

    /// A second draft for the same substance re-opens the existing row — no
    /// duplicate, no staging event, still asking for focus.
    @Test
    func `stageDraft for a staged substance re-opens its row`() {
        let tray = DoseTrayModel()
        stage(tray, "Caffeine", amount: 100)
        let row = tray.staged[0]
        tray.expandedItemIDs.removeAll()
        let tickBefore = tray.stageTick

        tray.stageDraft(substance: "Caffeine", route: .oral, unit: "mg", tint: nil, librarySubstance: nil)

        #expect(tray.staged.count == 1)
        #expect(tray.stageTick == tickBefore)
        #expect(tray.expandedItemIDs == [row.id])
        #expect(tray.staged[0].wantsAmountFocus)
    }

    /// A card's Custom chip opens its draft at the dock's half height: expanded,
    /// but not asking for the keyboard that would push the sheet to full height.
    @Test
    func `A Custom-chip draft opens without asking for the amount field`() {
        let tray = DoseTrayModel()
        tray.stageDraft(substance: "Caffeine", route: .oral, unit: "mg", tint: nil, librarySubstance: nil, focusesAmount: false)
        let draft = tray.staged[0]
        #expect(tray.expandedItemIDs == [draft.id])
        #expect(!draft.wantsAmountFocus)

        tray.expandedItemIDs.removeAll()
        tray.stageDraft(substance: "Caffeine", route: .oral, unit: "mg", tint: nil, librarySubstance: nil, focusesAmount: false)
        #expect(tray.expandedItemIDs == [draft.id])
        #expect(!tray.staged[0].wantsAmountFocus)
    }

    /// Two different substances are two rows, each visible to the card snapshot —
    /// the "Log 2 Doses" button counts rows, and every counted row needs a card.
    @Test
    func `staging a second substance adds a second row`() {
        let tray = DoseTrayModel()
        stage(tray, "Kratom", amount: 3, unit: "g")
        stage(tray, "Amphetamine", amount: 10)

        #expect(tray.staged.map(\.substanceName) == ["Kratom", "Amphetamine"])
        #expect(tray.staged.allSatisfy { $0.totalAmount > 0 })
        #expect(tray.isCommittable)

        let snapshot = tray.stagedCountsBySubstance()
        #expect((snapshot["kratom"] ?? .empty).count(route: .oral, amount: 3, unit: "g") == 1)
        #expect((snapshot["amphetamine"] ?? .empty).count(route: .oral, amount: 10, unit: "mg") == 1)
    }

    /// The doubling bug: staging a Concerta (canonical Methylphenidate, release
    /// `XR`) onto an already-staged plain Methylphenidate matched by name alone and
    /// summed the two into one row — you couldn't log IR + Concerta together, and
    /// the merged dose read as double. They are different forms and must stay
    /// separate staged rows, each with its own amount.
    @Test
    func `Concerta does not merge into plain methylphenidate`() {
        let tray = DoseTrayModel()
        let mph = SubstanceLibrary.lookup("methylphenidate")
        #expect(mph != nil)
        tray.stage(substance: "Methylphenidate", route: .oral, amount: 10, unit: "mg", tint: nil, librarySubstance: mph)
        tray.stage(substance: "Methylphenidate", route: .oral, amount: 10, unit: "mg", tint: nil, librarySubstance: mph, productName: "Concerta")
        #expect(tray.staged.count == 2, "IR-unspecified and XR are different forms — two rows")
        #expect(tray.staged.allSatisfy { $0.totalAmount == 10 }, "neither row is doubled")
    }

    /// The other side of the same key: two logs of the *same* product still merge,
    /// so re-tapping Concerta bumps its count rather than spawning a second row.
    @Test
    func `Same product re-stages into one row`() {
        let tray = DoseTrayModel()
        let mph = SubstanceLibrary.lookup("methylphenidate")
        tray.stage(substance: "Methylphenidate", route: .oral, amount: 18, unit: "mg", tint: nil, librarySubstance: mph, productName: "Concerta")
        tray.stage(substance: "Methylphenidate", route: .oral, amount: 18, unit: "mg", tint: nil, librarySubstance: mph, productName: "Concerta")
        #expect(tray.staged.count == 1)
        #expect(tray.staged[0].components.first?.count == 2)
    }

    // MARK: Combinations

    private var coCodamol: CustomSubstanceEntry {
        CustomSubstanceEntry(
            name: "Co-codamol", unit: "tablet",
            components: [
                CombinationComponent(substance: "Paracetamol", amountPerUnit: 500, unit: "mg", route: .oral),
                CombinationComponent(substance: "Codeine", amountPerUnit: 30, unit: "mg", route: .oral),
            ],
        )
    }

    /// One tablet is one row per component, each labeled with the product.
    @Test
    func `Staging a combination stages one row per component`() {
        let tray = DoseTrayModel()
        tray.stage(combination: coCodamol)

        #expect(tray.staged.count == 2)
        #expect(tray.staged.map(\.totalAmount) == [500, 30])
        #expect(tray.staged.map(\.unit) == ["mg", "mg"])
        #expect(tray.staged.allSatisfy { $0.route == .oral })
        #expect(tray.staged.allSatisfy { $0.combinationName == "Co-codamol" })
        #expect(tray.isCommittable)
    }

    /// Picking the product again is a second tablet: every row doubles, no
    /// row is added.
    @Test
    func `Staging a combination twice doubles every row`() {
        let tray = DoseTrayModel()
        tray.stage(combination: coCodamol)
        tray.stage(combination: coCodamol)

        #expect(tray.staged.count == 2)
        #expect(tray.staged.map(\.totalAmount) == [1000, 60])
        #expect(tray.staged.allSatisfy { $0.components.count == 1 && $0.components[0].count == 2 })
    }

    /// `quantity` is the same as that many picks.
    @Test
    func `A quantity stages that many units at once`() {
        let tray = DoseTrayModel()
        tray.stage(combination: coCodamol, quantity: 3)

        #expect(tray.staged.map(\.totalAmount) == [1500, 90])
        #expect(tray.staged[0].breakdownLabel == "3 × 500")
    }

    /// A component the library doesn't know stages under its raw name, as a
    /// custom substance does, rather than being dropped from the tablet.
    @Test
    func `An unknown component stages by its raw name`() {
        let tray = DoseTrayModel()
        let entry = CustomSubstanceEntry(
            name: "Mystery blend", unit: "capsule",
            components: [CombinationComponent(substance: "ZZNoSuchCompound", amountPerUnit: 10, unit: "mg", route: .sublingual)],
        )
        tray.stage(combination: entry)

        #expect(tray.staged.count == 1)
        #expect(tray.staged[0].substanceName == "ZZNoSuchCompound")
        #expect(tray.staged[0].librarySubstance == nil)
        #expect(tray.staged[0].route == .sublingual)
        #expect(tray.staged[0].combinationName == "Mystery blend")
    }

    /// A zero quantity stages nothing, and a combination with no components
    /// stages nothing — neither leaves an empty row behind.
    @Test
    func `Nothing to stage leaves the tray empty`() {
        let tray = DoseTrayModel()
        tray.stage(combination: coCodamol, quantity: 0)
        tray.stage(combination: CustomSubstanceEntry(name: "Empty"))
        #expect(tray.isEmpty)
    }
}
