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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily: "Daily"
        case .everyOtherDay: "Every other day"
        case .weekly: "Weekly"
        case .biweekly: "Every 2 weeks"
        case .monthly: "Monthly"
        case .specificDays: "Specific days"
        }
    }

    var shortLabel: String {
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

@Model
final class DailyDoseItem {
    var substance: String
    var amount: Double
    var unit: String
    var route: RouteOfAdministration
    var sortOrder: Int
    var category: String = ""

    // Schedule
    var frequencyRaw: String = DoseFrequency.daily.rawValue
    var frequencyDaysData: Data = Data()
    var startDate: Date = Date.distantPast

    var frequency: DoseFrequency {
        get { DoseFrequency(rawValue: frequencyRaw) ?? .daily }
        set { frequencyRaw = newValue.rawValue }
    }

    /// Weekday indices for `.specificDays` — 1=Sunday, 2=Monday, ..., 7=Saturday (Calendar convention)
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
        startDate: Date = .distantPast
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
