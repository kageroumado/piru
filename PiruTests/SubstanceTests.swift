import Testing
@testable import Piru

@Suite("Substance")
struct SubstanceTests {

    let oralRoute = SubstanceRoute(
        route: .oral,
        unit: "mg",
        doses: DoseRange(threshold: 5, light: 10...20, common: 20...40, strong: 40...80, heavy: 80),
        duration: DurationProfile(
            onset: DurationRange(min: 15, max: 30),
            comeup: DurationRange(min: 15, max: 30),
            peak: DurationRange(min: 60, max: 120),
            offset: DurationRange(min: 30, max: 60),
            afterglow: nil,
            total: nil
        )
    )

    let nasalRoute = SubstanceRoute(
        route: .insufflation,
        unit: "mg",
        doses: DoseRange(threshold: 3, light: 5...15, common: 15...30, strong: 30...60, heavy: 60),
        duration: DurationProfile(
            onset: DurationRange(min: 5, max: 10),
            comeup: DurationRange(min: 5, max: 10),
            peak: DurationRange(min: 30, max: 60),
            offset: DurationRange(min: 15, max: 30),
            afterglow: nil,
            total: nil
        )
    )

    var substance: Substance {
        Substance(
            name: "TestSubstance",
            aliases: ["TS", "Test Drug"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [oralRoute, nasalRoute],
            effects: ["Stimulation", "Euphoria"]
        )
    }

    // MARK: - matches()

    @Test("Matches by name case-insensitive")
    func matchesByName() {
        #expect(substance.matches("testsubstance"))
        #expect(substance.matches("TestSubstance"))
        #expect(substance.matches("TESTSUBSTANCE"))
    }

    @Test("Matches partial name")
    func matchesPartialName() {
        #expect(substance.matches("test"))
        #expect(substance.matches("Substance"))
    }

    @Test("Matches by alias")
    func matchesByAlias() {
        #expect(substance.matches("TS"))
        #expect(substance.matches("ts"))
        #expect(substance.matches("Test Drug"))
    }

    @Test("Matches partial alias")
    func matchesPartialAlias() {
        #expect(substance.matches("Test D"))
    }

    @Test("Does not match unrelated query")
    func noMatch() {
        #expect(!substance.matches("Aspirin"))
        #expect(!substance.matches("xyz"))
    }

    @Test("Empty query does not match")
    func emptyQueryDoesNotMatch() {
        #expect(!substance.matches(""))
    }

    // MARK: - doseRange(for:)

    @Test("Returns dose range for matching route")
    func doseRangeMatch() {
        let range = substance.doseRange(for: .oral)
        #expect(range != nil)
        #expect(range?.threshold == 5)
    }

    @Test("Returns nil for non-existent route")
    func doseRangeNoMatch() {
        #expect(substance.doseRange(for: .intravenous) == nil)
    }

    // MARK: - unit(for:)

    @Test("Returns unit for matching route")
    func unitMatch() {
        #expect(substance.unit(for: .oral) == "mg")
    }

    @Test("Falls back to defaultUnit for unknown route")
    func unitFallback() {
        #expect(substance.unit(for: .intravenous) == "mg")
    }

    // MARK: - duration(for:)

    @Test("Returns duration for matching route")
    func durationMatch() {
        let dur = substance.duration(for: .oral)
        #expect(dur != nil)
        #expect(dur?.onset?.midpoint == 22.5)
    }

    @Test("Returns nil duration for non-existent route")
    func durationNoMatch() {
        #expect(substance.duration(for: .intravenous) == nil)
    }

    // MARK: - defaultUnit

    @Test("Default unit from default route")
    func defaultUnitFromDefaultRoute() {
        #expect(substance.defaultUnit == "mg")
    }

    @Test("Default unit falls back to first route")
    func defaultUnitFallsBackToFirstRoute() {
        let s = Substance(
            name: "Test",
            aliases: [],
            category: .stimulant,
            defaultRoute: .intravenous, // not in routes
            routes: [SubstanceRoute(
                route: .oral,
                unit: "ug",
                doses: DoseRange(threshold: nil, light: nil, common: nil, strong: nil, heavy: nil)
            )],
            effects: []
        )
        #expect(s.defaultUnit == "ug")
    }

    @Test("Default unit falls back to mg when no routes")
    func defaultUnitFallsBackToMg() {
        let s = Substance(
            name: "Test",
            aliases: [],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [],
            effects: []
        )
        #expect(s.defaultUnit == "mg")
    }
}
