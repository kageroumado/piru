import Foundation
import Testing
@testable import Piru

/// ``StagedDose/makeEntry(timestamp:tags:meal:location:)``, the one mapping
/// from a staged dose to a journal entry, called with the context each of its
/// two callers has: the tray's Log button (tray-wide tags, meal, location) and
/// the Log Dose shortcut (tags and meal from the request).
@MainActor
@Suite("Staged dose to entry")
struct StagedDoseEntryTests {
    private let time = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func staged(
        _ name: String = "Caffeine", amount: Double = 100, unit: String = "mg", route: RouteOfAdministration = .oral,
    ) -> StagedDose {
        StagedDose(substanceName: name, amount: amount, unit: unit, route: route)
    }

    @Test
    func `A tray-shaped call carries every tray-wide value and per-dose flag`() {
        var dose = staged()
        dose.components.append(.init(amount: 50, count: 2))
        dose.note = "with breakfast"
        dose.isBackgroundMed = true
        dose.hadGrapefruit = true
        dose.combinationName = "Morning stack"
        let location = PickedLocation(name: "Home", latitude: 48.85, longitude: 2.35)

        let entry = dose.makeEntry(timestamp: time, tags: ["work", "focus"], meal: .light, location: location)

        #expect(entry.substance == "Caffeine")
        #expect(entry.amount == 200)
        #expect(entry.unit == "mg")
        #expect(entry.route == .oral)
        #expect(entry.timestamp == time)
        #expect(entry.notes == "with breakfast")
        #expect(entry.tags == ["work", "focus"])
        #expect(entry.isBackgroundMed)
        #expect(entry.hadGrapefruit == true)
        #expect(entry.meal == .light)
        #expect(entry.locationName == "Home")
        #expect(entry.latitude == 48.85)
        #expect(entry.longitude == 2.35)
        #expect(entry.combinationName == "Morning stack")
        #expect(!entry.isUnknownDose)
    }

    @Test
    func `A Shortcuts-shaped call leaves the tray-only fields empty`() {
        var dose = staged()
        dose.note = ""
        let entry = dose.makeEntry(timestamp: time, tags: [], meal: .full)

        #expect(entry.amount == 100)
        #expect(entry.notes == nil)
        #expect(entry.tags.isEmpty)
        #expect(entry.meal == .full)
        #expect(!entry.isBackgroundMed)
        #expect(entry.hadGrapefruit == nil)
        #expect(entry.locationName == nil)
        #expect(entry.latitude == nil)
        #expect(entry.longitude == nil)
        #expect(entry.injectionSite == nil)
        #expect(entry.drinkName == nil)
    }

    @Test
    func `Tags are trimmed and blank ones dropped`() {
        let entry = staged().makeEntry(timestamp: time, tags: [" party ", "", "   ", "night"])
        #expect(entry.tagsRaw == "party,night")
    }

    @Test
    func `A meal lands on oral doses only`() {
        let oral = staged(route: .oral).makeEntry(timestamp: time, meal: .full)
        let insufflated = staged(route: .insufflation).makeEntry(timestamp: time, meal: .full)
        #expect(oral.meal == .full)
        #expect(insufflated.meal == nil)
    }

    @Test
    func `A staged drink keeps its volume, strength and name`() {
        var dose = staged("Alcohol", amount: 16, unit: "g")
        dose.volumeML = 330
        dose.abv = 6
        dose.drinkName = "IPA"
        let entry = dose.makeEntry(timestamp: time)
        #expect(entry.volumeML == 330)
        #expect(entry.abv == 6)
        #expect(entry.drinkName == "IPA")
    }

    @Test
    func `An unknown amount commits as unknown with no by-volume detail`() {
        var dose = staged("Morphine", amount: 0.5, unit: "g")
        dose.combinationName = "Oral solution"
        dose.volumeML = 0.25
        dose.abv = 2
        dose.drinkName = "Vial"
        dose.isUnknownAmount = true
        #expect(dose.isLiquidCombinationRow)

        let entry = dose.makeEntry(timestamp: time)

        #expect(entry.isUnknownDose)
        #expect(entry.amount == 0)
        #expect(entry.volumeML == nil)
        #expect(entry.abv == nil)
        #expect(entry.drinkName == nil)
        #expect(entry.combinationName == "Oral solution")
    }

    @Test
    func `An injection site is kept only on a route that takes one`() {
        let site = InjectionSite(area: .thigh, side: .left)
        var injected = staged("Testosterone", amount: 100, route: .intramuscular)
        injected.injectionSite = site
        var oral = staged()
        oral.injectionSite = site

        #expect(injected.makeEntry(timestamp: time).injectionSite == site)
        #expect(oral.makeEntry(timestamp: time).injectionSite == nil)
    }
}
