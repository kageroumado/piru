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
    nonisolated var msSince1970: Int64 {
        Int64(timeIntervalSince1970 * 1_000)
    }
    nonisolated init(ms: Int64) {
        self.init(timeIntervalSince1970: Double(ms) / 1_000.0)
    }
}

// MARK: - PsyLog Codable Types

private nonisolated struct PsyLogFile: Codable {
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
        case exportSource
    }

    /// Stamped on export so PsychonautWiki recognises the file as the modern
    /// format. PW's importer rejects files with no `exportSource` as "legacy".
    /// Verified: a file carrying this key (and none of Piru's own top-level
    /// keys) imports cleanly into the current PsychonautWiki Journal app.
    static let exportSourceValue = "iOS Journal 15.0"

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
        // placeholder); older Piru exports wrote a proper array of custom
        // substance objects. Decode whichever shape is present; treat anything
        // unparseable as empty so a malformed `customSubstances` field never
        // blocks an import that would otherwise succeed.
        if let parsed = try? c.decodeIfPresent([PsyLogCustomSubstance].self, forKey: .customSubstances) {
            customSubstances = parsed
        } else {
            customSubstances = []
        }
    }

    /// Encodes the **exact** PsychonautWiki modern shape — `exportSource`,
    /// `experiences`, `substanceCompanions`, `customUnits` — and nothing else.
    /// Piru-only data (custom substances, daily-dose items, per-dose location)
    /// is deliberately omitted; full-fidelity round-trips use the Piru-native
    /// format instead. This keeps the file importable by PsychonautWiki.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.exportSourceValue, forKey: .exportSource)
        try c.encode(experiences, forKey: .experiences)
        try c.encode(substanceCompanions, forKey: .substanceCompanions)
        try c.encode([PsyLogCustomUnit](), forKey: .customUnits)
    }
}

/// A place attached to an experience (and, as a Piru extension, to an
/// individual ingestion). Matches PsyLog's `{name, latitude, longitude}` shape.
private nonisolated struct PsyLogLocation: Codable {
    var name: String
    var latitude: Double
    var longitude: Double
}

private nonisolated struct PsyLogExperience: Codable {
    var title: String
    var isFavorite: Bool
    var creationDate: Int64
    var sortDate: Int64
    var text: String
    var location: PsyLogLocation?
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

    init(title: String, text: String = "", creationDate: Int64, sortDate: Int64, location: PsyLogLocation? = nil, ingestions: [PsyLogIngestion]) {
        self.title = title
        self.isFavorite = false
        self.creationDate = creationDate
        self.sortDate = sortDate
        self.text = text
        self.location = location
        self.ingestions = ingestions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        creationDate = try c.decode(Int64.self, forKey: .creationDate)
        sortDate = try c.decode(Int64.self, forKey: .sortDate)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        location = try c.decodeIfPresent(PsyLogLocation.self, forKey: .location)
        ingestions = try c.decodeIfPresent([PsyLogIngestion].self, forKey: .ingestions) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode([String](), forKey: .ratings)
        try c.encode(title, forKey: .title)
        try c.encode(isFavorite, forKey: .isFavorite)
        try c.encode(creationDate, forKey: .creationDate)
        try c.encode(location, forKey: .location)
        try c.encode(sortDate, forKey: .sortDate)
        try c.encode(text, forKey: .text)
        try c.encode([String](), forKey: .timedNotes)
        try c.encode(ingestions, forKey: .ingestions)
    }
}

private nonisolated struct PsyLogIngestion: Codable {
    var substanceName: String?
    var customUnitId: Int?
    var dose: Double?
    var time: Int64
    var administrationRoute: String
    var notes: String
    var units: String
    /// Piru extension: per-ingestion location. PsyLog stores location only at
    /// the experience level, so this key is absent in cross-app files and is
    /// encoded only when set — letting a Piru→Piru round-trip preserve a
    /// dose's own location even when its session spans multiple places.
    var location: PsyLogLocation?

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
        case location
        case isHiddenInTimeline
    }

    init(substanceName: String, dose: Double, time: Int64, route: String, notes: String, units: String, location: PsyLogLocation? = nil) {
        self.substanceName = substanceName
        self.customUnitId = nil
        self.dose = dose
        self.time = time
        self.administrationRoute = route
        self.notes = notes
        self.units = units
        self.location = location
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
        location = try c.decodeIfPresent(PsyLogLocation.self, forKey: .location)
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
        // PsychonautWiki's modern ingestions always carry this flag; include it
        // so the file matches their shape exactly. Per-dose location is NOT
        // emitted here — PsyLog keeps location at the experience level only.
        try c.encode(false, forKey: .isHiddenInTimeline)
    }
}

private nonisolated struct PsyLogCompanion: Codable {
    var color: String
    var substanceName: String
}

private nonisolated struct PsyLogDailyDoseItem: Codable {
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
private nonisolated struct PsyLogCustomSubstance: Codable {
    var id: UUID
    var name: String
    var category: SubstanceCategory
    var defaultRoute: RouteOfAdministration
    var unit: String
    var notes: String
    var duration: DurationProfile?
    var createdAt: Int64

    @MainActor
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

    @MainActor
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

private nonisolated struct PsyLogCustomUnit: Codable {
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

// MARK: - Piru Native Format (full-fidelity backup)

/// Piru's own export shape — a complete, lossless dump of the user's data,
/// including the things the PsyLog/PW format can't represent: session titles &
/// notes, per-dose location and background-med flag, real tag arrays,
/// favourites, user colours, and daily-dose schedules. Detected on import by
/// the `piruExportVersion` key. Timestamps are epoch milliseconds, matching the
/// PsyLog format's convention.
private nonisolated struct PiruFile: Codable {
    var piruExportVersion: Int
    /// The app version that produced the file, e.g. "Piru 1.4 (212)".
    var appVersion: String
    var exportedAt: Int64
    var sessions: [PiruSessionData]
    /// Doses not assigned to any session (defensive; normally empty).
    var orphanDoses: [PiruDoseData]
    var dailyDoseItems: [PiruDailyDoseData]
    var substanceColors: [PiruColorData]
    var userColors: [PiruUserColorData]
    var favorites: [PiruFavoriteData]
    var customSubstances: [PsyLogCustomSubstance]
}

private nonisolated struct PiruSessionData: Codable {
    var id: UUID
    var startDate: Int64
    var title: String?
    var note: String?
    var doses: [PiruDoseData]
}

private nonisolated struct PiruDoseData: Codable {
    var substance: String
    var amount: Double
    var unit: String
    var route: RouteOfAdministration
    var timestamp: Int64
    var notes: String?
    var tags: [String]
    var isBackgroundMed: Bool
    var locationName: String?
    var latitude: Double?
    var longitude: Double?
}

private nonisolated struct PiruDailyDoseData: Codable {
    var substance: String
    var amount: Double
    var unit: String
    var route: RouteOfAdministration
    var sortOrder: Int
    var category: String
    var isBackgroundMed: Bool
    var frequencyRaw: String
    var frequencyDays: [Int]
    var startDate: Int64
}

private nonisolated struct PiruColorData: Codable {
    var substance: String
    var hexColor: String
}

private nonisolated struct PiruUserColorData: Codable {
    var hex: String
    var name: String
    var createdAt: Int64
}

private nonisolated struct PiruFavoriteData: Codable {
    var substance: String
    var createdAt: Int64
}

// MARK: - Export / Import

/// The two on-disk shapes Piru can write.
enum ExportFormat: Equatable {
    /// Piru-native, lossless (sessions, per-dose location, background flags, …).
    case piru
    /// PsychonautWiki's modern interchange format — importable by PW, but lossy
    /// for Piru-only fields.
    case psyLog
}

enum DataExportImport {
    // MARK: Export

    /// Build the export `Data` synchronously on the main actor. Used by the
    /// backup manager and tests; the UI uses
    /// ``exportJSONInBackground(format:context:customStore:)`` so the encode of a
    /// large library doesn't block the main thread behind no spinner.
    @MainActor
    static func exportJSON(
        format: ExportFormat = .piru,
        context: ModelContext,
        customStore: CustomSubstanceStore = .shared,
    ) throws -> Data {
        switch format {
        case .piru: try encodeJSON(makePiruFile(context: context, customStore: customStore))
        case .psyLog: try encodeJSON(makePsyLogFile(context: context))
        }
    }

    /// Gather on the main actor, then encode off it. Lets the caller show a
    /// spinner that actually animates while the heavy `JSONEncoder` work runs on
    /// a background task.
    @MainActor
    static func exportJSONInBackground(
        format: ExportFormat,
        context: ModelContext,
        customStore: CustomSubstanceStore = .shared,
    ) async throws -> Data {
        switch format {
        case .piru:
            let file = try makePiruFile(context: context, customStore: customStore)
            return try await Task.detached(priority: .userInitiated) { try encodeJSON(file) }.value
        case .psyLog:
            let file = try makePsyLogFile(context: context)
            return try await Task.detached(priority: .userInitiated) { try encodeJSON(file) }.value
        }
    }

    private nonisolated static func encodeJSON(_ value: some Encodable & Sendable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private static var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Piru \(version) (\(build))"
    }

    // MARK: PsychonautWiki (PsyLog) gathering

    /// Build the PsychonautWiki modern file. Doses are grouped by **session** so
    /// a Piru session becomes a PsyLog "experience" carrying its title and note;
    /// session-less doses (defensive) fall back to one experience per day.
    @MainActor
    private static func makePsyLogFile(context: ModelContext) throws -> PsyLogFile {
        let entries = try context.fetch(FetchDescriptor<DoseEntry>())
        let colors = try context.fetch(FetchDescriptor<SubstanceColor>())

        let titleFormatter = DateFormatter()
        titleFormatter.dateFormat = "d MMM yyyy"
        titleFormatter.locale = Locale(identifier: "en_US")
        let calendar = Calendar.current

        var groups: [(title: String, note: String, start: Date, doses: [DoseEntry])] = []
        for (session, doses) in Dictionary(grouping: entries, by: { $0.session }) {
            let sorted = doses.sorted { $0.timestamp < $1.timestamp }
            if let session {
                groups.append((
                    title: session.title ?? titleFormatter.string(from: session.startDate),
                    note: session.note ?? "",
                    start: session.startDate,
                    doses: sorted,
                ))
            } else {
                for (day, dayDoses) in Dictionary(grouping: sorted, by: { calendar.sessionDayStart(for: $0.timestamp) }) {
                    groups.append((title: titleFormatter.string(from: day), note: "", start: day, doses: dayDoses))
                }
            }
        }
        groups.sort { $0.start < $1.start }

        let experiences = groups.map { group -> PsyLogExperience in
            let ingestions = group.doses.map { entry -> PsyLogIngestion in
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
            let startMs = (group.doses.first?.timestamp ?? group.start).msSince1970
            return PsyLogExperience(
                title: group.title,
                text: group.note,
                creationDate: startMs,
                sortDate: startMs,
                location: group.doses.lazy.compactMap(psyLogLocation).first,
                ingestions: ingestions,
            )
        }

        let companions = colors.map {
            PsyLogCompanion(color: PsyLogColorMap.name(from: $0.hexColor), substanceName: $0.substance)
        }
        return PsyLogFile(experiences: experiences, companions: companions)
    }

    // MARK: Piru native gathering

    @MainActor
    private static func makePiruFile(context: ModelContext, customStore: CustomSubstanceStore) throws -> PiruFile {
        let sessions = try context.fetch(FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startDate)]))
        let allEntries = try context.fetch(FetchDescriptor<DoseEntry>())
        let dailyDoses = try context.fetch(FetchDescriptor<DailyDoseItem>())
        let colors = try context.fetch(FetchDescriptor<SubstanceColor>())
        let userColors = try context.fetch(FetchDescriptor<UserColor>())
        let favorites = try context.fetch(FetchDescriptor<FavoriteSubstance>())

        func doseData(_ e: DoseEntry) -> PiruDoseData {
            PiruDoseData(
                substance: e.substance, amount: e.amount, unit: e.unit, route: e.route,
                timestamp: e.timestamp.msSince1970, notes: e.notes, tags: e.tags,
                isBackgroundMed: e.isBackgroundMed,
                locationName: e.locationName, latitude: e.latitude, longitude: e.longitude,
            )
        }

        let sessionData = sessions.map { session in
            PiruSessionData(
                id: session.id, startDate: session.startDate.msSince1970,
                title: session.title, note: session.note,
                doses: session.orderedDoses.map(doseData),
            )
        }
        let orphans = allEntries
            .filter { $0.session == nil }
            .sorted { $0.timestamp < $1.timestamp }
            .map(doseData)

        let daily = dailyDoses.map { item in
            PiruDailyDoseData(
                substance: item.substance, amount: item.amount, unit: item.unit, route: item.route,
                sortOrder: item.sortOrder, category: item.category, isBackgroundMed: item.isBackgroundMed,
                frequencyRaw: item.frequencyRaw, frequencyDays: item.frequencyDays,
                startDate: item.startDate.msSince1970,
            )
        }

        return PiruFile(
            piruExportVersion: 1,
            appVersion: appVersionString,
            exportedAt: Date.now.msSince1970,
            sessions: sessionData,
            orphanDoses: orphans,
            dailyDoseItems: daily,
            substanceColors: colors.map { PiruColorData(substance: $0.substance, hexColor: $0.hexColor) },
            userColors: userColors.map { PiruUserColorData(hex: $0.hex, name: $0.name, createdAt: $0.createdAt.msSince1970) },
            favorites: favorites.map { PiruFavoriteData(substance: $0.substance, createdAt: $0.createdAt.msSince1970) },
            customSubstances: customStore.all.map(PsyLogCustomSubstance.init),
        )
    }

    /// Detects the file shape and routes to the right importer:
    /// - `piruExportVersion` → Piru-native (lossless).
    /// - `experiences` → PsychonautWiki, both the modern (`exportSource`
    ///   present) and the old (`customSubstances` present, no `exportSource`)
    ///   shapes; ``importPsyLog`` decodes both leniently.
    /// - otherwise → Piru's own early `doseEntries` backup format.
    @MainActor
    static func importJSON(data: Data, context: ModelContext, customStore: CustomSubstanceStore = .shared) throws {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if json?["piruExportVersion"] != nil {
            try importPiruNative(data: data, context: context, customStore: customStore)
        } else if json?["experiences"] != nil {
            try importPsyLog(data: data, context: context, customStore: customStore)
        } else {
            try importLegacy(data: data, context: context)
        }
        // Cluster any session-less imports (PsyLog/legacy) into sessions. The
        // native importer assigns its own sessions, so this is a no-op for it.
        SessionService.assignUnassignedDoses(in: context)
    }

    @MainActor
    private static func importPsyLog(data: Data, context: ModelContext, customStore: CustomSubstanceStore) throws {
        let file = try JSONDecoder().decode(PsyLogFile.self, from: data)
        importCustomSubstances(file.customSubstances, into: customStore)

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
            var sessionDoses: [DoseEntry] = []
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
                // A dose's own location (a Piru extension, present only in older
                // Piru PsyLog exports) wins; otherwise inherit the experience's
                // location. PsychonautWiki stores location per experience, so we
                // copy it onto every dose to fit Piru's per-dose model.
                let location = ingestion.location ?? experience.location
                let entry = DoseEntry(
                    substance: name,
                    amount: dose,
                    unit: ingestion.units,
                    route: route,
                    timestamp: timestamp,
                    notes: ingestion.notes.isEmpty ? nil : ingestion.notes,
                    tags: extractedTags,
                    locationName: location?.name,
                    latitude: location?.latitude,
                    longitude: location?.longitude,
                )
                context.insert(entry)
                sessionDoses.append(entry)
            }

            // Each PsychonautWiki experience becomes a Piru session, preserving
            // its grouping and carrying the custom title and notes across. Only
            // when it brought in at least one new (non-duplicate) dose, so a
            // re-import doesn't accumulate empty sessions.
            guard !sessionDoses.isEmpty else { continue }
            let start = sessionDoses.map(\.timestamp).min() ?? Date(ms: experience.sortDate)
            let session = Session(
                startDate: start,
                title: experience.title.isEmpty ? nil : experience.title,
                note: experience.text.isEmpty ? nil : experience.text,
            )
            context.insert(session)
            for dose in sessionDoses {
                dose.session = session
            }
            session.refreshStartDate()
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

    // MARK: Piru native import

    @MainActor
    private static func importPiruNative(data: Data, context: ModelContext, customStore: CustomSubstanceStore) throws {
        let file = try JSONDecoder().decode(PiruFile.self, from: data)
        importCustomSubstances(file.customSubstances, into: customStore)

        // Dedup doses by content against what's already stored and within the
        // file, so a re-import (or merge) stays idempotent.
        let existingDoses = (try? context.fetch(FetchDescriptor<DoseEntry>())) ?? []
        var seen = Set(existingDoses.map {
            doseDedupKey(substance: $0.substance, timestamp: $0.timestamp, amount: $0.amount, unit: $0.unit, route: $0.route)
        })

        func makeDose(_ d: PiruDoseData) -> DoseEntry? {
            let timestamp = Date(ms: d.timestamp)
            let key = doseDedupKey(substance: d.substance, timestamp: timestamp, amount: d.amount, unit: d.unit, route: d.route)
            guard seen.insert(key).inserted else { return nil }
            let entry = DoseEntry(
                substance: d.substance, amount: d.amount, unit: d.unit, route: d.route,
                timestamp: timestamp, notes: d.notes, tags: d.tags, isBackgroundMed: d.isBackgroundMed,
                locationName: d.locationName, latitude: d.latitude, longitude: d.longitude,
            )
            context.insert(entry)
            return entry
        }

        // Recreate sessions with their original id/title/note; reuse an existing
        // session row if one already carries that id (merge-safe).
        let existingSessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        var sessionsByID = Dictionary(existingSessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for sessionData in file.sessions {
            let doses = sessionData.doses.compactMap(makeDose)
            guard !doses.isEmpty || sessionsByID[sessionData.id] == nil else { continue }
            let session: Session
            if let existing = sessionsByID[sessionData.id] {
                session = existing
            } else {
                session = Session(
                    id: sessionData.id,
                    startDate: Date(ms: sessionData.startDate),
                    title: sessionData.title,
                    note: sessionData.note,
                )
                context.insert(session)
                sessionsByID[sessionData.id] = session
            }
            for dose in doses {
                dose.session = session
            }
            session.refreshStartDate()
        }

        // Session-less doses (defensive) are left unassigned; importJSON's
        // clustering pass groups them afterwards.
        for orphan in file.orphanDoses {
            _ = makeDose(orphan)
        }

        // Colours — skip substances that already have one.
        var importedColors = Set(((try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []).map { $0.substance.lowercased() })
        for color in file.substanceColors where importedColors.insert(color.substance.lowercased()).inserted {
            context.insert(SubstanceColor(substance: color.substance, hexColor: color.hexColor))
        }

        // User-defined palette colours — dedup by hex.
        let existingUserHexes = Set(((try? context.fetch(FetchDescriptor<UserColor>())) ?? []).map { $0.hex.uppercased() })
        for uc in file.userColors where !existingUserHexes.contains(uc.hex.uppercased()) {
            let color = UserColor(hex: uc.hex, name: uc.name)
            color.createdAt = Date(ms: uc.createdAt)
            context.insert(color)
        }

        // Favourites — dedup by substance.
        let existingFavs = Set(((try? context.fetch(FetchDescriptor<FavoriteSubstance>())) ?? []).map { $0.substance.lowercased() })
        for fav in file.favorites where !existingFavs.contains(fav.substance.lowercased()) {
            context.insert(FavoriteSubstance(substance: fav.substance))
        }

        // Daily-dose items — dedup by substance, restoring the full schedule.
        let existingDailyNames = Set(((try? context.fetch(FetchDescriptor<DailyDoseItem>())) ?? []).map { $0.substance.lowercased() })
        for item in file.dailyDoseItems where !existingDailyNames.contains(item.substance.lowercased()) {
            context.insert(DailyDoseItem(
                substance: item.substance, amount: item.amount, unit: item.unit, route: item.route,
                sortOrder: item.sortOrder, category: item.category,
                frequency: DoseFrequency(rawValue: item.frequencyRaw) ?? .daily,
                frequencyDays: item.frequencyDays, startDate: Date(ms: item.startDate),
                isBackgroundMed: item.isBackgroundMed,
            ))
        }
    }

    /// Merge imported custom substances into the store: add new ones, update
    /// same-name matches (keeping the existing row's UUID), skip exact dupes.
    private static func importCustomSubstances(_ list: [PsyLogCustomSubstance], into customStore: CustomSubstanceStore) {
        var existingByName: [String: CustomSubstanceEntry] = Dictionary(
            customStore.all.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first },
        )
        for imported in list {
            let incoming = imported.asEntry
            let key = incoming.name.lowercased()
            if let existing = existingByName[key] {
                guard existing != incoming else { continue }
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

    /// Content-based identity for a dose entry, used to skip duplicates on
    /// import. Lowercased substance/unit so cosmetic casing differences don't
    /// defeat it; millisecond timestamp matches the export precision.
    /// A dose's location as the exportable shape, or `nil` unless it has both a
    /// name and a coordinate.
    private static func psyLogLocation(for entry: DoseEntry) -> PsyLogLocation? {
        guard let name = entry.locationName, let lat = entry.latitude, let lng = entry.longitude else { return nil }
        return PsyLogLocation(name: name, latitude: lat, longitude: lng)
    }

    private static func doseDedupKey(substance: String, timestamp: Date, amount: Double, unit: String, route: RouteOfAdministration) -> String {
        "\(substance.lowercased())|\(timestamp.msSince1970)|\(amount)|\(unit.lowercased())|\(route.rawValue)"
    }

    static func deleteAll(context: ModelContext) throws {
        try context.delete(model: DoseEntry.self)
        try context.delete(model: Session.self)
        try context.delete(model: DailyDoseItem.self)
        try context.delete(model: SubstanceColor.self)
        try context.delete(model: UserColor.self)
        try context.delete(model: FavoriteSubstance.self)
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
