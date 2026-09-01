import Foundation
import Testing
@testable import Piru

/// The persisted-grouping rewrite from the five-thumbnail picker to Days ·
/// Timeline · Grouped. Runs against a throwaway defaults suite.
@Suite("JournalGroupingMigration")
struct JournalGroupingMigrationTests {
    private func freshDefaults() -> UserDefaults {
        let name = "JournalGroupingMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test
    func `Recent becomes Timeline with the axis off`() {
        let defaults = freshDefaults()
        defaults.set("Recent", forKey: JournalGroupingMigration.groupingKey)

        #expect(JournalGroupingMigration.migrate(in: defaults) == .recentToTimeline)
        #expect(defaults.string(forKey: JournalGroupingMigration.groupingKey) == JournalGrouping.timeline.rawValue)
        #expect(defaults.object(forKey: JournalGroupingMigration.timelineAxisKey) != nil)
        #expect(defaults.bool(forKey: JournalGroupingMigration.timelineAxisKey) == false)
    }

    @Test(arguments: [
        ("Substance", JournalGroupKey.substance, JournalGroupingMigration.Outcome.substanceToGrouped),
        ("Category", .category, .categoryToGrouped),
    ])
    func `Substance and Category become Grouped with the matching key`(
        stored: String, key: JournalGroupKey, outcome: JournalGroupingMigration.Outcome,
    ) {
        let defaults = freshDefaults()
        defaults.set(stored, forKey: JournalGroupingMigration.groupingKey)

        #expect(JournalGroupingMigration.migrate(in: defaults) == outcome)
        #expect(defaults.string(forKey: JournalGroupingMigration.groupingKey) == JournalGrouping.grouped.rawValue)
        #expect(defaults.string(forKey: JournalGroupingMigration.groupKeyKey) == key.rawValue)
        // A Grouped user never had an axis preference to migrate.
        #expect(defaults.object(forKey: JournalGroupingMigration.timelineAxisKey) == nil)
    }

    @Test(arguments: [nil, "Days", "Timeline", "Grouped"])
    func `Current values and an empty store are left alone`(stored: String?) {
        let defaults = freshDefaults()
        if let stored { defaults.set(stored, forKey: JournalGroupingMigration.groupingKey) }

        #expect(JournalGroupingMigration.migrate(in: defaults) == .unchanged)
        #expect(defaults.string(forKey: JournalGroupingMigration.groupingKey) == stored)
        #expect(defaults.object(forKey: JournalGroupingMigration.groupKeyKey) == nil)
        #expect(defaults.object(forKey: JournalGroupingMigration.timelineAxisKey) == nil)
    }

    @Test
    func `Migrating twice is a no-op the second time`() {
        let defaults = freshDefaults()
        defaults.set("Recent", forKey: JournalGroupingMigration.groupingKey)
        JournalGroupingMigration.migrate(in: defaults)
        // A user who turned the axis back on keeps it on.
        defaults.set(true, forKey: JournalGroupingMigration.timelineAxisKey)

        #expect(JournalGroupingMigration.migrate(in: defaults) == .unchanged)
        #expect(defaults.bool(forKey: JournalGroupingMigration.timelineAxisKey) == true)
    }

    @Test
    func `Every persisted raw value still resolves to a case`() {
        for grouping in JournalGrouping.allCases {
            #expect(JournalGrouping(rawValue: grouping.rawValue) == grouping)
        }
        #expect(JournalGrouping(rawValue: "Recent") == nil)
        #expect(JournalGrouping.allCases.count == 3)
    }
}
