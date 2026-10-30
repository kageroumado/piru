import Foundation
import Testing
@testable import Piru

/// The Get Help numbers people dial in a crisis.
@Suite("Emergency services")
@MainActor
struct EmergencyServicesTests {
    @Test
    func `The Netherlands lists 113's free line, never the paid 0900 number`() {
        // 113.nl: "Het gratis nummer is 0800-0113." The 0900 number is not
        // on the site.
        let urls = HelpView.services(for: "NL").map(\.url)
        #expect(urls.contains("tel:08000113"))
        #expect(!urls.contains { $0.hasPrefix("tel:0900") })
    }
}
