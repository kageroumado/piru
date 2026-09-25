import Foundation
import SwiftData

// MARK: - Custom Substance Wire Type

/// Piru-native wire shape for a user-defined substance — part of ``PiruFile``,
/// **not** the PsyLog format (which carries no custom substances at all). Named
/// like its `Piru*Data` siblings. Mirrors ``CustomSubstanceEntry`` so Piru→Piru
/// round-trips preserve every field — display name, dose ladder, duration, and
/// half-life — which is what restores a user's personalization and the timeline
/// graph for substances the bundled library lacks data for. A genuine PsyLog
/// file omits this key entirely (or carries an empty string-array placeholder);
/// the file-level decoder treats both as "no customs".
nonisolated struct PiruCustomSubstanceData: Codable {
    var id: UUID
    var name: String
    var category: SubstanceCategory
    var defaultRoute: RouteOfAdministration
    var unit: String
    var notes: String
    var duration: DurationProfile?
    var createdAt: Int64
    // Personalization fields (v1.4). Optional, so synthesized `Codable` decodes
    // them as `nil` when absent — older files and cross-app PsyLog files that
    // never carried them still import. Previously these were *omitted entirely*
    // from the wire shape, so a user's personal label, dose ladder, and half-life
    // were silently dropped on every Piru→Piru round-trip and weren't backed up.
    var displayName: String?
    var doses: DoseRange?
    var halfLifeMinutes: Double?

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
        self.displayName = entry.displayName
        self.doses = entry.doses
        self.halfLifeMinutes = entry.halfLifeMinutes
    }

    @MainActor
    var asEntry: CustomSubstanceEntry {
        CustomSubstanceEntry(
            id: id,
            name: name,
            displayName: displayName,
            category: category,
            defaultRoute: defaultRoute,
            unit: unit,
            notes: notes,
            doses: doses,
            duration: duration,
            halfLifeMinutes: halfLifeMinutes,
            createdAt: Date(ms: createdAt),
        )
    }
}

// MARK: - Piru Native Wire Types

/// Piru's own export shape — a complete, lossless dump of the user's data,
/// including the things the PsyLog/PW format can't represent: session titles &
/// notes, per-dose location and background-med flag, real tag arrays,
/// favorites, picked colors, and daily-dose schedules. Detected on import by
/// the `piruExportVersion` key. Timestamps are epoch milliseconds, matching the
/// PsyLog format's convention.
nonisolated struct PiruFile: Codable {
    var piruExportVersion: Int
    /// The app version that produced the file, e.g. "Piru 1.4 (212)".
    var appVersion: String
    var exportedAt: Int64
    var sessions: [PiruSessionData]
    /// Doses not assigned to any session (defensive; normally empty).
    var orphanDoses: [PiruDoseData]
    var dailyDoseItems: [PiruDailyDoseData]
    /// Colors the user picked. A substance on its class color is absent: the
    /// importing device generates the same color for it.
    var substanceColors: [PiruColorData]
    var favorites: [PiruFavoriteData]
    var customSubstances: [PiruCustomSubstanceData]
    /// Optional for back-compat: files written before inventory tracking omit
    /// the key, which decodes to `nil` (treated as empty). Mirrors the
    /// `id`/`saltForm` optional-on-decode pattern the dose data uses.
    var inventory: [PiruInventoryData]?
    /// Optional for the same back-compat reason: absent from older files,
    /// which leaves the importing install's rows of that kind untouched.
    var labMeasurements: [PiruLabMeasurementData]?
    var customUnits: [PiruCustomUnitData]?
    var drinkPresets: [PiruDrinkPresetData]?
    var quickLogDoses: [PiruQuickLogDoseData]?
    var routineOccurrences: [PiruRoutineOccurrenceData]?
    var profile: PiruProfileData?
    var notificationPreferences: PiruNotificationPreferencesData?
    /// App preferences kept outside the store — see ``ExportedSettings``.
    var settings: PiruSettingsData?
}

extension PiruFile {
    /// Every section defaults to empty when its key is absent, so a file from a
    /// build that had no favorites, custom substances, or inventory yet, or one
    /// trimmed by hand, still imports what it does carry. The version stays
    /// required: without it the file is not a Piru export.
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        piruExportVersion = try c.decode(Int.self, forKey: .piruExportVersion)
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion) ?? "?"
        exportedAt = try c.decodeIfPresent(Int64.self, forKey: .exportedAt) ?? 0
        sessions = try c.decodeIfPresent([PiruSessionData].self, forKey: .sessions) ?? []
        orphanDoses = try c.decodeIfPresent([PiruDoseData].self, forKey: .orphanDoses) ?? []
        dailyDoseItems = try c.decodeIfPresent([PiruDailyDoseData].self, forKey: .dailyDoseItems) ?? []
        substanceColors = try c.decodeIfPresent([PiruColorData].self, forKey: .substanceColors) ?? []
        favorites = try c.decodeIfPresent([PiruFavoriteData].self, forKey: .favorites) ?? []
        customSubstances = try c.decodeIfPresent([PiruCustomSubstanceData].self, forKey: .customSubstances) ?? []
        inventory = try c.decodeIfPresent([PiruInventoryData].self, forKey: .inventory)
        labMeasurements = try c.decodeIfPresent([PiruLabMeasurementData].self, forKey: .labMeasurements)
        customUnits = try c.decodeIfPresent([PiruCustomUnitData].self, forKey: .customUnits)
        drinkPresets = try c.decodeIfPresent([PiruDrinkPresetData].self, forKey: .drinkPresets)
        quickLogDoses = try c.decodeIfPresent([PiruQuickLogDoseData].self, forKey: .quickLogDoses)
        routineOccurrences = try c.decodeIfPresent([PiruRoutineOccurrenceData].self, forKey: .routineOccurrences)
        profile = try c.decodeIfPresent(PiruProfileData.self, forKey: .profile)
        notificationPreferences = try c.decodeIfPresent(PiruNotificationPreferencesData.self, forKey: .notificationPreferences)
        settings = try c.decodeIfPresent(PiruSettingsData.self, forKey: .settings)
    }
}

nonisolated struct PiruSessionData: Codable {
    var id: UUID
    var startDate: Int64
    var title: String?
    var note: String?
    var doses: [PiruDoseData]
    /// Timestamped notes. Optional on decode so files written before session
    /// notes still import (they decode as `nil`, treated as none).
    var notes: [PiruSessionNoteData]?
    /// Check-in cadence (see ``Session/checkInIntervalMinutes``); optional for
    /// the same back-compat reason.
    var checkInIntervalMinutes: Double?
    /// Custom check-in times (``Session/checkInOffsetMinutes``) and whether the
    /// check-in offer was already shown; optional for the same reason.
    var checkInOffsetMinutes: [Int]?
    var checkInOffered: Bool?
}

/// Wire shape of one ``SessionNote``. `kind` is the raw `SessionNote.Kind`;
/// `descriptors` are SubFxOnEx concept ids exactly as stored.
nonisolated struct PiruSessionNoteData: Codable {
    var id: UUID
    var timestamp: Int64
    var text: String
    var shulgin: Int?
    var mood: Int?
    var energy: Int?
    var social: Int?
    var worked: Int?
    var descriptors: [String]
    var heartRate: Double?
    var kind: String

    init(_ note: SessionNote) {
        id = note.id
        timestamp = note.timestamp.msSince1970
        text = note.text
        shulgin = note.shulgin
        mood = note.mood
        energy = note.energy
        social = note.social
        worked = note.worked
        descriptors = note.descriptors
        heartRate = note.heartRate
        kind = note.kindRaw
    }
}

nonisolated struct PiruDoseData: Codable {
    /// The dose's stable ``DoseEntry/id``. Always emitted on export; optional
    /// on decode so files written before schema V4 still import (those doses
    /// get fresh UUIDs). Not the dedup key — that stays content-based
    /// (see ``DataExportImport/doseDedupKey``).
    var id: UUID?
    var substance: String
    var amount: Double
    var unit: String
    var route: RouteOfAdministration
    /// The salt/ester form logged (Magnesium Glycinate, Lithium Orotate…).
    /// Optional on both encode and decode — omitted for the vast majority of
    /// doses, and absent from files written before salt-form support, which
    /// import with `saltForm == nil` unchanged.
    var saltForm: String?
    /// PSID identity + the user's product word, carried so a backup→restore keeps
    /// a Concerta dose Concerta. All optional on both sides: omitted for a plain
    /// dose, and absent from files written before PSID (which import unresolved and
    /// self-heal via the launch backfill). `productName` especially must ride
    /// along — the backfill can recover the facets from the canonical name but not
    /// the brand word, which is gone once `substance` is canonical.
    var substanceUID: String?
    var isomer: String?
    var releaseForm: String?
    var productName: String?
    var displayNameSnapshot: String?
    var timestamp: Int64
    var notes: String?
    var tags: [String]
    var isBackgroundMed: Bool
    var locationName: String?
    var latitude: Double?
    var longitude: Double?
    /// The dose's amount qualifiers. Always emitted; optional on decode so files
    /// written before either flag existed import with both `false`.
    var isApproximate: Bool?
    var isUnknownDose: Bool?
    /// The grapefruit flag and a by-volume drink's detail. Optional on both
    /// sides: omitted for an ordinary dose, absent from older files.
    var hadGrapefruit: Bool?
    var volumeML: Double?
    var abv: Double?
    var drinkName: String?
}

nonisolated struct PiruDailyDoseData: Codable {
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
    /// PSID identity and the reminder model. Optional on decode, so an older
    /// file imports with the model's defaults.
    var substanceUID: String?
    var isomer: String?
    var releaseForm: String?
    var saltForm: String?
    var productName: String?
    var reminderTimesMinutes: [Int]?
    var remind: Bool?
    /// `nil` follows the global Ask Again default; `[]` opts out.
    var askAgainOverrideMinutes: [Int]?
    var isQuiet: Bool?
    var isAsNeeded: Bool?
    var maxPerDay: Int?
}

/// One picked color. Format 2 writes `p3`; format 1 files carry `hexColor`, an
/// sRGB hex, for every substance the exporting device had met.
nonisolated struct PiruColorData: Codable {
    var substance: String
    var p3: P3Color?
    var hexColor: String?

    var tint: P3Color? {
        p3 ?? hexColor.map(LegacyColorImport.p3(fromSRGBHex:))
    }
}

nonisolated struct PiruFavoriteData: Codable {
    var substance: String
    var createdAt: Int64
    /// Position and PSID identity; optional on decode for older files.
    var sortOrder: Int?
    var substanceUID: String?
    var isomer: String?
    var releaseForm: String?
    var saltForm: String?
    var productName: String?
}

/// Everything needed to reconstruct an inventory item's stock. `currentQuantity`
/// and `lowStockNotified` are intentionally omitted — both are derived/transient
/// and rebuilt by `recomputeAll` after import. `trackingStart` is preserved so
/// the dose-consumption window matches the source device exactly.
nonisolated struct PiruInventoryData: Codable {
    /// Stable id and manual list position; optional on decode, so an older
    /// file's item gets a fresh id at position 0.
    var id: UUID?
    var sortOrder: Int?
    var substance: String
    var saltForm: String?
    var unit: String
    var trackingStart: Int64
    var lowStockThreshold: Double?
    var baselineQuantity: Double?
    var doseSize: Double?
    var unitStrengthMG: Double?
    var createdAt: Int64
    var manualEvents: [PiruManualEventData]
}

nonisolated struct PiruManualEventData: Codable {
    var id: UUID
    var kind: String
    var amount: Double
    var date: Int64
    var note: String?
    var setsBaseline: Bool
}

// MARK: - Piru Native Export / Import

extension DataExportImport {
    private static var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Piru \(version) (\(build))"
    }

    @MainActor
    static func makePiruFile(
        context: ModelContext,
        customStore: CustomSubstanceStore,
        settings: SettingsScope,
    ) throws -> PiruFile {
        let sessions = try context.fetch(FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startDate)]))
        let allEntries = try context.fetch(FetchDescriptor<DoseEntry>())
        let dailyDoses = try context.fetch(FetchDescriptor<DailyDoseItem>())
        let colors = try context.fetch(FetchDescriptor<SubstanceColor>())
        let favorites = try context.fetch(FetchDescriptor<FavoriteSubstance>())
        let inventoryItems = try context.fetch(FetchDescriptor<InventoryItem>())

        func doseData(_ e: DoseEntry) -> PiruDoseData {
            PiruDoseData(
                id: e.id,
                substance: e.substance, amount: e.amount, unit: e.unit, route: e.route,
                saltForm: e.saltForm,
                substanceUID: e.substanceUID, isomer: e.isomer, releaseForm: e.releaseForm,
                productName: e.productName, displayNameSnapshot: e.displayNameSnapshot,
                timestamp: e.timestamp.msSince1970, notes: e.notes, tags: e.tags,
                isBackgroundMed: e.isBackgroundMed,
                locationName: e.locationName, latitude: e.latitude, longitude: e.longitude,
                isApproximate: e.isApproximate, isUnknownDose: e.isUnknownDose,
                hadGrapefruit: e.hadGrapefruit,
                volumeML: e.volumeML, abv: e.abv, drinkName: e.drinkName,
            )
        }

        let sessionData = sessions.map { session in
            PiruSessionData(
                id: session.id, startDate: session.startDate.msSince1970,
                title: session.title, note: session.note,
                doses: session.orderedDoses.map(doseData),
                notes: session.orderedNotes.map(PiruSessionNoteData.init),
                checkInIntervalMinutes: session.checkInIntervalMinutes,
                checkInOffsetMinutes: session.checkInOffsetMinutes,
                checkInOffered: session.checkInOffered,
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
                substanceUID: item.substanceUID, isomer: item.isomer, releaseForm: item.releaseForm,
                saltForm: item.saltForm, productName: item.productName,
                reminderTimesMinutes: item.reminderTimesMinutes, remind: item.remind,
                askAgainOverrideMinutes: item.askAgainOverrideMinutes,
                isQuiet: item.isQuiet, isAsNeeded: item.isAsNeeded, maxPerDay: item.maxPerDay,
            )
        }
        let records = try makeNativeRecords(context: context)

        return PiruFile(
            piruExportVersion: DataExportImport.piruExportVersion,
            appVersion: appVersionString,
            exportedAt: Date.now.msSince1970,
            sessions: sessionData,
            orphanDoses: orphans,
            dailyDoseItems: daily,
            substanceColors: colors
                .filter { !$0.usesDefault || $0.isLegacy }
                .map { PiruColorData(substance: $0.substance, p3: $0.tint) },
            favorites: favorites.map {
                PiruFavoriteData(
                    substance: $0.substance, createdAt: $0.createdAt.msSince1970, sortOrder: $0.sortOrder,
                    substanceUID: $0.substanceUID, isomer: $0.isomer, releaseForm: $0.releaseForm,
                    saltForm: $0.saltForm, productName: $0.productName,
                )
            },
            customSubstances: customStore.all.map(PiruCustomSubstanceData.init),
            inventory: inventoryItems.map { item in
                PiruInventoryData(
                    id: item.id,
                    sortOrder: item.sortOrder,
                    substance: item.substance,
                    saltForm: item.saltForm,
                    unit: item.unit,
                    trackingStart: item.trackingStart.msSince1970,
                    lowStockThreshold: item.lowStockThreshold,
                    baselineQuantity: item.baselineQuantity,
                    doseSize: item.doseSize,
                    unitStrengthMG: item.unitStrengthMG,
                    createdAt: item.createdAt.msSince1970,
                    manualEvents: item.manualEvents.map { event in
                        PiruManualEventData(
                            id: event.id,
                            kind: event.kind.rawValue,
                            amount: event.amount,
                            date: event.date.msSince1970,
                            note: event.note,
                            setsBaseline: event.setsBaseline,
                        )
                    },
                )
            },
            labMeasurements: records.labMeasurements,
            customUnits: records.customUnits,
            drinkPresets: records.drinkPresets,
            quickLogDoses: records.quickLogDoses,
            routineOccurrences: records.routineOccurrences,
            profile: records.profile,
            notificationPreferences: records.notificationPreferences,
            settings: exportSettings(from: settings),
        )
    }

    /// Merge exported notes into `session`, keyed by note id so a re-import is
    /// idempotent. A session that had no `.summary` note but carries a summary
    /// text gets one from ``SessionNoteService/ensureSummaryNote(for:)``.
    @MainActor
    static func importNotes(_ notes: [PiruSessionNoteData], into session: Session, context: ModelContext) {
        var existing = Set((session.notes ?? []).map(\.id))
        for data in notes where !existing.contains(data.id) {
            existing.insert(data.id)
            context.insert(SessionNote(
                id: data.id,
                timestamp: Date(ms: data.timestamp),
                text: data.text,
                shulgin: data.shulgin, mood: data.mood, energy: data.energy,
                social: data.social, worked: data.worked,
                descriptors: data.descriptors, heartRate: data.heartRate,
                kind: SessionNote.Kind(rawValue: data.kind) ?? .observation,
                session: session,
            ))
        }
        SessionNoteService.ensureSummaryNote(for: session)
    }

    /// Restores every store section of a Piru-native file and returns its
    /// settings section for the caller to apply once the store work is done.
    /// Store rows always merge: a replace runs this against a store it has
    /// just emptied, so the merge restores exactly.
    @MainActor
    static func importPiruNative(
        data: Data,
        context: ModelContext,
        customStore: CustomSubstanceStore,
    ) throws -> PiruSettingsData? {
        let file = try JSONDecoder().decode(PiruFile.self, from: data)
        importCustomSubstances(file.customSubstances, into: customStore)

        // Dedup doses by content against what's already stored and within the
        // file, so a re-import (or merge) stays idempotent.
        let existingDoses = (try? context.fetch(FetchDescriptor<DoseEntry>())) ?? []
        var seen = Set(existingDoses.map {
            doseDedupKey(substance: $0.substance, timestamp: $0.timestamp, amount: $0.amount, unit: $0.unit, route: $0.route)
        })
        // Stable-id bookkeeping, seeded with the store's ids: an imported dose
        // keeps its exported id (so references like ramp-down keys survive a
        // wipe-and-restore) unless that id is already taken — a merge where the
        // dose's content was edited on one side — in which case the fresh UUID
        // from the initializer stands. Pre-V4 files carry no ids at all and get
        // fresh UUIDs throughout.
        var seenIDs = Set(existingDoses.map(\.id))

        func makeDose(_ d: PiruDoseData) -> DoseEntry? {
            let timestamp = Date(ms: d.timestamp)
            let key = doseDedupKey(substance: d.substance, timestamp: timestamp, amount: d.amount, unit: d.unit, route: d.route)
            guard seen.insert(key).inserted else { return nil }
            let entry = DoseEntry(
                substance: d.substance, amount: d.amount, unit: d.unit, route: d.route,
                saltForm: d.saltForm,
                isomer: d.isomer, releaseForm: d.releaseForm, productName: d.productName,
                substanceUID: d.substanceUID, displayNameSnapshot: d.displayNameSnapshot,
                timestamp: timestamp, notes: d.notes, tags: d.tags, isBackgroundMed: d.isBackgroundMed,
                locationName: d.locationName, latitude: d.latitude, longitude: d.longitude,
                hadGrapefruit: d.hadGrapefruit,
                isApproximate: d.isApproximate ?? false, isUnknownDose: d.isUnknownDose ?? false,
                volumeML: d.volumeML, abv: d.abv, drinkName: d.drinkName,
            )
            if let id = d.id, seenIDs.insert(id).inserted {
                entry.id = id
            } else {
                seenIDs.insert(entry.id)
            }
            context.insert(entry)
            return entry
        }

        // Recreate sessions with their original id/title/note; reuse an existing
        // session row if one already carries that id (merge-safe). On a reused
        // row the file fills only what this install left empty, so an edit made
        // here survives a merge.
        let existingSessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        var sessionsByID = Dictionary(existingSessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for sessionData in file.sessions {
            let doses = sessionData.doses.compactMap(makeDose)
            let session: Session
            if let existing = sessionsByID[sessionData.id] {
                session = existing
                if session.title == nil { session.title = sessionData.title }
                if session.note == nil { session.note = sessionData.note }
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
            session.refreshDoseBounds()
            importNotes(sessionData.notes ?? [], into: session, context: context)
            if session.checkInIntervalMinutes == nil {
                session.checkInIntervalMinutes = sessionData.checkInIntervalMinutes
            }
            if session.checkInOffsetMinutes.isEmpty, let offsets = sessionData.checkInOffsetMinutes, !offsets.isEmpty {
                session.checkInOffsetMinutes = offsets
            }
            if sessionData.checkInOffered == true { session.checkInOffered = true }
        }

        // Session-less doses (defensive) are left unassigned; importJSON's
        // clustering pass groups them afterwards.
        for orphan in file.orphanDoses {
            _ = makeDose(orphan)
        }

        // Colors — skip substances that already have one.
        var importedColors = Set(((try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []).map { $0.substance.lowercased() })
        for color in file.substanceColors {
            guard let tint = color.tint, importedColors.insert(color.substance.lowercased()).inserted else { continue }
            context.insert(SubstanceColor(substance: color.substance, tint: tint, usesDefault: false))
        }

        // Favorites — dedup by substance.
        let existingFavs = Set(((try? context.fetch(FetchDescriptor<FavoriteSubstance>())) ?? []).map { $0.substance.lowercased() })
        for fav in file.favorites where !existingFavs.contains(fav.substance.lowercased()) {
            let favorite = FavoriteSubstance(
                substance: fav.substance, sortOrder: fav.sortOrder ?? 0,
                substanceUID: fav.substanceUID, isomer: fav.isomer, releaseForm: fav.releaseForm,
                saltForm: fav.saltForm, productName: fav.productName,
            )
            favorite.createdAt = Date(ms: fav.createdAt)
            context.insert(favorite)
        }

        // Daily-dose items — dedup by substance, restoring the full schedule.
        let existingDailyNames = Set(((try? context.fetch(FetchDescriptor<DailyDoseItem>())) ?? []).map { $0.substance.lowercased() })
        for item in file.dailyDoseItems where !existingDailyNames.contains(item.substance.lowercased()) {
            let med = DailyDoseItem(
                substance: item.substance, amount: item.amount, unit: item.unit, route: item.route,
                sortOrder: item.sortOrder, category: item.category,
                frequency: DoseFrequency(rawValue: item.frequencyRaw) ?? .daily,
                frequencyDays: item.frequencyDays, startDate: Date(ms: item.startDate),
                isBackgroundMed: item.isBackgroundMed,
                substanceUID: item.substanceUID, isomer: item.isomer, releaseForm: item.releaseForm,
                saltForm: item.saltForm, productName: item.productName,
                reminderTimesMinutes: item.reminderTimesMinutes ?? [], remind: item.remind ?? true,
                isQuiet: item.isQuiet ?? false, isAsNeeded: item.isAsNeeded ?? false, maxPerDay: item.maxPerDay,
            )
            med.askAgainOverrideMinutes = item.askAgainOverrideMinutes
            context.insert(med)
        }

        // Inventory — merge by substance identity + salt (the same key
        // `InventoryService.find` uses, so an alias and its canonical name are
        // one item): union manual events by id so a re-import is idempotent,
        // keep the earliest trackingStart, and fill any missing scalar
        // settings. Rows inserted here join the match set, so a file that
        // carries two rows for one identity still lands as one item. Then
        // recompute caches now that doses and inventory are both in —
        // silently, so a restore doesn't fire a low-stock alert per item.
        if let importedInventory = file.inventory, !importedInventory.isEmpty {
            var existingItems = (try? context.fetch(FetchDescriptor<InventoryItem>())) ?? []
            var takenIDs = Set(existingItems.map(\.id))
            for inv in importedInventory {
                let importedEvents = inv.manualEvents.map { event in
                    ManualEvent(
                        id: event.id,
                        kind: ManualEvent.Kind(rawValue: event.kind) ?? .restock,
                        amount: event.amount,
                        date: Date(ms: event.date),
                        note: event.note,
                        setsBaseline: event.setsBaseline,
                    )
                }
                if let item = InventoryService.find(substance: inv.substance, saltForm: inv.saltForm, among: existingItems) {
                    var byID = Dictionary(item.manualEvents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                    for event in importedEvents where byID[event.id] == nil {
                        byID[event.id] = event
                    }
                    item.manualEvents = byID.values.sorted { $0.date < $1.date }
                    let importedStart = Date(ms: inv.trackingStart)
                    if importedStart < item.trackingStart { item.trackingStart = importedStart }
                    if item.lowStockThreshold == nil { item.lowStockThreshold = inv.lowStockThreshold }
                    if item.baselineQuantity == nil { item.baselineQuantity = inv.baselineQuantity }
                    if item.doseSize == nil { item.doseSize = inv.doseSize }
                    if item.unitStrengthMG == nil, item.unit == inv.unit { item.unitStrengthMG = inv.unitStrengthMG }
                } else {
                    let id = inv.id.flatMap { takenIDs.contains($0) ? nil : $0 } ?? UUID()
                    takenIDs.insert(id)
                    let item = InventoryItem(
                        id: id,
                        substance: inv.substance,
                        saltForm: inv.saltForm,
                        unit: inv.unit,
                        trackingStart: Date(ms: inv.trackingStart),
                        lowStockThreshold: inv.lowStockThreshold,
                        baselineQuantity: inv.baselineQuantity,
                        doseSize: inv.doseSize,
                        unitStrengthMG: inv.unitStrengthMG,
                        manualEvents: importedEvents,
                        createdAt: Date(ms: inv.createdAt),
                        sortOrder: inv.sortOrder ?? 0,
                    )
                    context.insert(item)
                    existingItems.append(item)
                }
            }
        }
        InventoryService.recomputeAll(in: context, notify: false)

        try importNativeRecords(file, context: context)
        return file.settings
    }
}
