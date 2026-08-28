import Foundation
import SwiftData

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
        nameToHex[name.uppercased()] ?? PresetColor.defaultHex
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
        // PsychonautWiki's journal `AdministrationRoute` has BUCCAL, so this
        // round-trips rather than degrading to ORAL.
        case .buccal: "BUCCAL"
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
        case "BUCCAL": self = .buccal
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

// MARK: - PsyLog Codable Types

nonisolated struct PsyLogFile: Codable {
    var experiences: [PsyLogExperience]
    var substanceCompanions: [PsyLogCompanion]
    var customUnits: [PsyLogCustomUnit]
    var customSubstances: [PiruCustomSubstanceData]
    var dailyDoseItems: [PsyLogDailyDoseItem]

    private enum CodingKeys: String, CodingKey {
        case experiences
        case substanceCompanions
        case customUnits
        case customSubstances
        case dailyDoseItems
        case exportSource
    }

    /// Stamped on export so PsychonautWiki recognizes the file as the modern
    /// format. PW's importer rejects files with no `exportSource` as "legacy".
    /// Verified: a file carrying this key (and none of Piru's own top-level
    /// keys) imports cleanly into the current PsychonautWiki Journal app.
    static let exportSourceValue = "iOS Journal 15.0"

    init(
        experiences: [PsyLogExperience],
        companions: [PsyLogCompanion],
        dailyDoseItems: [PsyLogDailyDoseItem] = [],
        customSubstances: [PiruCustomSubstanceData] = [],
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
        if let parsed = try? c.decodeIfPresent([PiruCustomSubstanceData].self, forKey: .customSubstances) {
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
/// Coordinates are optional to mirror PsychonautWiki's `LocationCodable` —
/// its users can name a location without attaching coordinates, and such
/// files must still import.
nonisolated struct PsyLogLocation: Codable {
    var name: String
    var latitude: Double?
    var longitude: Double?
}

nonisolated struct PsyLogExperience: Codable {
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
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        location = try c.decodeIfPresent(PsyLogLocation.self, forKey: .location)
        ingestions = try c.decodeIfPresent([PsyLogIngestion].self, forKey: .ingestions) ?? []
        // PsychonautWiki writes `sortDate: null` for experiences that never had
        // one, and its own importer falls back to the earliest ingestion — so
        // must we. Both dates are lenient: a missing one falls back to the
        // other, then to the earliest ingestion time.
        let decodedCreation = try c.decodeIfPresent(Int64.self, forKey: .creationDate)
        let decodedSort = try c.decodeIfPresent(Int64.self, forKey: .sortDate)
        let earliestIngestion = ingestions.map(\.time).min()
        creationDate = decodedCreation ?? decodedSort ?? earliestIngestion ?? 0
        sortDate = decodedSort ?? earliestIngestion ?? creationDate
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

nonisolated struct PsyLogIngestion: Codable {
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

nonisolated struct PsyLogCompanion: Codable {
    var color: String
    var substanceName: String
}

nonisolated struct PsyLogDailyDoseItem: Codable {
    var substance: String
    var amount: Double
    var unit: String
    var route: String
    var sortOrder: Int
}

nonisolated struct PsyLogCustomUnit: Codable {
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

// MARK: - PsyLog Export / Import

extension DataExportImport {
    /// Build the PsychonautWiki modern file. Doses are grouped by **session** so
    /// a Piru session becomes a PsyLog "experience" carrying its title and note;
    /// session-less doses (defensive) fall back to one experience per day.
    @MainActor
    static func makePsyLogFile(context: ModelContext) throws -> PsyLogFile {
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

    /// A dose's location as the exportable shape, or `nil` if it has no name.
    /// Coordinates are carried when present; a name-only location still
    /// round-trips (PsychonautWiki's shape allows coordinate-less locations).
    private static func psyLogLocation(for entry: DoseEntry) -> PsyLogLocation? {
        guard let name = entry.locationName else { return nil }
        return PsyLogLocation(name: name, latitude: entry.latitude, longitude: entry.longitude)
    }

    @MainActor
    static func importPsyLog(data: Data, context: ModelContext, customStore: CustomSubstanceStore) throws {
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
            session.refreshDoseBounds()
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
}
