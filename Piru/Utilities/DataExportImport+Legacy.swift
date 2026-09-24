import Foundation
import SwiftData

// MARK: - Legacy Piru Format (Import Only)

private nonisolated struct LegacyPiruData: Decodable {
    var doseEntries: [LegacyDoseEntry]
    var dailyDoseItems: [LegacyDailyDoseItem]
    var substanceColors: [LegacySubstanceColor]
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

// MARK: - Legacy Import

extension DataExportImport {
    /// Decodes a legacy file without touching any store; throws what ``importLegacy`` would.
    nonisolated static func validateLegacy(data: Data) throws {
        _ = try decodeLegacy(data)
    }

    private nonisolated static func decodeLegacy(_ data: Data) throws -> LegacyPiruData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LegacyPiruData.self, from: data)
    }

    static func importLegacy(data: Data, context: ModelContext) throws {
        let imported = try decodeLegacy(data)

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
            let tint = LegacyColorImport.p3(fromSRGBHex: color.hexColor)
            context.insert(SubstanceColor(substance: color.substance, tint: tint, usesDefault: false))
        }
    }
}
