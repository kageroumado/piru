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

    /// The PsyLog color nearest `tint`, by Oklab distance. PsyLog stores a
    /// name from its fixed palette, so any Piru color exports as the closest
    /// one it has.
    static func name(nearest tint: P3Color) -> String {
        let target = oklab(Oklch(displayP3: tint))
        var closest = "BLUE"
        var minDistance = Double.greatestFiniteMagnitude
        for (name, hex) in nameToHex {
            let candidate = oklab(Oklch(displayP3: LegacyColorImport.p3(fromSRGBHex: hex)))
            let distance = pow(target.l - candidate.l, 2) + pow(target.a - candidate.a, 2) + pow(target.b - candidate.b, 2)
            if distance < minDistance { minDistance = distance; closest = name }
        }
        return closest
    }

    private static func oklab(_ color: Oklch) -> (l: Double, a: Double, b: Double) {
        let radians = color.h * .pi / 180
        return (color.l, color.c * cos(radians), color.c * sin(radians))
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

/// PsychonautWiki's timed note (`TimedNoteCodable`): a free-text note pinned to a
/// moment inside an experience. `color` is one of PW's named substance colors and
/// `isPartOfTimeline` whether PW draws it on its graph; Piru writes `blue` and
/// `true` and reads neither back.
nonisolated struct PsyLogTimedNote: Codable {
    var creationDate: Int64
    var time: Int64
    var note: String
    var color: String
    var isPartOfTimeline: Bool

    init(time: Int64, note: String, creationDate: Int64? = nil) {
        self.time = time
        self.note = note
        self.creationDate = creationDate ?? time
        color = "blue"
        isPartOfTimeline = true
    }

    private enum CodingKeys: String, CodingKey {
        case creationDate
        case time
        case note
        case color
        case isPartOfTimeline
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        time = try c.decode(Int64.self, forKey: .time)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        creationDate = try c.decodeIfPresent(Int64.self, forKey: .creationDate) ?? time
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "blue"
        isPartOfTimeline = try c.decodeIfPresent(Bool.self, forKey: .isPartOfTimeline) ?? true
    }
}

nonisolated struct PsyLogExperience: Codable {
    var title: String
    var isFavorite: Bool
    var creationDate: Int64
    var sortDate: Int64
    var text: String
    var location: PsyLogLocation?
    var ingestions: [PsyLogIngestion]
    var timedNotes: [PsyLogTimedNote]

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

    init(title: String, text: String = "", creationDate: Int64, sortDate: Int64, location: PsyLogLocation? = nil, ingestions: [PsyLogIngestion], timedNotes: [PsyLogTimedNote] = []) {
        self.title = title
        self.isFavorite = false
        self.creationDate = creationDate
        self.sortDate = sortDate
        self.text = text
        self.location = location
        self.ingestions = ingestions
        self.timedNotes = timedNotes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        location = try c.decodeIfPresent(PsyLogLocation.self, forKey: .location)
        ingestions = try c.decodeIfPresent([PsyLogIngestion].self, forKey: .ingestions) ?? []
        // Older Piru exports wrote `timedNotes: []` as a string-array placeholder;
        // anything that isn't PW's object shape reads as no notes.
        timedNotes = (try? c.decodeIfPresent([PsyLogTimedNote].self, forKey: .timedNotes)) ?? []
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
        try c.encode(timedNotes, forKey: .timedNotes)
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
    /// Who took the dose: `nil` for the file's owner, otherwise the name the
    /// journal gave that person. Whitespace-only names read as the owner.
    var consumerName: String?
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

    init(
        substanceName: String,
        dose: Double?,
        time: Int64,
        route: String,
        notes: String,
        units: String,
        consumerName: String? = nil,
        location: PsyLogLocation? = nil,
    ) {
        self.substanceName = substanceName
        self.customUnitId = nil
        self.dose = dose
        self.time = time
        self.administrationRoute = route
        self.notes = notes
        self.units = units
        self.consumerName = consumerName
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
        let consumer = (try? c.decodeIfPresent(String.self, forKey: .consumerName))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        consumerName = consumer?.isEmpty == false ? consumer : nil
        location = try c.decodeIfPresent(PsyLogLocation.self, forKey: .location)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeNil(forKey: .customUnitId)
        try c.encode(time, forKey: .creationDate)
        if let consumerName {
            try c.encode(consumerName, forKey: .consumerName)
        } else {
            try c.encodeNil(forKey: .consumerName)
        }
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

// MARK: - PsyLog Export

/// One journal in a PsyLog export, and the `consumerName` its doses carry:
/// `nil` for the profile exporting, the person's name for anyone else.
struct PsyLogPerson {
    let name: String?
    let context: ModelContext
}

/// One PsyLog experience being assembled: a session, a day of session-less
/// doses, or, across people, every session sharing one `sharedExperienceID`.
private struct PsyLogExportGroup {
    /// The first participating session's title; `nil` titles it by its date.
    var title: String?
    var note: String
    var start: Date
    var doses: [(entry: DoseEntry, consumer: String?)]
    var notes: [SessionNote]

    mutating func merge(_ other: PsyLogExportGroup) {
        title = title ?? other.title
        if note.isEmpty { note = other.note }
        start = min(start, other.start)
        doses += other.doses
        notes += other.notes
    }
}

extension DataExportImport {
    /// This profile's journal as a PsychonautWiki file, every dose unnamed.
    @MainActor
    static func makePsyLogFile(context: ModelContext) throws -> PsyLogFile {
        try makePsyLogFile(people: [PsyLogPerson(name: nil, context: context)])
    }

    /// Build the PsychonautWiki modern file. Doses are grouped by **session** so
    /// a Piru session becomes a PsyLog "experience" carrying its title and note;
    /// session-less doses (defensive) fall back to one experience per day.
    ///
    /// With more than one person, each dose names its taker (``PsyLogPerson``),
    /// and sessions that share a `sharedExperienceID` become one experience
    /// holding everyone's doses, titled by the first of them that has a title.
    @MainActor
    static func makePsyLogFile(people: [PsyLogPerson]) throws -> PsyLogFile {
        var groups: [PsyLogExportGroup] = []
        var sharedGroups: [UUID: Int] = [:]
        var companions: [PsyLogCompanion] = []
        var companionNames: Set<String> = []
        for person in people {
            for group in try psyLogGroups(for: person) {
                if people.count > 1, let shared = group.shared {
                    if let index = sharedGroups[shared] {
                        groups[index].merge(group.group)
                        continue
                    }
                    sharedGroups[shared] = groups.count
                }
                groups.append(group.group)
            }
            for color in try person.context.fetch(FetchDescriptor<SubstanceColor>())
                where companionNames.insert(color.substance.lowercased()).inserted {
                companions.append(PsyLogCompanion(color: PsyLogColorMap.name(nearest: color.tint), substanceName: color.substance))
            }
        }
        groups.sort { $0.start < $1.start }

        let titleFormatter = DateFormatter()
        titleFormatter.dateFormat = "d MMM yyyy"
        titleFormatter.locale = Locale(identifier: "en_US")
        return PsyLogFile(
            experiences: groups.map { psyLogExperience(for: $0, title: $0.title ?? titleFormatter.string(from: $0.start)) },
            companions: companions,
        )
    }

    /// One person's doses grouped into experiences, each with the shared
    /// experience its session belongs to.
    @MainActor
    private static func psyLogGroups(for person: PsyLogPerson) throws -> [(group: PsyLogExportGroup, shared: UUID?)] {
        let calendar = Calendar.current
        let entries = try person.context.fetch(FetchDescriptor<DoseEntry>())
        var groups: [(group: PsyLogExportGroup, shared: UUID?)] = []
        for (session, doses) in Dictionary(grouping: entries, by: { $0.session }) {
            let sorted = doses.sorted { $0.timestamp < $1.timestamp }
            if let session {
                groups.append((PsyLogExportGroup(
                    title: session.title,
                    note: session.note ?? "",
                    start: session.startDate,
                    doses: sorted.map { ($0, person.name) },
                    // The summary already rides in `text`; PW's timed notes carry the
                    // rest of the timeline.
                    notes: session.orderedNotes.filter { $0.kind != .summary },
                ), session.sharedExperienceID))
            } else {
                for (day, dayDoses) in Dictionary(grouping: sorted, by: { calendar.sessionDayStart(for: $0.timestamp) }) {
                    groups.append((
                        PsyLogExportGroup(title: nil, note: "", start: day, doses: dayDoses.map { ($0, person.name) }, notes: []),
                        nil,
                    ))
                }
            }
        }
        return groups
    }

    @MainActor
    private static func psyLogExperience(for group: PsyLogExportGroup, title: String) -> PsyLogExperience {
        let doses = group.doses.sorted { $0.entry.timestamp < $1.entry.timestamp }
        let ingestions = doses.map { dose -> PsyLogIngestion in
            let entry = dose.entry
            var noteText = entry.notes ?? ""
            if !entry.tags.isEmpty {
                let tagStr = entry.tags.map { "#\($0)" }.joined(separator: " ")
                noteText = noteText.isEmpty ? tagStr : "\(noteText) \(tagStr)"
            }
            return PsyLogIngestion(
                substanceName: entry.substance,
                // PW's own shape for a dose taken without knowing how much.
                dose: entry.isUnknownDose ? nil : entry.amount,
                time: entry.timestamp.msSince1970,
                route: entry.route.psylogName,
                notes: noteText,
                units: entry.unit,
                consumerName: dose.consumer,
            )
        }
        let startMs = (doses.first?.entry.timestamp ?? group.start).msSince1970
        return PsyLogExperience(
            title: title,
            text: group.note,
            creationDate: startMs,
            sortDate: startMs,
            location: doses.lazy.compactMap { psyLogLocation(for: $0.entry) }.first,
            ingestions: ingestions,
            // PW has one text field per note, so the structure (rating, mood,
            // energy, descriptors) is flattened into the line — the native
            // format keeps the fields.
            timedNotes: group.notes.sorted { $0.timestamp < $1.timestamp }.map { note in
                PsyLogTimedNote(time: note.timestamp.msSince1970, note: TripReport.flattenedLine(for: note))
            },
        )
    }

    /// A dose's location as the exportable shape, or `nil` if it has no name.
    /// Coordinates are carried when present; a name-only location still
    /// round-trips (PsychonautWiki's shape allows coordinate-less locations).
    private static func psyLogLocation(for entry: DoseEntry) -> PsyLogLocation? {
        guard let name = entry.locationName else { return nil }
        return PsyLogLocation(name: name, latitude: entry.latitude, longitude: entry.longitude)
    }
}

// MARK: - PsyLog Import

/// One profile's store during a PsyLog import: what it already holds, so each
/// store dedups against its own journal and nobody else's.
@MainActor
private final class PsyLogStoreImport {
    let profile: UUID
    let context: ModelContext
    var doseIndex: ImportedDoseIndex
    /// Stored doses on route Other, keyed as if the file's dose were Other too.
    /// An earlier build filed PW's SMOKED as Other; when the same file comes
    /// in again, its dose names the real route, so the stored copy takes that
    /// route instead of a second copy landing beside it.
    var unroutedDoses: [String: [DoseEntry]]

    init(profile: UUID, context: ModelContext) {
        self.profile = profile
        self.context = context
        let existing = (try? context.fetch(FetchDescriptor<DoseEntry>())) ?? []
        doseIndex = ImportedDoseIndex(existing)
        unroutedDoses = Dictionary(grouping: existing.filter { $0.route == .other }) {
            DataExportImport.doseDedupKey(for: $0, route: .other)
        }
    }
}

/// One profile's part of one experience: the doses it adds, and the session
/// already holding doses it repeats, so a re-import lands its notes there.
@MainActor
private struct PsyLogExperiencePart {
    var doses: [DoseEntry] = []
    var matched: Session?
}

/// A store other than the importing context's that a PsyLog import wrote
/// into, which ``DataExportImport/importJSON(data:context:customStore:mode:settings:psyLogRouting:)``
/// finishes and commits under that profile's scope.
@MainActor
struct PsyLogImportedStore {
    let profile: UUID
    let context: ModelContext
}

extension DataExportImport {
    /// Adds the experience's timed notes to `session`, skipping any it already
    /// holds at the same moment, whether as the same text or as the structured
    /// note that exported as that line.
    @MainActor
    private static func importTimedNotes(_ timedNotes: [PsyLogTimedNote], into session: Session, context: ModelContext) {
        var held = Set((session.notes ?? []).flatMap { note in
            let ms = note.timestamp.msSince1970
            return ["\(ms)|\(note.text.trimmingCharacters(in: .whitespacesAndNewlines))", "\(ms)|\(TripReport.flattenedLine(for: note))"]
        })
        for timed in timedNotes {
            let text = timed.note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, held.insert("\(timed.time)|\(text)").inserted else { continue }
            context.insert(SessionNote(timestamp: Date(ms: timed.time), text: text, session: session))
        }
    }

    /// Imports a PsychonautWiki file into `context`'s journal and, with a
    /// `routing` that maps the file's named people to profiles, each person's
    /// doses into that profile's store. Without one, only the file owner's
    /// unnamed doses import. Returns the other stores written into, unsaved.
    @MainActor
    @discardableResult
    static func importPsyLog(
        data: Data,
        context: ModelContext,
        customStore: CustomSubstanceStore,
        routing: PsyLogRouting? = nil,
    ) throws -> [PsyLogImportedStore] {
        let file = try JSONDecoder().decode(PsyLogFile.self, from: data)
        let routing = routing ?? .ownerOnly()
        importCustomSubstances(file.customSubstances, into: customStore)

        // Build custom unit lookup: id -> custom unit
        let customUnitMap = Dictionary(file.customUnits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Dedup dose entries against what each store already holds (and within
        // this import) so a merge restore — or re-importing the same file —
        // stays idempotent instead of multiplying every dose. `DoseEntry` has
        // no natural id, so the key is its content: substance, time, dose,
        // unit, route.
        var stores: [UUID: PsyLogStoreImport] = [routing.owner: PsyLogStoreImport(profile: routing.owner, context: context)]
        var storeOrder: [UUID] = [routing.owner]
        func store(for profile: UUID) -> PsyLogStoreImport? {
            if let open = stores[profile] { return open }
            guard let other = routing.context(for: profile) else { return nil }
            let opened = PsyLogStoreImport(profile: profile, context: other)
            stores[profile] = opened
            storeOrder.append(profile)
            return opened
        }

        for experience in file.experiences {
            var parts: [UUID: PsyLogExperiencePart] = [:]
            var partOrder: [UUID] = []
            for ingestion in experience.ingestions {
                guard let profile = routing.profile(forConsumer: ingestion.consumerName),
                      let target = store(for: profile) else { continue }
                if parts[profile] == nil { partOrder.append(profile) }
                var part = parts[profile] ?? PsyLogExperiencePart()
                importIngestion(ingestion, of: experience, customUnits: customUnitMap, into: target, part: &part)
                parts[profile] = part
            }
            importSessions(of: experience, parts: parts, order: partOrder, owner: routing.owner, stores: stores)
        }

        // PsyLog makes every substance carry one of its palette names; those
        // are dropped in favor of Piru's class colors, so an import doesn't
        // arrive as a list of "custom" colors the user never chose here.
        var colorRows = (try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []
        for name in file.substanceCompanions.map(\.substanceName) {
            if let row = SubstanceColorStore.ensureRow(for: name, existing: colorRows, in: context) {
                colorRows.append(row)
            }
        }

        // Import daily dose items, skip duplicates by substance name. The
        // file's routine belongs to its owner.
        if !file.dailyDoseItems.isEmpty {
            let existing = (try? context.fetch(FetchDescriptor<DailyDoseItem>())) ?? []
            let existingNames = Set(existing.map { $0.substance.lowercased() })

            for item in file.dailyDoseItems {
                guard !existingNames.contains(item.substance.lowercased()) else { continue }
                context.insert(DailyDoseItem(
                    substance: item.substance,
                    amount: item.amount,
                    unit: item.unit,
                    route: RouteOfAdministration.from(string: item.route),
                    sortOrder: item.sortOrder,
                ))
            }
        }
        return storeOrder.dropFirst().compactMap { profile in
            stores[profile].map { PsyLogImportedStore(profile: profile, context: $0.context) }
        }
    }

    /// Inserts one ingestion into `store`, unless the store already holds it.
    @MainActor
    private static func importIngestion(
        _ ingestion: PsyLogIngestion,
        of experience: PsyLogExperience,
        customUnits: [Int: PsyLogCustomUnit],
        into store: PsyLogStoreImport,
        part: inout PsyLogExperiencePart,
    ) {
        // Resolve substance name: prefer direct name, fall back to custom unit
        let name: String
        if let directName = ingestion.substanceName {
            name = directName
        } else if let cuId = ingestion.customUnitId, let cu = customUnits[cuId] {
            name = cu.name
        } else {
            return
        }

        // PW writes `dose: null` for a dose taken without knowing how
        // much, which lands as an unknown dose. A zero is no dose at all.
        let dose = ingestion.dose
        if let dose, dose <= 0 { return }

        // The shared parser, never a table of this importer's own: PW
        // writes SMOKED beside INHALED (and PsyLog files carry the same
        // vocabulary), and a local table that missed one filed every
        // such dose as Other.
        let route = RouteOfAdministration.from(string: ingestion.administrationRoute)
        let timestamp = Date(ms: ingestion.time)
        let key = doseDedupKey(substance: name, timestamp: timestamp, amount: dose, unit: ingestion.units, route: route)
        if case let .duplicate(stored) = store.doseIndex.claim(key) {
            part.matched = part.matched ?? stored?.session
            return
        }
        if route != .other {
            let unroutedKey = doseDedupKey(substance: name, timestamp: timestamp, amount: dose, unit: ingestion.units, route: .other)
            if let stored = store.unroutedDoses[unroutedKey]?.popLast() {
                stored.route = route
                part.matched = part.matched ?? stored.session
                return
            }
        }

        let extractedTags = TagExtractor.extractTags(from: ingestion.notes)
        // A dose's own location (a Piru extension, present only in older
        // Piru PsyLog exports) wins; otherwise inherit the experience's
        // location. PsychonautWiki stores location per experience, so we
        // copy it onto every dose to fit Piru's per-dose model.
        let location = ingestion.location ?? experience.location
        let entry = DoseEntry(
            substance: name,
            amount: dose ?? 0,
            unit: ingestion.units,
            route: route,
            timestamp: timestamp,
            timeZoneIdentifier: nil,
            notes: ingestion.notes.isEmpty ? nil : ingestion.notes,
            tags: extractedTags,
            locationName: location?.name,
            latitude: location?.latitude,
            longitude: location?.longitude,
            isUnknownDose: dose == nil,
        )
        store.context.insert(entry)
        part.doses.append(entry)
    }

    /// Each PsychonautWiki experience becomes one Piru session per profile
    /// taking part, carrying the title and text to each. A store that already
    /// holds the experience's doses adds no session; its notes go to the
    /// session holding those doses. Timed notes go to the owner's session, or
    /// the first profile's when the owner took nothing, and when more than one
    /// profile took part their sessions share one `sharedExperienceID`.
    @MainActor
    private static func importSessions(
        of experience: PsyLogExperience,
        parts: [UUID: PsyLogExperiencePart],
        order: [UUID],
        owner: UUID,
        stores: [UUID: PsyLogStoreImport],
    ) {
        let text = experience.text.trimmingCharacters(in: .whitespacesAndNewlines)
        var sessions: [(profile: UUID, session: Session)] = []
        for profile in order {
            guard let part = parts[profile], let store = stores[profile] else { continue }
            let session = ProfileScope.$pinned.withValue(profile) {
                importedSession(
                    doses: part.doses,
                    matched: part.matched,
                    title: experience.title.isEmpty ? nil : experience.title,
                    note: text.isEmpty ? nil : text,
                    context: store.context,
                )
            }
            if let session { sessions.append((profile, session)) }
        }
        if let holder = sessions.first(where: { $0.profile == owner }) ?? sessions.first,
           let store = stores[holder.profile] {
            importTimedNotes(experience.timedNotes, into: holder.session, context: store.context)
        }
        guard sessions.count > 1 else { return }
        let shared = sessions.lazy.compactMap(\.session.sharedExperienceID).first ?? UUID()
        for (_, session) in sessions where session.sharedExperienceID != shared {
            session.sharedExperienceID = shared
        }
    }
}
