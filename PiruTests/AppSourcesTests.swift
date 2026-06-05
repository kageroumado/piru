import Testing
@testable import Piru

@Suite("AppSources")
struct AppSourcesTests {
    @Test
    func `Has expected number of sources`() {
        #expect(AppSources.all.count == 10)
    }

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
}
