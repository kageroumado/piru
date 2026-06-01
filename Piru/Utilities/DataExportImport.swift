import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - PsyLog Color Mapping

private enum PsyLogColorMap {
    static let nameToHex: [String: String] = [
        "BLUE": "007AFF",
        "PURPLE": "AF52DE",
        "PINK": "FF2D55",
        "RED": "FF3B30",
        "ORANGE": "FF9500",
        "YELLOW": "FFCC00",
        "GREEN": "34C759",
        "CYAN": "00BCD4",
        "MINT": "00C7BE",
        "TEAL": "30B0C7",
        "INDIGO": "5856D6",
        "BROWN": "A2845E",
        "DEEP_PINK": "FF1493",
        "MAGENTA": "E91E63",
        "FUCHSIA": "CA1F7B",
        "CRIMSON": "D32F2F",
        "FIRE_ENGINE_RED": "CE2029",
        "MAROON": "800000",
        "BURGUNDY": "800020",
        "SCARLET": "FF2400",
        "CINNABAR": "E34234",
        "BYZANTIUM": "702963",
        "JAZZBERRY_JAM": "A50B5E",
        "DARK_MAGENTA": "8B008B",
        "HELIOTROPE": "DF73FF",
        "DEEP_LAVENDER": "CE93D8",
        "LIME_GREEN": "32CD32",
        "ROYAL_BLUE": "4169E1",
        "AUBURN": "A52A2A",
        "BLUE_VIOLET": "8A2BE2",
        "BRONZE": "CD7F32",
        "CORAL": "FF7F50",
        "DARK_GOLD": "B8860B",
        "DARK_OLIVE_GREEN": "556B2F",
        "DARK_ORANGE": "FF8C00",
        "DARK_TURQUOISE": "00CED1",
        "DARK_VIOLET": "9400D3",
        "DODGER_BLUE": "1E90FF",
        "FOREST_GREEN": "228B22",
        "GOLD": "FFD700",
        "GRAYISH_MAGENTA": "9E7C93",
        "HOT_PINK": "FF69B4",
        "JUNGLE_GREEN": "29AB87",
        "KHAKI": "BDB76B",
        "LIGHT_SEA_GREEN": "20B2AA",
        "LIME": "00FF00",
        "MOSS_GREEN": "8A9A5B",
        "OLIVE": "808000",
        "OLIVE_DRAB": "6B8E23",
        "ORANGE_RED": "FF4500",
        "RUST": "B7410E",
        "SADDLE_BROWN": "8B4513",
        "SEA_GREEN": "2E8B57",
        "TOMATO": "FF6347",
    ]

    private static let hexToName: [String: String] = Dictionary(nameToHex.map { ($0.value.uppercased(), $0.key) }, uniquingKeysWith: { first, _ in first })

    static func hex(from name: String) -> String {
        nameToHex[name.uppercased()] ?? "007AFF"
    }

    static func name(from hex: String) -> String {
        let hex = hex.uppercased()
        if let exact = hexToName[hex] { return exact }
        let t = rgb(hex)
        var closest = "BLUE"
        var minDist = Double.greatestFiniteMagnitude
        for (name, colorHex) in nameToHex {
            let c = rgb(colorHex)
            let d = pow(t.0 - c.0, 2) + pow(t.1 - c.1, 2) + pow(t.2 - c.2, 2)
            if d < minDist { minDist = d; closest = name }
        }
        return closest
    }

    private static func rgb(_ hex: String) -> (Double, Double, Double) {
        var int: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: .alphanumerics.inverted)).scanHexInt64(&int)
        return (Double((int >> 16) & 0xFF), Double((int >> 8) & 0xFF), Double(int & 0xFF))
    }
}

// MARK: - Route Mapping

private extension RouteOfAdministration {
    var psylogName: String {
        switch self {
        case .oral: "ORAL"
        case .sublingual: "SUBLINGUAL"
        case .insufflation: "INSUFFLATED"
        case .inhalation: "INHALED"
        case .intravenous: "INTRAVENOUS"
        case .intramuscular: "INTRAMUSCULAR"
        case .subcutaneous: "SUBCUTANEOUS"
        case .transdermal: "TRANSDERMAL"
        case .rectal: "RECTAL"
        case .other: "ORAL"
        }
    }

    init(psylogName: String) {
        switch psylogName.uppercased() {
        case "ORAL": self = .oral
        case "SUBLINGUAL": self = .sublingual
        case "INSUFFLATED": self = .insufflation
        case "INHALED": self = .inhalation
        case "INTRAVENOUS": self = .intravenous
        case "INTRAMUSCULAR": self = .intramuscular
        case "SUBCUTANEOUS": self = .subcutaneous
        case "TRANSDERMAL": self = .transdermal
        case "RECTAL": self = .rectal
        default: self = .other
        }
    }
}

// MARK: - Millisecond Timestamps

private extension Date {
    var msSince1970: Int64 {
        Int64(timeIntervalSince1970 * 1_000)
    }
    init(ms: Int64) {
        self.init(timeIntervalSince1970: Double(ms) / 1_000.0)
    }
}

// MARK: - PsyLog Codable Types

private struct PsyLogFile: Codable {
    var experiences: [PsyLogExperience]
    var substanceCompanions: [PsyLogCompanion]
    var customUnits: [PsyLogCustomUnit]
    var customSubstances: [PsyLogCustomSubstance]
    var dailyDoseItems: [PsyLogDailyDoseItem]

    private enum CodingKeys: String, CodingKey {
        case experiences
        case substanceCompanions
        case customUnits
        case customSubstances
        case dailyDoseItems
    }

    init(
        experiences: [PsyLogExperience],
        companions: [PsyLogCompanion],
        dailyDoseItems: [PsyLogDailyDoseItem] = [],
        customSubstances: [PsyLogCustomSubstance] = [],
    ) {
        self.experiences = experiences
        self.substanceCompanions = companions
        self.customUnits = []
        self.customSubstances = customSubstances
        self.dailyDoseItems = dailyDoseItems
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        experiences = try c.decode([PsyLogExperience].self, forKey: .experiences)
        substanceCompanions = try c.decodeIfPresent([PsyLogCompanion].self, forKey: .substanceCompanions) ?? []
        customUnits = try c.decodeIfPresent([PsyLogCustomUnit].self, forKey: .customUnits) ?? []
        dailyDoseItems = try c.decodeIfPresent([PsyLogDailyDoseItem].self, forKey: .dailyDoseItems) ?? []
        // PsyLog historically writes `customSubstances: []` (string array
        // placeholder); Piru ≥ build 12 writes a proper array of custom
        // substance objects. Decode whichever shape is present; treat anything
        // unparseable as empty so a malformed `customSubstances` field never
        // blocks an import that would otherwise succeed.
        if let parsed = try? c.decodeIfPresent([PsyLogCustomSubstance].self, forKey: .customSubstances) {
            customSubstances = parsed
        } else {
            customSubstances = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(experiences, forKey: .experiences)
        try c.encode(substanceCompanions, forKey: .substanceCompanions)
        try c.encode([String](), forKey: .customUnits)
        try c.encode(customSubstances, forKey: .customSubstances)
        try c.encode(dailyDoseItems, forKey: .dailyDoseItems)
    }
}

private struct PsyLogExperience: Codable {
    var title: String
    var isFavorite: Bool
    var creationDate: Int64
    var sortDate: Int64
    var text: String
    var ingestions: [PsyLogIngestion]

    private enum CodingKeys: String, CodingKey {
        case title
        case isFavorite
        case creationDate
        case sortDate
        case text
        case ingestions
        case ratings
        case location
        case timedNotes
    }

    init(title: String, creationDate: Int64, sortDate: Int64, ingestions: [PsyLogIngestion]) {
        self.title = title
        self.isFavorite = false
        self.creationDate = creationDate
        self.sortDate = sortDate
        self.text = ""
        self.ingestions = ingestions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        creationDate = try c.decode(Int64.self, forKey: .creationDate)
        sortDate = try c.decode(Int64.self, forKey: .sortDate)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        ingestions = try c.decodeIfPresent([PsyLogIngestion].self, forKey: .ingestions) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode([String](), forKey: .ratings)
        try c.encode(title, forKey: .title)
        try c.encode(isFavorite, forKey: .isFavorite)
        try c.encode(creationDate, forKey: .creationDate)
        try c.encodeNil(forKey: .location)
        try c.encode(sortDate, forKey: .sortDate)
        try c.encode(text, forKey: .text)
        try c.encode([String](), forKey: .timedNotes)
        try c.encode(ingestions, forKey: .ingestions)
    }
}

private struct PsyLogIngestion: Codable {
    var substanceName: String?
    var customUnitId: Int?
    var dose: Double?
    var time: Int64
    var administrationRoute: String
    var notes: String
    var units: String

    private enum CodingKeys: String, CodingKey {
        case substanceName
        case dose
        case time
        case administrationRoute
        case notes
        case units
        case customUnitId
        case creationDate
        case consumerName
        case estimatedDoseStandardDeviation
        case isDoseAnEstimate
        case stomachFullness
        case endTime
    }

    init(substanceName: String, dose: Double, time: Int64, route: String, notes: String, units: String) {
        self.substanceName = substanceName
        self.customUnitId = nil
        self.dose = dose
        self.time = time
        self.administrationRoute = route
        self.notes = notes
        self.units = units
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        substanceName = try c.decodeIfPresent(String.self, forKey: .substanceName)
        customUnitId = try c.decodeIfPresent(Int.self, forKey: .customUnitId)
        dose = try c.decodeIfPresent(Double.self, forKey: .dose)
        time = try c.decode(Int64.self, forKey: .time)
        administrationRoute = try c.decodeIfPresent(String.self, forKey: .administrationRoute) ?? "ORAL"
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        units = try c.decodeIfPresent(String.self, forKey: .units) ?? "mg"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeNil(forKey: .customUnitId)
        try c.encode(time, forKey: .creationDate)
        try c.encodeNil(forKey: .consumerName)
        try c.encode(substanceName, forKey: .substanceName)
        try c.encodeNil(forKey: .estimatedDoseStandardDeviation)
        try c.encode(false, forKey: .isDoseAnEstimate)
        try c.encodeNil(forKey: .stomachFullness)
        try c.encode(dose, forKey: .dose)
        try c.encodeNil(forKey: .endTime)
        try c.encode(time, forKey: .time)
        try c.encode(administrationRoute, forKey: .administrationRoute)
        try c.encode(notes, forKey: .notes)
        try c.encode(units, forKey: .units)
    }
}

private struct PsyLogCompanion: Codable {
    var color: String
    var substanceName: String
}

private struct PsyLogDailyDoseItem: Codable {
    var substance: String
    var amount: Double
    var unit: String
    var route: String
    var sortOrder: Int
}

/// Piru-native shape for a user-defined substance inside a PsyLog-format
/// export. Mirrors ``CustomSubstanceEntry`` so Piru→Piru round-trips preserve
/// every field — including the duration profile, which is what restores
/// timeline-graph behaviour for substances the bundled library lacks data
/// for. Cross-app PsyLog files typically omit this key or carry an empty
/// string array; the file-level decoder treats both as "no customs".
private struct PsyLogCustomSubstance: Codable {
    var id: UUID
    var name: String
    var category: SubstanceCategory
    var defaultRoute: RouteOfAdministration
    var unit: String
    var notes: String
    var duration: DurationProfile?
    var createdAt: Int64

    init(_ entry: CustomSubstanceEntry) {
        self.id = entry.id
        self.name = entry.name
        self.category = entry.category
        self.defaultRoute = entry.defaultRoute
        self.unit = entry.unit
        self.notes = entry.notes
        self.duration = entry.duration
        self.createdAt = entry.createdAt.msSince1970
    }

    var asEntry: CustomSubstanceEntry {
        CustomSubstanceEntry(
            id: id,
            name: name,
            category: category,
            defaultRoute: defaultRoute,
            unit: unit,
            notes: notes,
            duration: duration,
            createdAt: Date(ms: createdAt),
        )
    }
}

private struct PsyLogCustomUnit: Codable {
    var id: Int
    var name: String
    var unit: String
    var color: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case unit
        case color
        case isArchived
        case doseComponents
        case unitPlural
        case note
        case creationDate
        case roaInfos
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? "mg"
        color = try c.decodeIfPresent(String.self, forKey: .color)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(unit, forKey: .unit)
    }
}

// MARK: - Legacy Piru Format (Import Only)

private struct LegacyPiruData: Decodable {
    var doseEntries: [LegacyDoseEntry]
    var dailyDoseItems: [LegacyDailyDoseItem]
    var substanceColors: [LegacySubstanceColor]
    var userColors: [LegacyUserColor]
}

private struct LegacyDoseEntry: Decodable {
    var substance: String
    var amount: Double
    var unit: String
    var route: RouteOfAdministration
    var timestamp: Date
    var notes: String?
    var tags: [String]?
}

private struct LegacyDailyDoseItem: Decodable {
    var substance: String
    var amount: Double
    var unit: String
    var route: RouteOfAdministration
    var sortOrder: Int
}

private struct LegacySubstanceColor: Decodable {
    var substance: String
    var hexColor: String
}

private struct LegacyUserColor: Decodable {
    var hex: String
    var name: String
    var createdAt: Date
}

// MARK: - Export / Import

enum DataExportImport {
    @MainActor
    static func exportJSON(context: ModelContext, customStore: CustomSubstanceStore = .shared) throws -> Data {
        let entries = try context.fetch(FetchDescriptor<DoseEntry>())
        let colors = try context.fetch(FetchDescriptor<SubstanceColor>())
        let dailyDoses = try context.fetch(FetchDescriptor<DailyDoseItem>())
        let customs = customStore.all

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.sessionDayStart(for: $0.timestamp) }

        let titleFormatter = DateFormatter()
        titleFormatter.dateFormat = "d MMM yyyy"
        titleFormatter.locale = Locale(identifier: "en_US")

        let experiences: [PsyLogExperience] = grouped.keys.sorted().map { day in
            let dayEntries = grouped[day]!.sorted { $0.timestamp < $1.timestamp }
            let ingestions = dayEntries.map { entry in
                var noteText = entry.notes ?? ""
                if !entry.tags.isEmpty {
                    let tagStr = entry.tags.map { "#\($0)" }.joined(separator: " ")
                    noteText = noteText.isEmpty ? tagStr : "\(noteText) \(tagStr)"
                }
                return PsyLogIngestion(
                    substanceName: entry.substance,
                    dose: entry.amount,
                    time: entry.timestamp.msSince1970,
                    route: entry.route.psylogName,
                    notes: noteText,
                    units: entry.unit,
                )
            }
            let earliest = dayEntries.first!.timestamp.msSince1970
            return PsyLogExperience(
                title: titleFormatter.string(from: day),
                creationDate: earliest,
                sortDate: earliest,
                ingestions: ingestions,
            )
        }

        let companions = colors.map {
            PsyLogCompanion(color: PsyLogColorMap.name(from: $0.hexColor), substanceName: $0.substance)
        }

        let exportedDailyDoses = dailyDoses.map {
            PsyLogDailyDoseItem(
                substance: $0.substance,
                amount: $0.amount,
                unit: $0.unit,
                route: $0.route.psylogName,
                sortOrder: $0.sortOrder,
            )
        }

        let exportedCustoms = customs.map(PsyLogCustomSubstance.init)
        let file = PsyLogFile(
            experiences: experiences,
            companions: companions,
            dailyDoseItems: exportedDailyDoses,
            customSubstances: exportedCustoms,
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    @MainActor
    static func importJSON(data: Data, context: ModelContext, customStore: CustomSubstanceStore = .shared) throws {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["experiences"] != nil {
            try importPsyLog(data: data, context: context, customStore: customStore)
        } else {
            try importLegacy(data: data, context: context)
        }
    }

    @MainActor
    private static func importPsyLog(data: Data, context: ModelContext, customStore: CustomSubstanceStore) throws {
        let file = try JSONDecoder().decode(PsyLogFile.self, from: data)

        // User-defined substances win fully over library entries with the
        // same name — the import is the user's explicit say-so. Adds new
        // customs and updates existing matches (preserving the stored UUID
        // when present so other models keep referencing the same row); skips
        // exact duplicates so re-imports stay idempotent.
        var existingByName: [String: CustomSubstanceEntry] = Dictionary(
            customStore.all.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first },
        )
        for imported in file.customSubstances {
            let incoming = imported.asEntry
            let key = incoming.name.lowercased()
            if let existing = existingByName[key] {
                guard existing != incoming else { continue }
                // Preserve the existing row's UUID so other state referencing
                // it (e.g. open form sheets) stays valid; re-init with the
                // imported field values so the update goes through.
                let merged = CustomSubstanceEntry(
                    id: existing.id,
                    name: incoming.name,
                    category: incoming.category,
                    defaultRoute: incoming.defaultRoute,
                    unit: incoming.unit,
                    notes: incoming.notes,
                    duration: incoming.duration,
                    createdAt: incoming.createdAt,
                )
                customStore.update(merged)
                existingByName[key] = merged
            } else {
                customStore.add(incoming)
                existingByName[key] = incoming
            }
        }

        // Build custom unit lookup: id -> custom unit
        let customUnitMap = Dictionary(file.customUnits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Dedup dose entries against what's already stored (and within this
        // import) so a merge restore — or re-importing the same file — stays
        // idempotent instead of multiplying every dose. `DoseEntry` has no
        // natural id, so the key is its content: substance, time, dose, unit, route.
        let existingDoses = (try? context.fetch(FetchDescriptor<DoseEntry>())) ?? []
        var seenDoseKeys = Set(existingDoses.map {
            doseDedupKey(substance: $0.substance, timestamp: $0.timestamp, amount: $0.amount, unit: $0.unit, route: $0.route)
        })

        for experience in file.experiences {
            for ingestion in experience.ingestions {
                // Resolve substance name: prefer direct name, fall back to custom unit
                let name: String
                if let directName = ingestion.substanceName {
                    name = directName
                } else if let cuId = ingestion.customUnitId, let cu = customUnitMap[cuId] {
                    name = cu.name
                } else {
                    continue
                }

                // Skip entries with missing or zero dose
                guard let dose = ingestion.dose, dose > 0 else { continue }

                let route = RouteOfAdministration(psylogName: ingestion.administrationRoute)
                let timestamp = Date(ms: ingestion.time)
                let key = doseDedupKey(substance: name, timestamp: timestamp, amount: dose, unit: ingestion.units, route: route)
                guard seenDoseKeys.insert(key).inserted else { continue }

                let extractedTags = TagExtractor.extractTags(from: ingestion.notes)
                context.insert(DoseEntry(
                    substance: name,
                    amount: dose,
                    unit: ingestion.units,
                    route: route,
                    timestamp: timestamp,
                    notes: ingestion.notes.isEmpty ? nil : ingestion.notes,
                    tags: extractedTags,
                ))
            }
        }

        // Track imported colors to avoid duplicates — seeded with existing
        // colors so a merge doesn't insert a second row for a substance.
        var importedColors = Set(((try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []).map { $0.substance.lowercased() })

        for companion in file.substanceCompanions {
            let key = companion.substanceName.lowercased()
            guard !importedColors.contains(key) else { continue }
            importedColors.insert(key)
            context.insert(SubstanceColor(
                substance: companion.substanceName,
                hexColor: PsyLogColorMap.hex(from: companion.color),
            ))
        }

        // Import colors from custom units that aren't already in companions
        for cu in file.customUnits {
            guard let colorName = cu.color,
                  !importedColors.contains(cu.name.lowercased()) else { continue }
            importedColors.insert(cu.name.lowercased())
            context.insert(SubstanceColor(
                substance: cu.name,
                hexColor: PsyLogColorMap.hex(from: colorName),
            ))
        }

        // Import daily dose items, skip duplicates by substance name
        if !file.dailyDoseItems.isEmpty {
            let existing = (try? context.fetch(FetchDescriptor<DailyDoseItem>())) ?? []
            let existingNames = Set(existing.map { $0.substance.lowercased() })

            for item in file.dailyDoseItems {
                guard !existingNames.contains(item.substance.lowercased()) else { continue }
                context.insert(DailyDoseItem(
                    substance: item.substance,
                    amount: item.amount,
                    unit: item.unit,
                    route: RouteOfAdministration(psylogName: item.route),
                    sortOrder: item.sortOrder,
                ))
            }
        }
    }

    private static func importLegacy(data: Data, context: ModelContext) throws {
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

    /// Content-based identity for a dose entry, used to skip duplicates on
    /// import. Lowercased substance/unit so cosmetic casing differences don't
    /// defeat it; millisecond timestamp matches the export precision.
    private static func doseDedupKey(substance: String, timestamp: Date, amount: Double, unit: String, route: RouteOfAdministration) -> String {
        "\(substance.lowercased())|\(timestamp.msSince1970)|\(amount)|\(unit.lowercased())|\(route.rawValue)"
    }

    static func deleteAll(context: ModelContext) throws {
        try context.delete(model: DoseEntry.self)
        try context.delete(model: DailyDoseItem.self)
        try context.delete(model: SubstanceColor.self)
        try context.delete(model: UserColor.self)
    }

    static var exportFilename: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HHmmss"
        return "Piru \(f.string(from: .now))"
    }
}

// MARK: - File Document for Export

struct PiruDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json]
    }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
