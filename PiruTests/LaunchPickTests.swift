import Testing
@testable import Piru

@MainActor
@Suite("Launch pick")
struct LaunchPickTests {
    @Test
    func `A launch gets one pick, however often the root is re-created`() {
        let pick = LaunchPick()
        #expect(!pick.isTaken)
        #expect(pick.claim())
        #expect(pick.isTaken)
        #expect(!pick.claim())
        #expect(!pick.claim())
    }
}
