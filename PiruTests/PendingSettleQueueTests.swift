import Testing
@testable import Piru

/// The dock reveals a freshly staged row only once the sheet has finished
/// growing for it, by queueing the reveal behind the detent move. A second
/// refresh landing mid-move (the commit bar growing for an interaction
/// warning) supersedes the first move — the reveal must ride along to the
/// move that actually lands, or the row stays hidden with "Log 2 Doses"
/// above a one-row tray.
@Suite("PendingSettleQueue")
struct PendingSettleQueueTests {
    @Test
    func `a callback survives its move being superseded`() {
        var queue = PendingSettleQueue()
        var ran: [String] = []

        queue.enqueue { ran.append("reveal") }
        queue.enqueue { ran.append("second move") }
        #expect(ran.isEmpty, "nothing runs until a move lands")

        for callback in queue.drain() {
            callback()
        }
        #expect(ran == ["reveal", "second move"], "both fire, in registration order")
    }

    @Test
    func `draining empties the queue`() {
        var queue = PendingSettleQueue()
        queue.enqueue {}
        #expect(!queue.isEmpty)
        _ = queue.drain()
        #expect(queue.isEmpty)
        #expect(queue.drain().isEmpty)
    }

    @Test
    func `a nil registration is ignored`() {
        var queue = PendingSettleQueue()
        queue.enqueue(nil)
        #expect(queue.isEmpty)
    }
}
