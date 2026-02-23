import Foundation
import SwiftData

@Model
final class DoseEntry {
    var substance: String
    var amount: Double
    var unit: String
    var route: RouteOfAdministration
    var timestamp: Date
    var notes: String?

    init(
        substance: String,
        amount: Double,
        unit: String = "mg",
        route: RouteOfAdministration = .oral,
        timestamp: Date = .now,
        notes: String? = nil
    ) {
        self.substance = substance
        self.amount = max(0, amount)
        self.unit = unit
        self.route = route
        self.timestamp = timestamp
        self.notes = notes
    }
}
