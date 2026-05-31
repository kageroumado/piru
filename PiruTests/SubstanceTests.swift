import Testing
import Foundation
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

@Suite("Citation")
struct CitationTests {
    @Test("DOI resolves to doi.org")
    func doiURL() {
        let c = Citation(doi: "10.1234/abc")
        #expect(c.resolvedURL?.absoluteString == "https://doi.org/10.1234/abc")
        #expect(c.label == "DOI 10.1234/abc")
    }

    @Test("PMID resolves to PubMed")
    func pmidURL() {
        let c = Citation(pmid: 40992254)
        #expect(c.resolvedURL?.absoluteString == "https://pubmed.ncbi.nlm.nih.gov/40992254/")
        #expect(c.label == "PMID 40992254")
    }

    @Test("HTTP url resolves and is its own label")
    func httpURL() {
        let c = Citation(url: "https://en.wikipedia.org/wiki/Pynazolam")
        #expect(c.resolvedURL != nil)
        #expect(c.label == "https://en.wikipedia.org/wiki/Pynazolam")
    }

    @Test("Free-text reference is not a link, shows as its label")
    func freeTextNoLink() {
        // "PubChem CID 20368157" lives in the url slot but isn't a web URL.
        let c = Citation(url: "PubChem CID 20368157")
        #expect(c.resolvedURL == nil)
        #expect(c.label == "PubChem CID 20368157")
    }

    @Test("Title wins the label")
    func titleLabel() {
        let c = Citation(url: "Egrifta SmPC", title: "Egrifta SmPC")
        #expect(c.label == "Egrifta SmPC")
        #expect(c.resolvedURL == nil)
    }
}
