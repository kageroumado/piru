import Foundation

/// Rewrites a persisted grouping from the five-thumbnail picker into the
/// three-view one, so nobody's saved choice snaps back to Days. Recent was the
/// Timeline's bubbles without the hour axis, so it becomes Timeline with the
/// axis off; Substance and Category become Grouped with the matching key.
enum JournalGroupingMigration {
    static let groupingKey = "journalGrouping"
    static let groupKeyKey = "journalGroupKey"
    static let timelineAxisKey = "timelineShowsAxis"

    enum Outcome: Equatable {
        case unchanged
        case recentToTimeline
        case substanceToGrouped
        case categoryToGrouped
    }

    @discardableResult
    static func migrate(in defaults: UserDefaults) -> Outcome {
        switch defaults.string(forKey: groupingKey) {
        case "Recent":
            defaults.set(JournalGrouping.timeline.rawValue, forKey: groupingKey)
            defaults.set(false, forKey: timelineAxisKey)
            return .recentToTimeline
        case "Substance":
            defaults.set(JournalGrouping.grouped.rawValue, forKey: groupingKey)
            defaults.set(JournalGroupKey.substance.rawValue, forKey: groupKeyKey)
            return .substanceToGrouped
        case "Category":
            defaults.set(JournalGrouping.grouped.rawValue, forKey: groupingKey)
            defaults.set(JournalGroupKey.category.rawValue, forKey: groupKeyKey)
            return .categoryToGrouped
        default:
            return .unchanged
        }
    }
}
