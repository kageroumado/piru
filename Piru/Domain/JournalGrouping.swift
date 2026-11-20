import Foundation

/// The Journal's three views. `grouped` buckets entries under a secondary key
/// (``JournalGroupKey``) picked in the options popover.
enum JournalGrouping: String, CaseIterable {
    // Order drives the grouping menu.
    case byDay = "Days"
    case timeline = "Timeline"
    case grouped = "Grouped"

    var displayName: LocalizedStringResource {
        switch self {
        case .byDay: "Days"
        case .timeline: "Timeline"
        case .grouped: "Grouped"
        }
    }
}

/// What the Grouped view buckets by — the popover's segmented control under
/// the thumbnails. Remembered across launches.
enum JournalGroupKey: String, CaseIterable {
    case substance = "Substance"
    case category = "Category"

    var displayName: LocalizedStringResource {
        switch self {
        case .substance: "By Substance"
        case .category: "By Category"
        }
    }
}
