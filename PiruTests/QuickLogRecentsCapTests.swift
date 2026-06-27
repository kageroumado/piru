import Foundation
import Testing
@testable import Piru

/// The quick-log recent (non-favorite) card set is capped — a heavy log can
/// accumulate ~50 curated substances, but rendering all of them is what made
/// `QuickLogView.body` long. Favorites are exempt (explicitly pinned).
@MainActor
@Suite("QuickLogRecentsCap")
struct QuickLogRecentsCapTests {
    private func makeDose(_ substance: String, daysAgo: Double) -> QuickLogDose {
        QuickLogDose(
            substance: substance,
            route: .oral,
            amount: 100,
            unit: "mg",
            sortOrder: 0,
            lastUsedAt: Date(timeIntervalSinceNow: -daysAgo * 86_400),
        )
    }

    @Test
    func `caps recent cards at the limit, keeping the most recently used`() {
        let content = QuickLogContentModel()
        // 15 distinct substances, substance-0 most recent … substance-14 oldest.
        let doses = (0 ..< 15).map { makeDose("Sub\($0)", daysAgo: Double($0)) }

        content.rebuildColorLookup(substanceColors: [])
        content.rebuildCards(quickLogDoses: doses, favorites: [])

        #expect(content.cachedCards.count == 15) // all built
        #expect(content.cachedNonFavoriteCards.count == QuickLogContentModel.recentCardLimit)
        // The kept cards are the most-recent prefix — newest first, oldest dropped.
        #expect(content.cachedNonFavoriteCards.first?.substanceName == "Sub0")
        #expect(content.cachedNonFavoriteCards.contains { $0.substanceName == "Sub14" } == false)
    }

    @Test
    func `favorites are exempt from the recent cap`() {
        let content = QuickLogContentModel()
        let doses = (0 ..< 15).map { makeDose("Sub\($0)", daysAgo: Double($0)) }
        // Favorite the three oldest — they'd be cut from the recent prefix, but
        // belong in the favorites section regardless.
        let favorites = [12, 13, 14].map { FavoriteSubstance(substance: "Sub\($0)") }

        content.rebuildColorLookup(substanceColors: [])
        content.rebuildCards(quickLogDoses: doses, favorites: favorites)

        #expect(content.cachedFavoriteCards.count == 3)
        #expect(content.cachedNonFavoriteCards.count == QuickLogContentModel.recentCardLimit)
        // No overlap between the two sections.
        let favIDs = Set(content.cachedFavoriteCards.map(\.id))
        #expect(content.cachedNonFavoriteCards.allSatisfy { !favIDs.contains($0.id) })
    }
}
