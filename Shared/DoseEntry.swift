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
    var tagsRaw: String?

    var tags: [String] {
        get {
            guard let raw = tagsRaw, !raw.isEmpty else { return [] }
            return raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        set {
            tagsRaw = newValue.isEmpty ? nil : newValue.joined(separator: ",")
        }
    }

    init(
        substance: String,
        amount: Double,
        unit: String = "mg",
        route: RouteOfAdministration = .oral,
        timestamp: Date = .now,
        notes: String? = nil,
        tags: [String] = []
    ) {
        self.substance = substance
        self.amount = max(0, amount)
        self.unit = unit
        self.route = route
        self.timestamp = timestamp
        self.notes = notes
        self.tagsRaw = tags.isEmpty ? nil : tags.joined(separator: ",")
    }
}
