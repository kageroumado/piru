import Testing
@testable import Piru

@Suite("AppSources")
struct AppSourcesTests {
    @Test
    func `All sources have name and description`() {
        for source in AppSources.all {
            #expect(!source.name.isEmpty, "\(source.name) should have a name")
            #expect(!source.description.isEmpty, "\(source.name) should have a description")
            #expect(!source.detail.isEmpty, "\(source.name) should have a detail")
        }
    }

    @Test
    func `Lookup by name returns correct source`() {
        let tripSit = AppSources.info(for: "TripSit")
        #expect(tripSit != nil)
        #expect(tripSit?.url == "https://tripsit.me")
    }

    @Test
    func `Lookup OpenFDA`() {
        let fda = AppSources.info(for: "OpenFDA")
        #expect(fda != nil)
        #expect(fda?.url == "https://open.fda.gov")
    }

    @Test
    func `Lookup unknown returns nil`() {
        #expect(AppSources.info(for: "NotASource") == nil)
    }

    @Test
    func `All expected sources are present`() {
        let names = Set(AppSources.all.map(\.name))
        #expect(names.contains("TripSit"))
        #expect(names.contains("OpenFDA"))
        #expect(names.contains("PsychonautWiki"))
        #expect(names.contains("DrugBank"))
        #expect(names.contains("PubMed"))
    }

    @Test
    func `Source names are unique`() {
        let names = AppSources.all.map(\.name)
        #expect(Set(names).count == names.count)
    }

    @Test
    func `Every slug the DB attributes maps to a named source`() {
        // `license(forSlug:)` and the Sources list both go through this map, so
        // a bundled slug missing from it shows an unlicensed, unnamed row.
        for slug in ["dosewiki", "freeodwiki", "psychonautwiki", "tripsit"] {
            let name = try? #require(AppSources.slugToName[slug])
            #expect(name != nil, "\(slug) has no display name")
            #expect(AppSources.info(for: name ?? "") != nil, "\(slug) names no source")
        }
    }

    @Test
    func `dose.wiki declares the license it ships under`() {
        let dosewiki = AppSources.info(for: "dose.wiki")
        #expect(dosewiki?.url == "https://dose.wiki")
        #expect(dosewiki?.license == "CC0 1.0")
    }

    @Test
    func `A dose.wiki link needs the captured slug`() {
        // Never the site root: a row labelled with a substance that opens a
        // homepage reads as a working link and hides the missing slug.
        #expect(AppSources.dosewikiURL(slug: nil) == nil)
        #expect(AppSources.dosewikiURL(slug: "") == nil)
        #expect(
            AppSources.dosewikiURL(slug: "4-meo-butyrfentanyl")?.absoluteString
                == "https://dose.wiki/4-meo-butyrfentanyl",
        )
    }
}
