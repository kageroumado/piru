import Foundation
import SwiftData
import Testing
@testable import Piru

// MARK: - Field tables

/// One persisted property of a model, and how to tell whether two rows agree
/// on it. The round-trip test compares every row through these tables, and
/// the coverage test requires every stored property of every `@Model` to be
/// either in a table or in ``ExportCoverage/derivedFields`` — so a property
/// added later cannot silently fall out of the backup.
private struct FieldCheck<M> {
    let name: String
    let same: (M, M) -> Bool
}

private func field<M>(_ name: String, _ keyPath: KeyPath<M, some Equatable>) -> FieldCheck<M> {
    FieldCheck(name: name) { $0[keyPath: keyPath] == $1[keyPath: keyPath] }
}

private func field<M>(_ name: String, _ same: @escaping (M, M) -> Bool) -> FieldCheck<M> {
    FieldCheck(name: name, same: same)
}

@MainActor
private enum Fields {
    static let doseEntry: [FieldCheck<DoseEntry>] = [
        field("id", \.id), field("substance", \.substance), field("amount", \.amount), field("unit", \.unit),
        field("route", \.route), field("saltForm", \.saltForm), field("isomer", \.isomer),
        field("releaseForm", \.releaseForm), field("substanceUID", \.substanceUID),
        field("productName", \.productName), field("displayNameSnapshot", \.displayNameSnapshot),
        field("timestamp", \.timestamp), field("notes", \.notes), field("tagsRaw", \.tagsRaw),
        field("session") { $0.session?.id == $1.session?.id },
        field("isBackgroundMed", \.isBackgroundMed), field("locationName", \.locationName),
        field("latitude", \.latitude), field("longitude", \.longitude), field("hadGrapefruit", \.hadGrapefruit),
        field("isApproximate", \.isApproximate), field("isUnknownDose", \.isUnknownDose),
        field("volumeML", \.volumeML), field("abv", \.abv), field("drinkName", \.drinkName),
    ]

    static let session: [FieldCheck<Session>] = [
        field("id", \.id), field("startDate", \.startDate), field("title", \.title), field("note", \.note),
        field("doses") { Set(($0.doses ?? []).map(\.id)) == Set(($1.doses ?? []).map(\.id)) },
        field("notes") { Set(($0.notes ?? []).map(\.id)) == Set(($1.notes ?? []).map(\.id)) },
        field("checkInIntervalMinutes", \.checkInIntervalMinutes),
        field("checkInOffsetsData") { $0.checkInOffsetMinutes == $1.checkInOffsetMinutes },
        field("checkInOffered", \.checkInOffered),
    ]

    static let sessionNote: [FieldCheck<SessionNote>] = [
        field("id", \.id), field("timestamp", \.timestamp), field("text", \.text), field("shulgin", \.shulgin),
        field("mood", \.mood), field("energy", \.energy), field("social", \.social), field("worked", \.worked),
        field("descriptors", \.descriptors), field("heartRate", \.heartRate), field("kindRaw", \.kindRaw),
        field("session") { $0.session?.id == $1.session?.id },
    ]

    static let dailyDoseItem: [FieldCheck<DailyDoseItem>] = [
        field("substance", \.substance), field("amount", \.amount), field("unit", \.unit), field("route", \.route),
        field("sortOrder", \.sortOrder), field("category", \.category), field("substanceUID", \.substanceUID),
        field("isomer", \.isomer), field("releaseForm", \.releaseForm), field("saltForm", \.saltForm),
        field("productName", \.productName), field("isBackgroundMed", \.isBackgroundMed),
        field("reminderTimesMinutesData") { $0.reminderTimesMinutes == $1.reminderTimesMinutes },
        field("remind", \.remind),
        field("askAgainOverrideData") { $0.askAgainOverrideMinutes == $1.askAgainOverrideMinutes },
        field("isQuiet", \.isQuiet), field("isAsNeeded", \.isAsNeeded), field("maxPerDay", \.maxPerDay),
        field("frequencyRaw", \.frequencyRaw),
        field("frequencyDaysData") { $0.frequencyDays == $1.frequencyDays },
        field("startDate", \.startDate),
    ]

    static let favorite: [FieldCheck<FavoriteSubstance>] = [
        field("substance", \.substance), field("createdAt", \.createdAt), field("sortOrder", \.sortOrder),
        field("substanceUID", \.substanceUID), field("isomer", \.isomer), field("releaseForm", \.releaseForm),
        field("saltForm", \.saltForm), field("productName", \.productName),
    ]

    static let quickLogDose: [FieldCheck<QuickLogDose>] = [
        field("substance", \.substance), field("route", \.route), field("amount", \.amount), field("unit", \.unit),
        field("sortOrder", \.sortOrder), field("lastUsedAt", \.lastUsedAt), field("volumeML", \.volumeML),
        field("abv", \.abv), field("drinkName", \.drinkName), field("emoji", \.emoji),
        field("substanceUID", \.substanceUID), field("isomer", \.isomer), field("releaseForm", \.releaseForm),
        field("saltForm", \.saltForm), field("productName", \.productName),
    ]

    static let inventoryItem: [FieldCheck<InventoryItem>] = [
        field("id", \.id), field("substance", \.substance), field("saltForm", \.saltForm), field("unit", \.unit),
        field("trackingStart", \.trackingStart), field("lowStockThreshold", \.lowStockThreshold),
        field("baselineQuantity", \.baselineQuantity), field("doseSize", \.doseSize),
        field("unitStrengthMG", \.unitStrengthMG),
        field("restocksData") { $0.manualEvents == $1.manualEvents },
        field("createdAt", \.createdAt), field("sortOrder", \.sortOrder),
    ]

    static let profile: [FieldCheck<UserProfileRecord>] = [
        field("disclosureTierRaw", \.disclosureTierRaw), field("bodyWeightKg", \.bodyWeightKg),
        field("weightSourceRaw", \.weightSourceRaw), field("grapefruitLoggingEnabled", \.grapefruitLoggingEnabled),
        field("aldh2Deficient", \.aldh2Deficient),
    ]

    static let customSubstance: [FieldCheck<CustomSubstanceRecord>] = [
        field("id", \.id), field("name", \.name), field("displayName", \.displayName),
        field("categoryRaw", \.categoryRaw), field("defaultRouteRaw", \.defaultRouteRaw), field("unit", \.unit),
        field("notes", \.notes), field("dosesData") { $0.asEntry.doses == $1.asEntry.doses },
        field("durationData") { $0.asEntry.duration == $1.asEntry.duration },
        field("halfLifeMinutes", \.halfLifeMinutes), field("createdAt", \.createdAt),
    ]

    static let drinkPreset: [FieldCheck<CustomDrinkPreset>] = [
        field("name", \.name), field("emoji", \.emoji), field("strengthABV", \.strengthABV),
        field("volumeML", \.volumeML), field("substanceName", \.substanceName), field("sortOrder", \.sortOrder),
        field("createdAt", \.createdAt),
    ]

    static let unitPreset: [FieldCheck<CustomUnitPreset>] = [
        field("substanceName", \.substanceName), field("label", \.label), field("amountPerUnit", \.amountPerUnit),
        field("unit", \.unit), field("sortOrder", \.sortOrder), field("createdAt", \.createdAt),
    ]

    static let notificationPreferences: [FieldCheck<NotificationPreferences>] = [
        field("masterEnabled", \.masterEnabled), field("hydrationEnabled", \.hydrationEnabled),
        field("sleepEnabled", \.sleepEnabled), field("phaseEnabled", \.phaseEnabled),
        field("cumulativeEnabled", \.cumulativeEnabled), field("routineEnabled", \.routineEnabled),
        field("routineFollowUpEnabled", \.routineFollowUpEnabled), field("inventoryEnabled", \.inventoryEnabled),
        field("checkInEnabled", \.checkInEnabled), field("quietHoursEnabled", \.quietHoursEnabled),
        field("quietHoursStartMinutes", \.quietHoursStartMinutes),
        field("quietHoursEndMinutes", \.quietHoursEndMinutes),
        field("routineTimeSensitive", \.routineTimeSensitive),
        field("routineFollowUpTimeSensitive", \.routineFollowUpTimeSensitive),
        field("cumulativeTimeSensitive", \.cumulativeTimeSensitive),
        field("askAgainDefaultData") {
            $0.askAgainDefaultData.isEmpty == $1.askAgainDefaultData.isEmpty
                && $0.askAgainDefaultMinutes == $1.askAgainDefaultMinutes
        },
    ]

    static let routineOccurrence: [FieldCheck<RoutineOccurrence>] = [
        field("routineName", \.routineName), field("substance", \.substance), field("substanceUID", \.substanceUID),
        field("routeRaw", \.routeRaw), field("dueDay", \.dueDay), field("stateRaw", \.stateRaw),
        field("satisfyingEntryID", \.satisfyingEntryID), field("slotMinutes", \.slotMinutes),
    ]

    static let labMeasurement: [FieldCheck<LabMeasurement>] = [
        field("id", \.id), field("date", \.date), field("analyteKey", \.analyteKey), field("value", \.value),
        field("inputUnit", \.inputUnit), field("esterID", \.esterID),
        field("excludedFromCalibration", \.excludedFromCalibration), field("note", \.note),
        field("createdAt", \.createdAt),
    ]

    static let substanceColor: [FieldCheck<SubstanceColor>] = [
        field("substance", \.substance), field("red", \.red), field("green", \.green), field("blue", \.blue),
        field("usesDefault", \.usesDefault),
    ]

    /// Every checked property name, keyed by entity name.
    static var checked: [String: Set<String>] {
        [
            "DoseEntry": Set(doseEntry.map(\.name)),
            "Session": Set(session.map(\.name)),
            "SessionNote": Set(sessionNote.map(\.name)),
            "DailyDoseItem": Set(dailyDoseItem.map(\.name)),
            "FavoriteSubstance": Set(favorite.map(\.name)),
            "QuickLogDose": Set(quickLogDose.map(\.name)),
            "InventoryItem": Set(inventoryItem.map(\.name)),
            "UserProfileRecord": Set(profile.map(\.name)),
            "CustomSubstanceRecord": Set(customSubstance.map(\.name)),
            "CustomDrinkPreset": Set(drinkPreset.map(\.name)),
            "CustomUnitPreset": Set(unitPreset.map(\.name)),
            "NotificationPreferences": Set(notificationPreferences.map(\.name)),
            "RoutineOccurrence": Set(routineOccurrence.map(\.name)),
            "LabMeasurement": Set(labMeasurement.map(\.name)),
            "SubstanceColor": Set(substanceColor.map(\.name)),
        ]
    }
}

// MARK: - Coverage manifest

/// What a Piru-native export deliberately leaves out, and why. Everything
/// else in the schema must be in a ``Fields`` table.
private enum ExportCoverage {
    static let excludedEntities: [String: String] = [
        "ToleranceState": "a cache of the dose-log replay; ToleranceStore rebuilds it from the restored doses",
        "DoseRoutine": "folded into DailyDoseItem reminder fields by MedsMigrator and no longer read",
    ]

    static let derivedFields: [String: [String: String]] = [
        "Session": ["lastDoseDate": "refreshDoseBounds recomputes it from the restored doses"],
        "InventoryItem": [
            "currentQuantity": "InventoryService.recomputeAll rebuilds it from doses and manual events",
            "lowStockNotified": "transient alert latch, reset by the recompute",
        ],
        "SubstanceColor": [
            "hexColor": "legacy sRGB column; its color travels as P3 components and restores as a resolved row",
        ],
    ]
}

// MARK: - Settings manifest

/// `UserDefaults` keys found in the source that deliberately stay on the
/// device, with the reason. See ``ExportedSettings`` for the ones that travel.
private let excludedSettingKeys: [String: String] = [
    "appLaunchCount": "launch counter",
    "AppNavigator.selectedTab": "navigation state",
    "backup.autoICloudEnabled": "this device's backup state",
    "backup.lastPlaintextHash": "this device's backup state",
    "backup.lastSuccessDate": "this device's backup state",
    "backupKey.v1": "Keychain account name, not a default",
    "checkInOfferDeclines": "prompt counter",
    "legacyHandoff.": "LegacyHandoff's key prefix, not a default",
    "legacyHandoff.completedAt": "this install's handoff bookkeeping",
    "legacyHandoff.importedJournalEntries": "this install's handoff bookkeeping",
    "legacyHandoff.successorImportedAt": "the legacy install's handoff bookkeeping",
    "deepLink": "notification userInfo key, not a default",
    "skipTarget": "notification userInfo key, not a default",
    "didOfferSessionVitals": "prompt flag",
    "didResplitOverlongSessionsV1": "migration bookkeeping",
    "discordPromptDismissedForever": "prompt flag",
    "discordPromptShown": "prompt flag",
    "dockLabelsMigrated_v1": "migration bookkeeping",
    "doseLogStoreGeneration": "cache key",
    "ester.identityBackfill.v1.disabled": "migration bookkeeping",
    "ester.identityBackfill.v1.snapshotTaken": "migration bookkeeping",
    "hasCompletedOnboarding": "onboarding flag",
    "install.firstBuild": "update-notice bookkeeping",
    "journalResetDate": "reset bookkeeping",
    "journalResetGeneration": "reset bookkeeping",
    "medsRoutineFoldDone": "migration bookkeeping",
    "myMedsMissedNoticeDismissedDays": "per-day notice dismissals",
    "notificationMasterEnabled": "mirror of NotificationPreferences, which is exported",
    "notificationQuietHoursEnabled": "mirror of NotificationPreferences, which is exported",
    "notificationQuietHoursEnd": "mirror of NotificationPreferences, which is exported",
    "notificationQuietHoursStart": "mirror of NotificationPreferences, which is exported",
    "phaseNotificationsEnabled": "legacy flag seeded into NotificationPreferences",
    "wellnessNotificationsEnabled": "legacy flag seeded into NotificationPreferences",
    "piru.customSubstances.v1": "legacy blob migrated into CustomSubstanceRecord",
    "piru.sourceOrderMigrationVersion": "migration bookkeeping",
    "piru.substanceDisplayNames.v1": "widget mirror of custom display names",
    "piruImportFile": "debug launch argument",
    "piruNow": "debug launch argument",
    "piruPersona": "debug launch argument",
    "piruScanFixture": "debug launch argument",
    "piruShowTips": "debug launch argument",
    "piruShowUpdateNotice": "debug launch argument",
    "psid.curatedBackfill.v1.disabled": "migration bookkeeping",
    "psid.doseBackfill.v1.disabled": "migration bookkeeping",
    "psid.doseBackfill.v1.snapshotTaken": "migration bookkeeping",
    "psid.repin.20260912.didRun": "migration bookkeeping",
    "quickLogManifest": "watch sync payload",
    "watchDosePayload": "watch sync payload",
    "skinOwnedProducts": "StoreKit re-establishes ownership on the new install",
    "ternaryTapHintSeen": "hint flag",
]

// MARK: - Coverage tests

@Suite("Export completeness — coverage")
@MainActor
struct ExportCoverageTests {
    @Test
    func `every stored property of every model is exported or excluded with a reason`() {
        let schema = Schema(PiruSchema.models)
        let checked = Fields.checked
        var seenEntities: Set<String> = []
        for entity in schema.entities {
            seenEntities.insert(entity.name)
            let stored = Set(entity.attributes.map(\.name)).union(entity.relationships.map(\.name))
            if ExportCoverage.excludedEntities[entity.name] != nil {
                #expect(checked[entity.name] == nil, "\(entity.name) is both excluded and checked")
                continue
            }
            guard let exported = checked[entity.name] else {
                Issue.record("\(entity.name) is neither exported nor excluded — add a Fields table or an excludedEntities reason")
                continue
            }
            let derived = Set((ExportCoverage.derivedFields[entity.name] ?? [:]).keys)
            for property in stored.subtracting(exported).subtracting(derived).sorted() {
                Issue.record("\(entity.name).\(property) is neither exported nor listed as derived")
            }
            for property in exported.union(derived).subtracting(stored).sorted() {
                Issue.record("\(entity.name).\(property) is listed but not a stored property")
            }
            #expect(exported.isDisjoint(with: derived), "\(entity.name) lists a property as both exported and derived")
        }
        for name in Set(checked.keys).union(ExportCoverage.excludedEntities.keys).subtracting(seenEntities).sorted() {
            Issue.record("\(name) is listed but is not in PiruSchema.models")
        }
    }

    @Test
    func `every UserDefaults key in the source is exported or excluded with a reason`() throws {
        let sources = try Self.appSources()
        let patterns = try [
            #"@AppStorage\(\s*"([^"\\]+)""#,
            #"forKey:\s*"([^"\\]+)""#,
            #"static let \w*[Kk]ey\w*\s*=\s*"([^"\\]+)""#,
            #"AppStorage\(wrappedValue: [^,]+, "([^"\\]+)""#,
        ].map { try NSRegularExpression(pattern: $0) }
        var found: Set<String> = []
        for text in sources.values {
            let range = NSRange(text.startIndex..., in: text)
            for regex in patterns {
                for match in regex.matches(in: text, range: range) {
                    if let r = Range(match.range(at: 1), in: text) { found.insert(String(text[r])) }
                }
            }
        }
        let exported = Set(ExportedSettings.all.map(\.key))
        #expect(exported.isDisjoint(with: excludedSettingKeys.keys))
        for key in found.subtracting(exported).subtracting(excludedSettingKeys.keys).sorted() {
            Issue.record("UserDefaults key \"\(key)\" is neither in ExportedSettings nor excluded with a reason")
        }

        // Each exported key must still be read somewhere: literally, or as a
        // `prefix.\(suffix)` key whose suffix is a literal elsewhere.
        let corpus = sources.values.joined(separator: "\n")
        for key in exported.sorted() where !corpus.contains("\"\(key)\"") {
            let prefix = key.split(separator: ".").dropLast().joined(separator: ".") + "."
            let suffix = key.split(separator: ".").last.map(String.init) ?? key
            #expect(corpus.contains("\"\(prefix)\\(") && corpus.contains("\"\(suffix)\""), "\(key) is exported but read nowhere")
        }
    }

    private static func appSources(file: StaticString = #filePath) throws -> [URL: String] {
        let root = URL(fileURLWithPath: "\(file)").deletingLastPathComponent().deletingLastPathComponent()
        var result: [URL: String] = [:]
        for dir in ["Piru", "Shared", "PiruWidget", "PiruLiveActivityExtension"] {
            guard let walker = FileManager.default.enumerator(at: root.appendingPathComponent(dir), includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                result[url] = try String(contentsOf: url, encoding: .utf8)
            }
        }
        #expect(result.count > 100, "source scan found too few files at \(root.path)")
        return result
    }
}

// MARK: - Round-trip

@Suite("Export completeness — round-trip", .serialized)
@MainActor
struct ExportRoundTripTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_700_003_600)

    private struct Side {
        let container: ModelContainer
        let context: ModelContext
        let customs: CustomSubstanceStore
        let settings: DataExportImport.SettingsScope
        let sources: SubstanceStore
        let tempDir: URL
        let suites: [String]
    }

    private func makeSide() throws -> Side {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Schema(PiruSchema.models), configurations: config)
        let context = container.mainContext
        let (sources, tempDir) = try makeIsolatedSubstanceStore()
        let standardName = "piru.tests.export.\(UUID().uuidString)"
        let groupName = "piru.tests.export.group.\(UUID().uuidString)"
        return try Side(
            container: container,
            context: context,
            customs: CustomSubstanceStore.forTesting(context: context),
            settings: .init(
                standard: #require(UserDefaults(suiteName: standardName)),
                appGroup: #require(UserDefaults(suiteName: groupName)),
                sources: sources,
            ),
            sources: sources,
            tempDir: tempDir,
            suites: [standardName, groupName],
        )
    }

    private func tearDown(_ side: Side) {
        for name in side.suites {
            UserDefaults().removePersistentDomain(forName: name)
        }
        tearDownIsolatedSubstanceStore(side.sources, tempDir: side.tempDir)
    }

    /// A value of the setting's kind that differs from the key being unset.
    private func sampleValue(for setting: ExportedSetting) -> Any {
        switch setting.kind {
        case .bool: true
        case .int: 7
        case .double: 1.75
        case .string: "value-\(setting.key)"
        case .strings: ["a-\(setting.key)", "b"]
        case .data: Data("data-\(setting.key)".utf8)
        }
    }

    /// The key the source leaves unset, so replace must remove it on the target.
    private let unsetKey = "timelineZoom"

    // MARK: Seeding

    private func seed(_ side: Side) throws {
        let context = side.context
        let session = Session(id: UUID(), startDate: t0, title: "Trip", note: "the summary")
        session.checkInIntervalMinutes = -1
        session.checkInOffsetMinutes = [15, 45]
        session.checkInOffered = true
        context.insert(session)

        let drink = DoseEntry(
            substance: "Alcohol", amount: 13, unit: "g", route: .insufflation, saltForm: "HCl", isomer: "d",
            releaseForm: "XR", productName: "Brand", substanceUID: "uid-alcohol", displayNameSnapshot: "Snapshot",
            timestamp: t0, notes: "dose notes", tags: ["a", "b"], isBackgroundMed: true,
            locationName: "Park", latitude: 51.5, longitude: -0.12, hadGrapefruit: true, isApproximate: true,
            volumeML: 330, abv: 5, drinkName: "IPA",
        )
        drink.session = session
        context.insert(drink)
        let unknown = DoseEntry(
            substance: "Caffeine", amount: 0, unit: "mg", route: .oral, substanceUID: "uid-caffeine",
            timestamp: t1, isUnknownDose: true,
        )
        unknown.session = session
        context.insert(unknown)

        context.insert(SessionNote(timestamp: t0, text: "the summary", kind: .summary, session: session))
        context.insert(SessionNote(
            timestamp: t1, text: "check-in", shulgin: 3, mood: 1, energy: -1, social: 0, worked: 1,
            descriptors: ["euphoria"], heartRate: 92, kind: .checkIn, session: session,
        ))

        let med = DailyDoseItem(
            substance: "Sertraline", amount: 50, unit: "µg", route: .sublingual, sortOrder: 3, category: "Morning",
            frequency: .specificDays, frequencyDays: [2, 4], startDate: t0, isBackgroundMed: true,
            substanceUID: "uid-sertraline", isomer: "s", releaseForm: "ER", saltForm: "HCl", productName: "Zoloft",
            reminderTimesMinutes: [480, 1200], remind: false, isQuiet: true, isAsNeeded: true, maxPerDay: 2,
        )
        med.askAgainOverrideMinutes = [5, 20]
        context.insert(med)

        let favorite = FavoriteSubstance(
            substance: "Caffeine", sortOrder: 4, substanceUID: "uid-caffeine", isomer: "x",
            releaseForm: "IR", saltForm: "citrate", productName: "Coffee",
        )
        favorite.createdAt = t0
        context.insert(favorite)

        context.insert(QuickLogDose(
            substance: "Alcohol", route: .insufflation, amount: 13, unit: "g", sortOrder: 2.5, lastUsedAt: t0,
            volumeML: 330, abv: 5, drinkName: "IPA", emoji: "🍺", substanceUID: "uid-alcohol", isomer: "d",
            releaseForm: "XR", saltForm: "HCl", productName: "Brand",
        ))

        context.insert(InventoryItem(
            id: UUID(), substance: "Caffeine", saltForm: "citrate", unit: "tabs", trackingStart: t0,
            lowStockThreshold: 5, baselineQuantity: 30, doseSize: 2, unitStrengthMG: 10,
            manualEvents: [ManualEvent(kind: .restock, amount: 12, date: t1, note: "bought", setsBaseline: true)],
            createdAt: t0, sortOrder: 2,
        ))

        context.insert(UserProfileRecord(
            disclosureTierRaw: UserProfile.casual.rawValue, bodyWeightKg: 61.5, weightSourceRaw: "manual",
            grapefruitLoggingEnabled: true, aldh2Deficient: true,
        ))

        side.customs.add(CustomSubstanceEntry(
            name: "2-MMC", displayName: "mmc", category: .stimulant, defaultRoute: .insufflation, unit: "µg",
            notes: "custom notes", doses: DoseRange(common: 5 ... 10, heavy: 30),
            duration: DurationProfile(
                onset: DurationRange(min: 5, max: 15), comeup: nil, peak: DurationRange(min: 30, max: 90),
                offset: nil, afterglow: nil, total: DurationRange(min: 120, max: 240),
            ),
            halfLifeMinutes: 180, createdAt: t0,
        ))

        context.insert(CustomDrinkPreset(
            name: "House red", emoji: "🍷", strengthABV: 13.5, volumeML: 175, substanceName: "wine",
            sortOrder: 2, createdAt: t0,
        ))
        context.insert(CustomUnitPreset(
            substanceName: "Lisdexamfetamine", label: "capsule", amountPerUnit: 30, unit: "µg", sortOrder: 1, createdAt: t0,
        ))

        let prefs = NotificationPreferences()
        prefs.masterEnabled = false
        prefs.hydrationEnabled = true
        prefs.sleepEnabled = true
        prefs.phaseEnabled = true
        prefs.cumulativeEnabled = true
        prefs.routineEnabled = false
        prefs.routineFollowUpEnabled = false
        prefs.inventoryEnabled = false
        prefs.checkInEnabled = false
        prefs.quietHoursEnabled = true
        prefs.quietHoursStartMinutes = 22 * 60
        prefs.quietHoursEndMinutes = 6 * 60
        prefs.routineTimeSensitive = false
        prefs.routineFollowUpTimeSensitive = false
        prefs.cumulativeTimeSensitive = false
        prefs.askAgainDefaultMinutes = [7, 14]
        context.insert(prefs)

        let occurrence = RoutineOccurrence(
            routineName: "Morning", substance: "Sertraline", substanceUID: "uid-sertraline", route: .sublingual,
            dueDay: t0, slotMinutes: 480,
        )
        occurrence.state = .skipped
        occurrence.satisfyingEntryID = drink.id
        context.insert(occurrence)

        context.insert(LabMeasurement(
            id: UUID(), date: t0, analyteKey: "testosterone", value: 512, inputUnit: "nmol/L", esterID: "cypionate",
            excludedFromCalibration: true, note: "fasted", createdAt: t1,
        ))

        context.insert(SubstanceColor(substance: "Caffeine", tint: P3Color(red: 0.1, green: 0.2, blue: 0.3), usesDefault: false))
        try context.save()

        for setting in ExportedSettings.all where setting.key != unsetKey {
            side.settings.defaults(setting.domain).set(sampleValue(for: setting), forKey: setting.key)
        }
        let reordered = side.sources.sourcePreferences()
        let count = reordered.count
        side.sources.restoreSourcePreferences(reordered.enumerated().map { index, pref in
            .init(slug: pref.slug, priority: count - index, enabled: index % 3 != 0)
        })
    }

    /// Different data on the importing side, so the replace has something to
    /// wipe and every setting has something to overwrite or remove.
    private func seedJunk(_ side: Side) throws {
        side.context.insert(DoseEntry(substance: "Junk", amount: 1, timestamp: t1))
        side.context.insert(LabMeasurement(value: 1))
        side.context.insert(CustomUnitPreset(substanceName: "junk", label: "scoop", amountPerUnit: 1))
        side.context.insert(UserProfileRecord(bodyWeightKg: 99))
        side.customs.add(CustomSubstanceEntry(name: "2-MMC", notes: "stale"))
        try side.context.save()
        for setting in ExportedSettings.all {
            let defaults = side.settings.defaults(setting.domain)
            switch setting.kind {
            case .bool: defaults.set(false, forKey: setting.key)
            case .int: defaults.set(1, forKey: setting.key)
            case .double: defaults.set(9.5, forKey: setting.key)
            case .string: defaults.set("junk", forKey: setting.key)
            case .strings: defaults.set(["junk"], forKey: setting.key)
            case .data: defaults.set(Data("junk".utf8), forKey: setting.key)
            }
        }
        side.sources.setSource(side.sources.sourcePreferences()[0].slug, enabled: false)
    }

    // MARK: Comparison

    private func compare<M: PersistentModel>(
        _ type: M.Type, _ checks: [FieldCheck<M>], source: Side, target: Side, key: (M) -> String,
    ) throws {
        let before = try source.context.fetch(FetchDescriptor<M>())
        let after = try target.context.fetch(FetchDescriptor<M>())
        let name = "\(type)"
        #expect(!before.isEmpty, "\(name) was not seeded")
        #expect(before.count == after.count, "\(name): \(before.count) rows exported, \(after.count) restored")
        let restored = Dictionary(after.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
        for row in before {
            guard let match = restored[key(row)] else {
                Issue.record("\(name) \(key(row)) did not come back")
                continue
            }
            for check in checks where !check.same(row, match) {
                Issue.record("\(name).\(check.name) differs after the round-trip")
            }
        }
    }

    /// Each checked field must hold a non-default value in at least one seeded
    /// row — otherwise a dropped field would restore to its default and the
    /// comparison would still pass.
    private func expectNonDefault<M: PersistentModel>(_ checks: [FieldCheck<M>], rows: [M], default blank: M) {
        for check in checks where rows.allSatisfy({ check.same($0, blank) }) {
            Issue.record("\(M.self).\(check.name) is seeded with its default value")
        }
    }

    @Test
    func `every exported item and setting survives export, wipe and replace`() throws {
        let source = try makeSide()
        let target = try makeSide()
        defer {
            tearDown(source)
            tearDown(target)
        }
        try seed(source)
        try seedJunk(target)

        let data = try DataExportImport.exportJSON(context: source.context, customStore: source.customs, settings: source.settings)

        try DataExportImport.deleteAll(context: target.context)
        target.customs.resetAfterDeletion()
        try DataExportImport.importJSON(
            data: data, context: target.context, customStore: target.customs, mode: .replace, settings: target.settings,
        )
        try target.context.save()

        try compare(DoseEntry.self, Fields.doseEntry, source: source, target: target) { $0.id.uuidString }
        try compare(Session.self, Fields.session, source: source, target: target) { $0.id.uuidString }
        try compare(SessionNote.self, Fields.sessionNote, source: source, target: target) { $0.id.uuidString }
        try compare(DailyDoseItem.self, Fields.dailyDoseItem, source: source, target: target) { $0.substance }
        try compare(FavoriteSubstance.self, Fields.favorite, source: source, target: target) { $0.substance }
        try compare(QuickLogDose.self, Fields.quickLogDose, source: source, target: target) { $0.key }
        try compare(InventoryItem.self, Fields.inventoryItem, source: source, target: target) { $0.id.uuidString }
        try compare(UserProfileRecord.self, Fields.profile, source: source, target: target) { _ in "profile" }
        try compare(CustomSubstanceRecord.self, Fields.customSubstance, source: source, target: target) { $0.name }
        try compare(CustomDrinkPreset.self, Fields.drinkPreset, source: source, target: target) { $0.name }
        try compare(CustomUnitPreset.self, Fields.unitPreset, source: source, target: target) { $0.label }
        try compare(NotificationPreferences.self, Fields.notificationPreferences, source: source, target: target) { _ in "prefs" }
        try compare(RoutineOccurrence.self, Fields.routineOccurrence, source: source, target: target) { $0.substance }
        try compare(LabMeasurement.self, Fields.labMeasurement, source: source, target: target) { $0.id.uuidString }
        try compare(SubstanceColor.self, Fields.substanceColor, source: source, target: target) { $0.substance }

        for setting in ExportedSettings.all {
            let before = source.settings.defaults(setting.domain).object(forKey: setting.key)
            let after = target.settings.defaults(setting.domain).object(forKey: setting.key)
            if setting.key == unsetKey {
                #expect(after == nil, "\(setting.key) is unset on the source but survived the replace")
            } else {
                #expect((before as? NSObject) == (after as? NSObject), "setting \(setting.key) differs after the round-trip")
            }
        }
        #expect(source.sources.sourcePreferences() == target.sources.sourcePreferences())
        #expect(!source.sources.sourcePreferencesAreDefault())
    }

    @Test
    func `the seed puts a non-default value in every exported field`() throws {
        let side = try makeSide()
        defer { tearDown(side) }
        try seed(side)
        let context = side.context
        try expectNonDefault(Fields.doseEntry, rows: context.fetch(FetchDescriptor()), default: DoseEntry(substance: "", amount: 0, timestamp: .distantPast))
        try expectNonDefault(Fields.session, rows: context.fetch(FetchDescriptor()), default: Session(startDate: .distantPast))
        try expectNonDefault(Fields.sessionNote, rows: context.fetch(FetchDescriptor()), default: SessionNote(timestamp: .distantPast))
        try expectNonDefault(Fields.dailyDoseItem, rows: context.fetch(FetchDescriptor()), default: DailyDoseItem(substance: "", amount: 0))
        try expectNonDefault(Fields.favorite, rows: context.fetch(FetchDescriptor()), default: FavoriteSubstance(substance: ""))
        try expectNonDefault(
            Fields.quickLogDose, rows: context.fetch(FetchDescriptor()),
            default: QuickLogDose(substance: "", route: .oral, amount: 0, unit: "mg", sortOrder: 0, lastUsedAt: .distantPast),
        )
        try expectNonDefault(Fields.inventoryItem, rows: context.fetch(FetchDescriptor()), default: InventoryItem(trackingStart: .distantPast, createdAt: .distantPast))
        try expectNonDefault(Fields.profile, rows: context.fetch(FetchDescriptor()), default: UserProfileRecord())
        try expectNonDefault(Fields.customSubstance, rows: context.fetch(FetchDescriptor()), default: CustomSubstanceRecord(CustomSubstanceEntry(name: "", createdAt: .distantPast)))
        try expectNonDefault(Fields.drinkPreset, rows: context.fetch(FetchDescriptor()), default: CustomDrinkPreset(name: "", strengthABV: 5, createdAt: .distantPast))
        try expectNonDefault(Fields.unitPreset, rows: context.fetch(FetchDescriptor()), default: CustomUnitPreset(substanceName: "", label: "", amountPerUnit: 0, createdAt: .distantPast))
        try expectNonDefault(Fields.notificationPreferences, rows: context.fetch(FetchDescriptor()), default: NotificationPreferences())
        try expectNonDefault(Fields.routineOccurrence, rows: context.fetch(FetchDescriptor()), default: RoutineOccurrence(substance: "", route: .oral, dueDay: .distantPast))
        try expectNonDefault(Fields.labMeasurement, rows: context.fetch(FetchDescriptor()), default: LabMeasurement(date: .distantPast, createdAt: .distantPast))
        try expectNonDefault(
            Fields.substanceColor, rows: context.fetch(FetchDescriptor()),
            default: SubstanceColor(substance: "", tint: P3Color(red: 0, green: 0, blue: 0), usesDefault: true),
        )
    }

    @Test
    func `a merge fills only what the importing install has not set`() throws {
        let source = try makeSide()
        let target = try makeSide()
        defer {
            tearDown(source)
            tearDown(target)
        }
        try seed(source)
        let data = try DataExportImport.exportJSON(context: source.context, customStore: source.customs, settings: source.settings)

        let chosen = UserProfileRecord(bodyWeightKg: 80, weightSourceRaw: "manual")
        target.context.insert(chosen)
        target.context.insert(NotificationPreferences())
        target.settings.appGroup.set(false, forKey: "stackRedoses")
        try target.context.save()

        try DataExportImport.importJSON(data: data, context: target.context, customStore: target.customs, settings: target.settings)
        try DataExportImport.importJSON(data: data, context: target.context, customStore: target.customs, settings: target.settings)

        // A choice made here stays; an untouched record and unset keys take the file's.
        #expect(try target.context.fetch(FetchDescriptor<UserProfileRecord>()).map(\.bodyWeightKg) == [80])
        let prefs = try #require(try target.context.fetch(FetchDescriptor<NotificationPreferences>()).first)
        #expect(prefs.quietHoursEnabled)
        #expect(target.settings.appGroup.object(forKey: "stackRedoses") as? Bool == false)
        #expect(target.settings.appGroup.string(forKey: SkinDefaults.skinKey) == "value-\(SkinDefaults.skinKey)")
        #expect(target.sources.sourcePreferences() == source.sources.sourcePreferences())

        // Importing twice added nothing.
        #expect(try target.context.fetchCount(FetchDescriptor<LabMeasurement>()) == 1)
        #expect(try target.context.fetchCount(FetchDescriptor<QuickLogDose>()) == 1)
        #expect(try target.context.fetchCount(FetchDescriptor<CustomUnitPreset>()) == 1)
        #expect(try target.context.fetchCount(FetchDescriptor<CustomDrinkPreset>()) == 1)
        #expect(try target.context.fetchCount(FetchDescriptor<RoutineOccurrence>()) == 1)
        #expect(try target.context.fetchCount(FetchDescriptor<NotificationPreferences>()) == 1)
        #expect(try target.context.fetchCount(FetchDescriptor<SessionNote>()) == 2)
    }

    @Test
    func `a file written before these sections imports and leaves them alone`() throws {
        let target = try makeSide()
        defer { tearDown(target) }
        target.settings.appGroup.set(true, forKey: "stackRedoses")
        let data = Data(#"{"piruExportVersion": 2, "sessions": [], "favorites": [{"substance": "Caffeine", "createdAt": 1700000000000}]}"#.utf8)

        try DataExportImport.importJSON(data: data, context: target.context, customStore: target.customs, mode: .replace, settings: target.settings)

        let favorite = try #require(try target.context.fetch(FetchDescriptor<FavoriteSubstance>()).first)
        #expect(favorite.createdAt == t0)
        #expect(favorite.sortOrder == 0)
        #expect(target.settings.appGroup.object(forKey: "stackRedoses") as? Bool == true)
        #expect(target.sources.sourcePreferencesAreDefault())
    }
}
