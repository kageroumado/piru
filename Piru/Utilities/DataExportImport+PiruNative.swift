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
/// favorites, user colors, and daily-dose schedules. Detected on import by
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
    var substanceColors: [PiruColorData]
    var userColors: [PiruUserColorData]
    var favorites: [PiruFavoriteData]
    var customSubstances: [PiruCustomSubstanceData]
    /// Optional for back-compat: files written before inventory tracking omit
    /// the key, which decodes to `nil` (treated as empty). Mirrors the
    /// `id`/`saltForm` optional-on-decode pattern the dose data uses.
    var inventory: [PiruInventoryData]?
}

nonisolated struct PiruSessionData: Codable {
    var id: UUID
    var startDate: Int64
    var title: String?
    var note: String?
    var doses: [PiruDoseData]
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
}

nonisolated struct PiruColorData: Codable {
    var substance: String
    var hexColor: String
}

nonisolated struct PiruUserColorData: Codable {
    var hex: String
    var name: String
    var createdAt: Int64
}

nonisolated struct PiruFavoriteData: Codable {
    var substance: String
    var createdAt: Int64
}

/// Everything needed to reconstruct an inventory item's stock. `currentQuantity`
/// and `lowStockNotified` are intentionally omitted — both are derived/transient
/// and rebuilt by `recomputeAll` after import. `trackingStart` is preserved so
/// the dose-consumption window matches the source device exactly.
nonisolated struct PiruInventoryData: Codable {
    var substance: String
    var saltForm: String?
    var unit: String
    var trackingStart: Int64
    var lowStockThreshold: Double?
    var baselineQuantity: Double?
    var doseSize: Double?
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
    static func makePiruFile(context: ModelContext, customStore: CustomSubstanceStore) throws -> PiruFile {
        let sessions = try context.fetch(FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startDate)]))
        let allEntries = try context.fetch(FetchDescriptor<DoseEntry>())
        let dailyDoses = try context.fetch(FetchDescriptor<DailyDoseItem>())
        let colors = try context.fetch(FetchDescriptor<SubstanceColor>())
        let userColors = try context.fetch(FetchDescriptor<UserColor>())
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
            customSubstances: customStore.all.map(PiruCustomSubstanceData.init),
            inventory: inventoryItems.map { item in
                PiruInventoryData(
                    substance: item.substance,
                    saltForm: item.saltForm,
                    unit: item.unit,
                    trackingStart: item.trackingStart.msSince1970,
                    lowStockThreshold: item.lowStockThreshold,
                    baselineQuantity: item.baselineQuantity,
                    doseSize: item.doseSize,
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
        )
    }

    @MainActor
    static func importPiruNative(data: Data, context: ModelContext, customStore: CustomSubstanceStore) throws {
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
            session.refreshDoseBounds()
        }

        // Session-less doses (defensive) are left unassigned; importJSON's
        // clustering pass groups them afterwards.
        for orphan in file.orphanDoses {
            _ = makeDose(orphan)
        }

        // Colors — skip substances that already have one.
        var importedColors = Set(((try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []).map { $0.substance.lowercased() })
        for color in file.substanceColors where importedColors.insert(color.substance.lowercased()).inserted {
            context.insert(SubstanceColor(substance: color.substance, hexColor: color.hexColor))
        }

        // User-defined palette colors — dedup by hex.
        let existingUserHexes = Set(((try? context.fetch(FetchDescriptor<UserColor>())) ?? []).map { $0.hex.uppercased() })
        for uc in file.userColors where !existingUserHexes.contains(uc.hex.uppercased()) {
            let color = UserColor(hex: uc.hex, name: uc.name)
            color.createdAt = Date(ms: uc.createdAt)
            context.insert(color)
        }

        // Favorites — dedup by substance.
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

        // Inventory — merge by (substance, salt): union manual events by id so a
        // re-import is idempotent, keep the earliest trackingStart, and fill any
        // missing scalar settings. Then recompute caches now that doses and
        // inventory are both in — silently, so a restore doesn't fire a low-stock
        // alert per item.
        if let importedInventory = file.inventory, !importedInventory.isEmpty {
            let existingItems = (try? context.fetch(FetchDescriptor<InventoryItem>())) ?? []
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
                if let item = existingItems.first(where: {
                    $0.substance.lowercased() == inv.substance.lowercased() && $0.saltForm == inv.saltForm
                }) {
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
                } else {
                    context.insert(InventoryItem(
                        substance: inv.substance,
                        saltForm: inv.saltForm,
                        unit: inv.unit,
                        trackingStart: Date(ms: inv.trackingStart),
                        lowStockThreshold: inv.lowStockThreshold,
                        baselineQuantity: inv.baselineQuantity,
                        doseSize: inv.doseSize,
                        manualEvents: importedEvents,
                        createdAt: Date(ms: inv.createdAt),
                    ))
                }
            }
        }
        InventoryService.recomputeAll(in: context, notify: false)
    }
}
