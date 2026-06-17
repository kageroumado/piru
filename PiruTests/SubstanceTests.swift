import Foundation
import Testing
@testable import Piru

@Suite("Substance")
struct SubstanceTests {
    let oralRoute = SubstanceRoute(
        route: .oral,
        unit: "mg",
        doses: DoseRange(threshold: 5, light: 10 ... 20, common: 20 ... 40, strong: 40 ... 80, heavy: 80),
        duration: DurationProfile(
            onset: DurationRange(min: 15, max: 30),
            comeup: DurationRange(min: 15, max: 30),
            peak: DurationRange(min: 60, max: 120),
            offset: DurationRange(min: 30, max: 60),
            afterglow: nil,
            total: nil,
        ),
    )

    let nasalRoute = SubstanceRoute(
        route: .insufflation,
        unit: "mg",
        doses: DoseRange(threshold: 3, light: 5 ... 15, common: 15 ... 30, strong: 30 ... 60, heavy: 60),
        duration: DurationProfile(
            onset: DurationRange(min: 5, max: 10),
            comeup: DurationRange(min: 5, max: 10),
            peak: DurationRange(min: 30, max: 60),
            offset: DurationRange(min: 15, max: 30),
            afterglow: nil,
            total: nil,
        ),
    )

    var substance: Substance {
        Substance(
            name: "TestSubstance",
            aliases: ["TS", "Test Drug"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [oralRoute, nasalRoute],
            effects: ["Stimulation", "Euphoria"],
        )
    }

    // MARK: - matches()

    @Test
    func `Matches by name case-insensitive`() {
        #expect(substance.matches("testsubstance"))
        #expect(substance.matches("TestSubstance"))
        #expect(substance.matches("TESTSUBSTANCE"))
    }

    @Test
    func `Matches partial name`() {
        #expect(substance.matches("test"))
        #expect(substance.matches("Substance"))
    }

    @Test
    func `Matches by alias`() {
        #expect(substance.matches("TS"))
        #expect(substance.matches("ts"))
        #expect(substance.matches("Test Drug"))
    }

    @Test
    func `Matches partial alias`() {
        #expect(substance.matches("Test D"))
    }

    @Test
    func `Does not match unrelated query`() {
        #expect(!substance.matches("Aspirin"))
        #expect(!substance.matches("xyz"))
    }

    @Test
    func `Empty query does not match`() {
        #expect(!substance.matches(""))
    }

    @Test
    func `Display aliases put Chinese names last in a non-Chinese UI`() {
        // Tests run in an English host, so CJK aliases (FreeOD street names)
        // should sort after the Latin ones regardless of source order.
        let s = Substance(
            name: "MDMA",
            aliases: ["摇头丸", "Molly", "莫莉", "Ecstasy"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [],
            effects: [],
        )
        let shown = s.displayAliases
        let firstHanIndex = shown.firstIndex(where: \.containsHan)
        let lastLatinIndex = shown.lastIndex(where: { !$0.containsHan })
        if let firstHanIndex, let lastLatinIndex {
            #expect(firstHanIndex > lastLatinIndex)
        }
        #expect(shown.contains("Molly"))
        #expect(shown.contains("莫莉"))
    }

    // MARK: - doseRange(for:)

    @Test
    func `Returns dose range for matching route`() {
        let range = substance.doseRange(for: .oral)
        #expect(range != nil)
        #expect(range?.threshold == 5)
    }

    @Test
    func `Returns nil for non-existent route`() {
        #expect(substance.doseRange(for: .intravenous) == nil)
    }

    // MARK: - unit(for:)

    @Test
    func `Returns unit for matching route`() {
        #expect(substance.unit(for: .oral) == "mg")
    }

    @Test
    func `Falls back to defaultUnit for unknown route`() {
        #expect(substance.unit(for: .intravenous) == "mg")
    }

    // MARK: - duration(for:)

    @Test
    func `Returns duration for matching route`() {
        let dur = substance.duration(for: .oral)
        #expect(dur != nil)
        #expect(dur?.onset?.midpoint == 22.5)
    }

    @Test
    func `Returns nil duration for non-existent route`() {
        #expect(substance.duration(for: .intravenous) == nil)
    }

    // MARK: - defaultUnit

    @Test
    func `Default unit from default route`() {
        #expect(substance.defaultUnit == "mg")
    }

    @Test
    func `Default unit falls back to first route`() {
        let s = Substance(
            name: "Test",
            aliases: [],
            category: .stimulant,
            defaultRoute: .intravenous, // not in routes
            routes: [SubstanceRoute(
                route: .oral,
                unit: "ug",
                doses: DoseRange(threshold: nil, light: nil, common: nil, strong: nil, heavy: nil),
            )],
            effects: [],
        )
        #expect(s.defaultUnit == "ug")
    }

    @Test
    func `Default unit falls back to mg when no routes`() {
        let s = Substance(
            name: "Test",
            aliases: [],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [],
            effects: [],
        )
        #expect(s.defaultUnit == "mg")
    }
}

@Suite("Citation")
struct CitationTests {
    @Test
    func `DOI resolves to doi.org`() {
        let c = Citation(doi: "10.1234/abc")
        #expect(c.resolvedURL?.absoluteString == "https://doi.org/10.1234/abc")
        #expect(c.label == "DOI 10.1234/abc")
    }

    @Test
    func `PMID resolves to PubMed`() {
        let c = Citation(pmid: 40_992_254)
        #expect(c.resolvedURL?.absoluteString == "https://pubmed.ncbi.nlm.nih.gov/40992254/")
        #expect(c.label == "PMID 40992254")
    }

    @Test
    func `HTTP url resolves and is its own label`() {
        let c = Citation(url: "https://en.wikipedia.org/wiki/Pynazolam")
        #expect(c.resolvedURL != nil)
        #expect(c.label == "https://en.wikipedia.org/wiki/Pynazolam")
    }

    @Test
    func `Free-text reference is not a link, shows as its label`() {
        // "PubChem CID 20368157" lives in the url slot but isn't a web URL.
        let c = Citation(url: "PubChem CID 20368157")
        #expect(c.resolvedURL == nil)
        #expect(c.label == "PubChem CID 20368157")
    }

    @Test
    func `Title wins the label`() {
        let c = Citation(url: "Egrifta SmPC", title: "Egrifta SmPC")
        #expect(c.label == "Egrifta SmPC")
        #expect(c.resolvedURL == nil)
    }
}
