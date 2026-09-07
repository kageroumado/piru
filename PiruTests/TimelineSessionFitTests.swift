import CoreGraphics
import SwiftData
import SwiftUI
import Testing
@testable import Piru

/// ``TimelineStripBuilder/fitRun`` keeps a session envelope inside its day
/// slice: pull the stack up while there is room, hide the rest behind the
/// "+n more" footer.
@Suite("TimelineSessionFit")
struct TimelineSessionFitTests {
    private static let cardHeight: CGFloat = 58

    private func group(doses: Int, topY: CGFloat, timestamp: Date = .now) -> TimelineDayLayout.CardGroup {
        let items = (0 ..< doses).map { i in
            let entry = DoseEntry(substance: "Mephedrone", amount: 100, unit: "mg", route: .oral, timestamp: timestamp.addingTimeInterval(Double(i) * 60))
            return TimelineDayLayout.CardItem(entry: entry, displayName: "Mephedrone", color: .pink, remainingFraction: nil, state: nil)
        }
        var group = TimelineDayLayout.CardGroup(
            id: items[0].entry.persistentModelID,
            items: items,
            representativeTime: timestamp,
            sessionID: UUID(),
            cardHeight: Self.cardHeight,
        )
        group.inSession = true
        group.topY = topY
        return group
    }

    @Test
    func `A run inside the limit is left where its times put it`() {
        var groups = [group(doses: 2, topY: 100), group(doses: 1, topY: 300)]
        let envelope = TimelineStripBuilder.fitRun(&groups, sessionID: UUID(), range: 0 ... 1, floor: 50, limit: 1_000)
        #expect(groups[0].topY == 100)
        #expect(groups[1].topY == 300)
        #expect(envelope.hiddenDoseCount == 0)
        #expect(envelope.yEnd == 358 + TimelineDayLayout.envelopePad + TimelineDayLayout.envelopeFooterHeight)
    }

    @Test
    func `A run past the limit is pulled up only as far as the limit needs`() {
        var groups = [group(doses: 1, topY: 100), group(doses: 3, topY: 500)]
        let envelope = TimelineStripBuilder.fitRun(&groups, sessionID: UUID(), range: 0 ... 1, floor: 50, limit: 600)
        // Three cards: 3 × 58 + 2 × 4 = 182 → the oldest group's top moves to 418.
        #expect(groups[1].topY == 418)
        // The newest group already cleared the pulled-up neighbor and stays put.
        #expect(groups[0].topY == 100)
        #expect(envelope.hiddenDoseCount == 0)
        #expect(groups.allSatisfy { $0.hiddenItemCount == 0 })
        #expect(envelope.yEnd == 600 + TimelineDayLayout.envelopePad + TimelineDayLayout.envelopeFooterHeight)
    }

    @Test
    func `With no room above, the bubbles past the limit go behind the footer`() {
        var groups = [group(doses: 2, topY: 80), group(doses: 3, topY: 300)]
        let envelope = TimelineStripBuilder.fitRun(&groups, sessionID: UUID(), range: 0 ... 1, floor: 80, limit: 150)
        #expect(groups[0].topY == 80)
        // Group 0 spans 80…200; only its first card (bottom 138) fits under 150,
        // and group 1, re-pushed below it, fits nothing.
        #expect(groups[1].topY == 214)
        #expect(groups[0].hiddenItemCount == 1)
        #expect(groups[1].hiddenItemCount == 3)
        #expect(envelope.hiddenDoseCount == 4)
        #expect(envelope.yEnd == 138 + TimelineDayLayout.envelopePad + TimelineDayLayout.envelopeFooterHeight)
        #expect(groups[0].visibleItems.count == 1)
    }

    @Test
    func `The first bubble always shows, even past the limit`() {
        var groups = [group(doses: 2, topY: 100)]
        let envelope = TimelineStripBuilder.fitRun(&groups, sessionID: UUID(), range: 0 ... 0, floor: 100, limit: 90)
        #expect(groups[0].hiddenItemCount == 1)
        #expect(envelope.hiddenDoseCount == 1)
    }
}
