import Foundation
import Testing
@testable import Piru

/// The distress phrases that raise the crisis panel in search and quick log.
@Suite("Crisis keywords")
struct CrisisKeywordsTests {
    @Test
    func `A phrase matches with the curly apostrophe iOS types by default`() {
        #expect(CrisisKeywords.matches("can't breathe"))
        #expect(CrisisKeywords.matches("can\u{2019}t breathe"))
        #expect(CrisisKeywords.matches("I can\u{2019}t breathe"))
    }
}
