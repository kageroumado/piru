import Foundation

// MARK: - Quick Log Data Types

/// A recent/favorite substance with its route groups, backing one card in the
/// quick-log list. Built from the curated `QuickLogDose` rows, not raw history.
struct SubstanceCard: Identifiable {
    let substanceName: String
    let colorHex: String?
    let routes: [SubstanceGroup]
    let latestTimestamp: Date

    var id: String {
        substanceName.lowercased()
    }
}

/// One (substance, route) pairing within a card, carrying its curated dose
/// chips sorted for display.
struct SubstanceGroup: Identifiable {
    let id: String
    let substanceName: String
    let route: RouteOfAdministration
    let colorHex: String?
    let librarySubstance: Substance?
    var latestTimestamp: Date
    private var chipEntries: [(amount: Double, unit: String, sortOrder: Double)] = []

    var doses: [DoseChip] {
        chipEntries
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { DoseChip(amount: $0.amount, unit: $0.unit) }
    }

    init(substanceName: String, route: RouteOfAdministration, colorHex: String?, librarySubstance: Substance?, latestTimestamp: Date) {
        self.id = "\(substanceName.lowercased())|\(route.rawValue)"
        self.substanceName = substanceName
        self.route = route
        self.colorHex = colorHex
        self.librarySubstance = librarySubstance
        self.latestTimestamp = latestTimestamp
    }

    /// Add a curated chip (sorted by `sortOrder` for display). Tracks the most
    /// recent use so cards order by recency.
    mutating func addChip(amount: Double, unit: String, sortOrder: Double, lastUsedAt: Date) {
        chipEntries.append((amount: amount, unit: unit, sortOrder: sortOrder))
        if lastUsedAt > latestTimestamp {
            latestTimestamp = lastUsedAt
        }
    }
}

/// A single tappable dose amount within a `SubstanceGroup`.
struct DoseChip: Identifiable {
    let amount: Double
    let unit: String

    var id: String {
        "\(amount)|\(unit)"
    }

    var formattedAmount: String {
        amount.doseFormatted
    }
}
