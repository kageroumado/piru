import Foundation
import SwiftData

// MARK: - Dose Frequency

enum DoseFrequency: String, Codable, CaseIterable, Identifiable {
    case daily
    case everyOtherDay
    case weekly
    case biweekly
    case monthly
    case specificDays

    var id: String {
        rawValue
    }

    var displayName: LocalizedStringResource {
        switch self {
        case .daily: "Daily"
        case .everyOtherDay: "Every other day"
        case .weekly: "Weekly"
        case .biweekly: "Every 2 weeks"
        case .monthly: "Monthly"
        case .specificDays: "Specific days"
        }
    }

    var shortLabel: LocalizedStringResource {
        switch self {
        case .daily: "Daily"
        case .everyOtherDay: "Every 2 days"
        case .weekly: "Weekly"
        case .biweekly: "Biweekly"
        case .monthly: "Monthly"
        case .specificDays: "Custom days"
        }
    }
}

// MARK: - Model

/// A recurring medication or supplement scheduled on a fixed cadence.
///
/// SwiftData `@Model` shared across the main Piru app, the Home Screen widget
/// (`PiruWidget`), and the Lock Screen Live Activity extension
/// (`PiruLiveActivityExtension`).
///
/// ## Schedule Storage
/// - ``frequency`` is exposed as a ``DoseFrequency`` enum but persisted via
///   ``frequencyRaw`` (a `String`) so the column survives Swift-level renames.
/// - ``frequencyDays`` is exposed as `[Int]` but persisted via
///   ``frequencyDaysData`` (JSON-encoded `Data`). Arrays of value types are
///   awkward to model across SwiftData and our extension targets; JSON
///   storage keeps the schema flat and portable.
///
/// ## Schema Migration Note
/// All persisted properties have default values (e.g. `frequencyRaw`,
/// `frequencyDaysData`, `category`, `startDate`) so new fields can be added
/// non-destructively as the model evolves. When introducing a new field,
/// always supply a default so existing user data migrates without prompting.
@Model
final class DailyDoseItem {
    /// The substance's display name.
    var substance: String
    /// Quantity of one dose in ``unit``.
    var amount: Double
    /// Unit of measure for ``amount`` (e.g. `"mg"`, `"µg"`).
    var unit: String
    /// Route of administration; persisted as `rawValue` (a `String`).
    var route: RouteOfAdministration
    /// User-defined ordering within the daily list.
    var sortOrder: Int
    /// Optional category label used to group items in the UI.
    var category: String = ""

    // Schedule

    /// Backing storage for ``frequency``. Prefer reading/writing ``frequency``.
    var frequencyRaw: String = DoseFrequency.daily.rawValue
    /// JSON-encoded backing storage for ``frequencyDays``. Prefer reading/writing ``frequencyDays``.
    var frequencyDaysData: Data = Data()
    /// First day the schedule should be considered active.
    var startDate: Date = Date.distantPast

    /// Recurrence cadence; computed view over ``frequencyRaw``.
    var frequency: DoseFrequency {
        get { DoseFrequency(rawValue: frequencyRaw) ?? .daily }
        set { frequencyRaw = newValue.rawValue }
    }

    /// Weekday indices used when ``frequency`` is `.specificDays`.
    ///
    /// Encoded using Foundation's `Calendar` weekday convention:
    /// `1 = Sunday, 2 = Monday, …, 7 = Saturday`. Values are JSON-encoded into
    /// ``frequencyDaysData`` for SwiftData portability across extension targets.
    var frequencyDays: [Int] {
        get { (try? JSONDecoder().decode([Int].self, from: frequencyDaysData)) ?? [] }
        set { frequencyDaysData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(
        substance: String,
        amount: Double,
        unit: String = "mg",
        route: RouteOfAdministration = .oral,
        sortOrder: Int = 0,
        category: String = "",
        frequency: DoseFrequency = .daily,
        frequencyDays: [Int] = [],
        startDate: Date = .distantPast,
    ) {
        self.substance = substance
        self.amount = amount
        self.unit = unit
        self.route = route
        self.sortOrder = sortOrder
        self.category = category
        self.frequencyRaw = frequency.rawValue
        self.frequencyDaysData = (try? JSONEncoder().encode(frequencyDays)) ?? Data()
        self.startDate = startDate
    }
}
