import Testing
import Foundation
@testable import Piru

@Suite("RouteOfAdministration")
struct RouteOfAdministrationTests {

    // MARK: - Display names

    @Test("All display names are correct", arguments: [
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
    func displayName(route: RouteOfAdministration, expected: String) {
        #expect(route.displayName == expected)
    }

    // MARK: - Identifiable

    @Test("ID returns rawValue", arguments: RouteOfAdministration.allCases)
    func idIsRawValue(route: RouteOfAdministration) {
        #expect(route.id == route.rawValue)
    }

    // MARK: - CaseIterable

    @Test("Has exactly 10 cases")
    func caseCount() {
        #expect(RouteOfAdministration.allCases.count == 10)
    }

    // MARK: - Codable

    @Test("Encodes and decodes correctly", arguments: RouteOfAdministration.allCases)
    func codableRoundTrip(route: RouteOfAdministration) throws {
        let data = try JSONEncoder().encode(route)
        let decoded = try JSONDecoder().decode(RouteOfAdministration.self, from: data)
        #expect(decoded == route)
    }
}
