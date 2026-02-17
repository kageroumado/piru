import Foundation
import SwiftData

@Model
final class DailyDoseItem {
    var substance: String
    var amount: Double
    var unit: String
    var route: RouteOfAdministration
    var sortOrder: Int

    init(
        substance: String,
        amount: Double,
        unit: String = "mg",
        route: RouteOfAdministration = .oral,
        sortOrder: Int = 0
    ) {
        self.substance = substance
        self.amount = amount
        self.unit = unit
        self.route = route
        self.sortOrder = sortOrder
    }
}
