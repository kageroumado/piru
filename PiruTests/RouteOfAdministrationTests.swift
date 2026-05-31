import Foundation
import Testing
@testable import Piru

@Suite("RouteOfAdministration")
struct RouteOfAdministrationTests {
    // MARK: - Display names

    @Test(arguments: [
        (RouteOfAdministration.oral, "Oral"),
        (.sublingual, "Sublingual"),
        (.insufflation, "Insufflation"),
        (.inhalation, "Inhalation"),
        (.intravenous, "Intravenous"),
        (.intramuscular, "Intramuscular"),
        (.subcutaneous, "Subcutaneous"),
        (.transdermal, "Transdermal"),
        (.rectal, "Rectal"),
        (.other, "Other"),
    ])
    func `All display names are correct`(route: RouteOfAdministration, expected: String) {
        #expect(route.displayName == expected)
    }

    // MARK: - Identifiable

    @Test(arguments: RouteOfAdministration.allCases)
    func `ID returns rawValue`(route: RouteOfAdministration) {
        #expect(route.id == route.rawValue)
    }

    // MARK: - CaseIterable

    @Test
    func `Has exactly 10 cases`() {
        #expect(RouteOfAdministration.allCases.count == 10)
    }

    // MARK: - Codable

    @Test(arguments: RouteOfAdministration.allCases)
    func `Encodes and decodes correctly`(route: RouteOfAdministration) throws {
        let data = try JSONEncoder().encode(route)
        let decoded = try JSONDecoder().decode(RouteOfAdministration.self, from: data)
        #expect(decoded == route)
    }
}
