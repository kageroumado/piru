import SwiftData
import Foundation

@Model
final class CustomSubstance {
    @Attribute(.unique) var name: String
    var category: SubstanceCategory
    var defaultRoute: RouteOfAdministration
    var unit: String
    var notes: String
    var createdAt: Date

    init(
        name: String,
        category: SubstanceCategory = .other,
        defaultRoute: RouteOfAdministration = .oral,
        unit: String = "mg",
        notes: String = ""
    ) {
        self.name = name
        self.category = category
        self.defaultRoute = defaultRoute
        self.unit = unit
        self.notes = notes
        self.createdAt = Date()
    }

    @MainActor var asSubstance: Substance {
        Substance(
            name: name,
            aliases: [],
            category: category,
            defaultRoute: defaultRoute,
            routes: [SubstanceRoute(route: defaultRoute, unit: unit, doses: DoseRange())],
            effects: [],
            sources: ["User-defined"]
        )
    }
}
