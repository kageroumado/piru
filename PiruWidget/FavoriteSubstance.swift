import Foundation
import SwiftData

@Model
final class FavoriteSubstance {
    @Attribute(.unique) var substance: String
    var createdAt: Date

    init(substance: String) {
        self.substance = substance
        self.createdAt = .now
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
