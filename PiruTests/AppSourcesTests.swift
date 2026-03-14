import Testing
@testable import Piru

@Suite("AppSources")
struct AppSourcesTests {

    @Test("Has expected number of sources")
    func sourceCount() {
        #expect(AppSources.all.count == 14)
    }

    @Test("All sources have name and description")
    func allSourcesHaveData() {
        for source in AppSources.all {
            #expect(!source.name.isEmpty, "\(source.name) should have a name")
            #expect(!source.description.isEmpty, "\(source.name) should have a description")
            #expect(!source.detail.isEmpty, "\(source.name) should have a detail")
        }
    }

    @Test("Lookup by name returns correct source")
    func lookupByName() {
        let tripSit = AppSources.info(for: "TripSit")
        #expect(tripSit != nil)
        #expect(tripSit?.url == "https://tripsit.me")
    }

    @Test("Lookup OpenFDA")
    func lookupOpenFDA() {
        let fda = AppSources.info(for: "OpenFDA")
        #expect(fda != nil)
        #expect(fda?.url == "https://open.fda.gov")
    }

    @Test("Lookup unknown returns nil")
    func lookupUnknown() {
        #expect(AppSources.info(for: "NotASource") == nil)
    }

    @Test("All expected sources are present")
    func expectedSourcesPresent() {
        let names = Set(AppSources.all.map(\.name))
        #expect(names.contains("TripSit"))
        #expect(names.contains("OpenFDA"))
        #expect(names.contains("PsychonautWiki"))
        #expect(names.contains("DrugBank"))
        #expect(names.contains("PubMed"))
    }

    @Test("Source names are unique")
    func uniqueNames() {
        let names = AppSources.all.map(\.name)
        #expect(Set(names).count == names.count)
    }
}
