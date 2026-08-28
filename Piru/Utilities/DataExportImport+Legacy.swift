import Foundation
import SwiftData

// MARK: - Legacy Piru Format (Import Only)

private nonisolated struct LegacyPiruData: Decodable {
    var doseEntries: [LegacyDoseEntry]
    var dailyDoseItems: [LegacyDailyDoseItem]
    var substanceColors: [LegacySubstanceColor]
    var userColors: [LegacyUserColor]
}

private nonisolated struct LegacyDoseEntry: Decodable {
    var substance: String
    var amount: Double
    var unit: String
    var route: RouteOfAdministration
    var timestamp: Date
    var notes: String?
    var tags: [String]?
    var locationName: String?
    var latitude: Double?
    var longitude: Double?
}

private nonisolated struct LegacyDailyDoseItem: Decodable {
    var substance: String
    var amount: Double
    var unit: String
    var route: RouteOfAdministration
    var sortOrder: Int
}

private nonisolated struct LegacySubstanceColor: Decodable {
    var substance: String
    var hexColor: String
}

private nonisolated struct LegacyUserColor: Decodable {
    var hex: String
    var name: String
    var createdAt: Date
}

// MARK: - Legacy Import

extension DataExportImport {
    static func importLegacy(data: Data, context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let imported = try decoder.decode(LegacyPiruData.self, from: data)

        for entry in imported.doseEntries {
            context.insert(DoseEntry(
                substance: entry.substance,
                amount: entry.amount,
                unit: entry.unit,
                route: entry.route,
                timestamp: entry.timestamp,
                notes: entry.notes,
                tags: entry.tags ?? [],
                locationName: entry.locationName,
                latitude: entry.latitude,
                longitude: entry.longitude,
            ))
        }

        for item in imported.dailyDoseItems {
            context.insert(DailyDoseItem(
                substance: item.substance,
                amount: item.amount,
                unit: item.unit,
                route: item.route,
                sortOrder: item.sortOrder,
            ))
        }

        for color in imported.substanceColors {
            context.insert(SubstanceColor(substance: color.substance, hexColor: color.hexColor))
        }

        for color in imported.userColors {
            let uc = UserColor(hex: color.hex, name: color.name)
            uc.createdAt = color.createdAt
            context.insert(uc)
        }
    }
}
