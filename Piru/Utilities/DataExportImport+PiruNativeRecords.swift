import Foundation
import SwiftData

// MARK: - Wire types

/// One serum lab result (``LabMeasurement``). Keyed by `id` on import.
nonisolated struct PiruLabMeasurementData: Codable {
    var id: UUID
    var date: Int64
    var analyteKey: String
    var value: Double
    var inputUnit: String
    var esterID: String?
    var excludedFromCalibration: Bool
    var note: String?
    var createdAt: Int64
}

/// One user-defined colloquial unit (``CustomUnitPreset``). Keyed by
/// substance + label on import.
nonisolated struct PiruCustomUnitData: Codable {
    var substanceName: String
    var label: String
    var amountPerUnit: Double
    var unit: String
    var sortOrder: Double
    var createdAt: Int64
}

/// One drink preset (``CustomDrinkPreset``). Keyed by substance + name on
/// import, so the curated seeds an install already made are not doubled.
nonisolated struct PiruDrinkPresetData: Codable {
    var name: String
    var emoji: String
    var strengthABV: Double
    var volumeML: Double?
    var substanceName: String
    var sortOrder: Double
    var createdAt: Int64
}

/// One curated quick-log chip (``QuickLogDose``). Keyed by ``QuickLogDose/key``
/// on import.
nonisolated struct PiruQuickLogDoseData: Codable {
    var substance: String
    var route: RouteOfAdministration
    var amount: Double
    var unit: String
    var sortOrder: Double
    var lastUsedAt: Int64
    var volumeML: Double?
    var abv: Double?
    var drinkName: String?
    var emoji: String?
    var substanceUID: String?
    var isomer: String?
    var releaseForm: String?
    var saltForm: String?
    var productName: String?
}

/// One med-slot occurrence (``RoutineOccurrence``). Past days are history the
/// reconcile never re-derives — a Skip is a user choice, a miss is a record —
/// so every row travels. Keyed by routine, item identity, route, day and slot.
nonisolated struct PiruRoutineOccurrenceData: Codable {
    var routineName: String
    var substance: String
    var substanceUID: String?
    var route: String
    var dueDay: Int64
    var state: String
    var satisfyingEntryID: UUID?
    var slotMinutes: Int?
}

/// The profile singleton (``UserProfileRecord``).
nonisolated struct PiruProfileData: Codable, Equatable {
    var disclosureTier: String
    var bodyWeightKg: Double?
    var weightSource: String
    var grapefruitLoggingEnabled: Bool
    var aldh2Deficient: Bool
}

/// The notification-preferences singleton (``NotificationPreferences``).
nonisolated struct PiruNotificationPreferencesData: Codable, Equatable {
    var masterEnabled: Bool
    var hydrationEnabled: Bool
    var sleepEnabled: Bool
    var phaseEnabled: Bool
    var cumulativeEnabled: Bool
    var routineEnabled: Bool
    var routineFollowUpEnabled: Bool
    var inventoryEnabled: Bool
    var checkInEnabled: Bool
    var quietHoursEnabled: Bool
    var quietHoursStartMinutes: Int
    var quietHoursEndMinutes: Int
    var routineTimeSensitive: Bool
    var routineFollowUpTimeSensitive: Bool
    var cumulativeTimeSensitive: Bool
    /// `nil` when the cadence was never edited, so the importing install keeps
    /// reading the built-in default rather than a frozen copy of it.
    var askAgainDefaultMinutes: [Int]?
}

// MARK: - Mapping

extension PiruProfileData {
    init(_ record: UserProfileRecord) {
        disclosureTier = record.disclosureTierRaw
        bodyWeightKg = record.bodyWeightKg
        weightSource = record.weightSourceRaw
        grapefruitLoggingEnabled = record.grapefruitLoggingEnabled
        aldh2Deficient = record.aldh2Deficient
    }

    func apply(to record: UserProfileRecord) {
        record.disclosureTierRaw = disclosureTier
        record.bodyWeightKg = bodyWeightKg
        record.weightSourceRaw = weightSource
        record.grapefruitLoggingEnabled = grapefruitLoggingEnabled
        record.aldh2Deficient = aldh2Deficient
    }
}

extension PiruNotificationPreferencesData {
    init(_ record: NotificationPreferences) {
        masterEnabled = record.masterEnabled
        hydrationEnabled = record.hydrationEnabled
        sleepEnabled = record.sleepEnabled
        phaseEnabled = record.phaseEnabled
        cumulativeEnabled = record.cumulativeEnabled
        routineEnabled = record.routineEnabled
        routineFollowUpEnabled = record.routineFollowUpEnabled
        inventoryEnabled = record.inventoryEnabled
        checkInEnabled = record.checkInEnabled
        quietHoursEnabled = record.quietHoursEnabled
        quietHoursStartMinutes = record.quietHoursStartMinutes
        quietHoursEndMinutes = record.quietHoursEndMinutes
        routineTimeSensitive = record.routineTimeSensitive
        routineFollowUpTimeSensitive = record.routineFollowUpTimeSensitive
        cumulativeTimeSensitive = record.cumulativeTimeSensitive
        askAgainDefaultMinutes = record.askAgainDefaultData.isEmpty ? nil : record.askAgainDefaultMinutes
    }

    func apply(to record: NotificationPreferences) {
        record.masterEnabled = masterEnabled
        record.hydrationEnabled = hydrationEnabled
        record.sleepEnabled = sleepEnabled
        record.phaseEnabled = phaseEnabled
        record.cumulativeEnabled = cumulativeEnabled
        record.routineEnabled = routineEnabled
        record.routineFollowUpEnabled = routineFollowUpEnabled
        record.inventoryEnabled = inventoryEnabled
        record.checkInEnabled = checkInEnabled
        record.quietHoursEnabled = quietHoursEnabled
        record.quietHoursStartMinutes = quietHoursStartMinutes
        record.quietHoursEndMinutes = quietHoursEndMinutes
        record.routineTimeSensitive = routineTimeSensitive
        record.routineFollowUpTimeSensitive = routineFollowUpTimeSensitive
        record.cumulativeTimeSensitive = cumulativeTimeSensitive
        if let askAgainDefaultMinutes {
            record.askAgainDefaultMinutes = askAgainDefaultMinutes
        } else {
            record.askAgainDefaultData = Data()
        }
    }
}

// MARK: - Export / import

extension DataExportImport {
    /// The per-record sections of ``PiruFile`` beyond the journal itself.
    struct NativeRecords {
        var labMeasurements: [PiruLabMeasurementData]
        var customUnits: [PiruCustomUnitData]
        var drinkPresets: [PiruDrinkPresetData]
        var quickLogDoses: [PiruQuickLogDoseData]
        var routineOccurrences: [PiruRoutineOccurrenceData]
        var profile: PiruProfileData?
        var notificationPreferences: PiruNotificationPreferencesData?
    }

    @MainActor
    static func makeNativeRecords(context: ModelContext) throws -> NativeRecords {
        let labs = try context.fetch(FetchDescriptor<LabMeasurement>(sortBy: [SortDescriptor(\.date)]))
        let units = try context.fetch(FetchDescriptor<CustomUnitPreset>(sortBy: [SortDescriptor(\.sortOrder)]))
        let drinks = try context.fetch(FetchDescriptor<CustomDrinkPreset>(sortBy: [SortDescriptor(\.sortOrder)]))
        let chips = try context.fetch(FetchDescriptor<QuickLogDose>(sortBy: [SortDescriptor(\.sortOrder)]))
        let occurrences = try context.fetch(FetchDescriptor<RoutineOccurrence>(sortBy: [SortDescriptor(\.dueDay)]))
        let profile = try context.fetch(FetchDescriptor<UserProfileRecord>()).first
        let notifications = try context.fetch(FetchDescriptor<NotificationPreferences>()).first

        return NativeRecords(
            labMeasurements: labs.map {
                PiruLabMeasurementData(
                    id: $0.id, date: $0.date.msSince1970, analyteKey: $0.analyteKey, value: $0.value,
                    inputUnit: $0.inputUnit, esterID: $0.esterID,
                    excludedFromCalibration: $0.excludedFromCalibration, note: $0.note,
                    createdAt: $0.createdAt.msSince1970,
                )
            },
            customUnits: units.map {
                PiruCustomUnitData(
                    substanceName: $0.substanceName, label: $0.label, amountPerUnit: $0.amountPerUnit,
                    unit: $0.unit, sortOrder: $0.sortOrder, createdAt: $0.createdAt.msSince1970,
                )
            },
            drinkPresets: drinks.map {
                PiruDrinkPresetData(
                    name: $0.name, emoji: $0.emoji, strengthABV: $0.strengthABV, volumeML: $0.volumeML,
                    substanceName: $0.substanceName, sortOrder: $0.sortOrder, createdAt: $0.createdAt.msSince1970,
                )
            },
            quickLogDoses: chips.map {
                PiruQuickLogDoseData(
                    substance: $0.substance, route: $0.route, amount: $0.amount, unit: $0.unit,
                    sortOrder: $0.sortOrder, lastUsedAt: $0.lastUsedAt.msSince1970,
                    volumeML: $0.volumeML, abv: $0.abv, drinkName: $0.drinkName, emoji: $0.emoji,
                    substanceUID: $0.substanceUID, isomer: $0.isomer, releaseForm: $0.releaseForm,
                    saltForm: $0.saltForm, productName: $0.productName,
                )
            },
            routineOccurrences: occurrences.map {
                PiruRoutineOccurrenceData(
                    routineName: $0.routineName, substance: $0.substance, substanceUID: $0.substanceUID,
                    route: $0.routeRaw, dueDay: $0.dueDay.msSince1970, state: $0.stateRaw,
                    satisfyingEntryID: $0.satisfyingEntryID, slotMinutes: $0.slotMinutes,
                )
            },
            profile: profile.map(PiruProfileData.init),
            notificationPreferences: notifications.map(PiruNotificationPreferencesData.init),
        )
    }

    /// Restores the per-record sections. Collections merge by their natural
    /// key, so a re-import adds nothing. The two singletons take the file's
    /// values only while this install's record is absent or untouched (every
    /// field at its default) — a replace has just deleted it, a fresh install
    /// has only the default one — so a merge never overwrites a choice made
    /// on this device.
    @MainActor
    static func importNativeRecords(_ file: PiruFile, context: ModelContext) throws {
        try importLabMeasurements(file.labMeasurements ?? [], context: context)
        try importCustomUnits(file.customUnits ?? [], context: context)
        try importDrinkPresets(file.drinkPresets ?? [], context: context)
        try importQuickLogDoses(file.quickLogDoses ?? [], context: context)
        try importRoutineOccurrences(file.routineOccurrences ?? [], context: context)

        if let profile = file.profile {
            let existing = try context.fetch(FetchDescriptor<UserProfileRecord>()).first
            if let existing {
                if PiruProfileData(existing) == PiruProfileData(UserProfileRecord()) { profile.apply(to: existing) }
            } else {
                let record = UserProfileRecord()
                profile.apply(to: record)
                context.insert(record)
            }
        }
        if let preferences = file.notificationPreferences {
            let existing = try context.fetch(FetchDescriptor<NotificationPreferences>()).first
            if let existing {
                if PiruNotificationPreferencesData(existing) == PiruNotificationPreferencesData(NotificationPreferences()) {
                    preferences.apply(to: existing)
                }
            } else {
                let record = NotificationPreferences()
                preferences.apply(to: record)
                context.insert(record)
            }
        }
    }

    private static func importLabMeasurements(_ list: [PiruLabMeasurementData], context: ModelContext) throws {
        var seen = try Set(context.fetch(FetchDescriptor<LabMeasurement>()).map(\.id))
        for lab in list where seen.insert(lab.id).inserted {
            context.insert(LabMeasurement(
                id: lab.id, date: Date(ms: lab.date), analyteKey: lab.analyteKey, value: lab.value,
                inputUnit: lab.inputUnit, esterID: lab.esterID,
                excludedFromCalibration: lab.excludedFromCalibration, note: lab.note,
                createdAt: Date(ms: lab.createdAt),
            ))
        }
    }

    private static func importCustomUnits(_ list: [PiruCustomUnitData], context: ModelContext) throws {
        func key(_ substance: String, _ label: String) -> String {
            "\(substance.lowercased())|\(label.lowercased())"
        }
        var seen = try Set(context.fetch(FetchDescriptor<CustomUnitPreset>()).map { key($0.substanceName, $0.label) })
        for unit in list where seen.insert(key(unit.substanceName, unit.label)).inserted {
            context.insert(CustomUnitPreset(
                substanceName: unit.substanceName, label: unit.label, amountPerUnit: unit.amountPerUnit,
                unit: unit.unit, sortOrder: unit.sortOrder, createdAt: Date(ms: unit.createdAt),
            ))
        }
    }

    private static func importDrinkPresets(_ list: [PiruDrinkPresetData], context: ModelContext) throws {
        func key(_ substance: String, _ name: String) -> String {
            "\(substance.lowercased())|\(name.lowercased())"
        }
        var seen = try Set(context.fetch(FetchDescriptor<CustomDrinkPreset>()).map { key($0.substanceName, $0.name) })
        for preset in list where seen.insert(key(preset.substanceName, preset.name)).inserted {
            context.insert(CustomDrinkPreset(
                name: preset.name, emoji: preset.emoji, strengthABV: preset.strengthABV, volumeML: preset.volumeML,
                substanceName: preset.substanceName, sortOrder: preset.sortOrder, createdAt: Date(ms: preset.createdAt),
            ))
        }
    }

    private static func importQuickLogDoses(_ list: [PiruQuickLogDoseData], context: ModelContext) throws {
        var seen = try Set(context.fetch(FetchDescriptor<QuickLogDose>()).map(\.key))
        for chip in list {
            let dose = QuickLogDose(
                substance: chip.substance, route: chip.route, amount: chip.amount, unit: chip.unit,
                sortOrder: chip.sortOrder, lastUsedAt: Date(ms: chip.lastUsedAt),
                volumeML: chip.volumeML, abv: chip.abv, drinkName: chip.drinkName, emoji: chip.emoji,
                substanceUID: chip.substanceUID, isomer: chip.isomer, releaseForm: chip.releaseForm,
                saltForm: chip.saltForm, productName: chip.productName,
            )
            guard seen.insert(dose.key).inserted else { continue }
            context.insert(dose)
        }
    }

    private static func importRoutineOccurrences(_ list: [PiruRoutineOccurrenceData], context: ModelContext) throws {
        func key(routine: String, substance: String, uid: String?, route: String, day: Date, slot: Int?) -> String {
            let identity = uid.flatMap { $0.isEmpty ? nil : $0 } ?? substance.lowercased()
            return "\(routine)|\(identity)|\(route)|\(day.msSince1970)|\(slot.map(String.init) ?? "-")"
        }
        var seen = try Set(context.fetch(FetchDescriptor<RoutineOccurrence>()).map {
            key(routine: $0.routineName, substance: $0.substance, uid: $0.substanceUID, route: $0.routeRaw, day: $0.dueDay, slot: $0.slotMinutes)
        })
        for data in list {
            let day = Date(ms: data.dueDay)
            let occurrenceKey = key(
                routine: data.routineName, substance: data.substance, uid: data.substanceUID,
                route: data.route, day: day, slot: data.slotMinutes,
            )
            guard seen.insert(occurrenceKey).inserted else { continue }
            let occurrence = RoutineOccurrence(
                routineName: data.routineName, substance: data.substance, substanceUID: data.substanceUID,
                route: .oral, dueDay: day, slotMinutes: data.slotMinutes,
            )
            occurrence.routeRaw = data.route
            occurrence.stateRaw = data.state
            occurrence.satisfyingEntryID = data.satisfyingEntryID
            context.insert(occurrence)
        }
    }
}
