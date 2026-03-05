import Foundation
import SwiftData

@Model
final class DailyDoseItem {
    var substance: String
    var amount: Double
    var unit: String
    var route: RouteOfAdministration
    var sortOrder: Int
    var category: String = ""

    init(
        substance: String,
        amount: Double,
        unit: String = "mg",
        route: RouteOfAdministration = .oral,
        sortOrder: Int = 0,
        category: String = ""
    ) {
        self.substance = substance
        self.amount = amount
        self.unit = unit
        self.route = route
        self.sortOrder = sortOrder
        self.category = category
    }
}
