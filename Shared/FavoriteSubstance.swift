import Foundation
import SwiftData

@Model
final class FavoriteSubstance {
    @Attribute(.unique) var substance: String
    var createdAt: Date
    /// User-defined position in the Favorites section (lower = first). New
    /// favorites append at the end; reorder via the quick-log Edit sheet.
    var sortOrder: Int = 0

    init(substance: String, sortOrder: Int = 0) {
        self.substance = substance
        self.createdAt = .now
        self.sortOrder = sortOrder
    }
}

extension [FavoriteSubstance] {
    /// Set of lowercased favorite substance names for O(1) lookup.
    var favoriteSet: Set<String> {
        Set(map { $0.substance.lowercased() })
    }

    func isFavorite(_ name: String) -> Bool {
        contains { $0.substance.lowercased() == name.lowercased() }
    }
}
