import Foundation

// MARK: - Import mode

/// How an import treats what the importing install already has.
nonisolated enum ImportMode: Equatable, Sendable {
    /// Add what is missing; never overwrite a choice made on this install.
    case merge
    /// The store was just emptied: restore the file exactly, settings included.
    case replace
}

// MARK: - Exported settings

/// Which `UserDefaults` suite a setting lives in.
nonisolated enum SettingsDomain: String, Sendable {
    case standard
    case appGroup
}

/// A setting's stored type, so export reads it with the matching getter and
/// import writes back the same type the app's readers expect.
nonisolated enum SettingKind: Sendable {
    case bool
    case int
    case double
    case string
    case strings
    case data
}

nonisolated struct ExportedSetting: Sendable {
    let key: String
    let domain: SettingsDomain
    let kind: SettingKind
}

/// The one list of `UserDefaults` keys a Piru-native export carries: choices
/// the person made about how the app looks, logs and models. Everything else
/// in `UserDefaults` stays on the device, and `ExportCoverageTests` fails on a
/// key found in the source that is in neither this list nor its excluded list.
///
/// Not exported, by design:
/// - caches and derived mirrors (`doseLogStoreGeneration`,
///   `piru.substanceDisplayNames.v1`, the `notification*` mirrors of
///   ``NotificationPreferences``, `quickLogManifest`, `watchDosePayload`);
/// - migration and launch-pass bookkeeping (`psid.*`, `ester.*`,
///   `medsRoutineFoldDone`, `didResplitOverlongSessionsV1`,
///   `piru.sourceOrderMigrationVersion`, `dockLabelsMigrated_v1`,
///   `journalResetGeneration`, `journalResetDate`, launch-pass tokens);
/// - onboarding, prompt and hint flags and counters (`hasCompletedOnboarding`,
///   `discordPrompt*`, `didOfferSessionVitals`, `ternaryTapHintSeen`,
///   `checkInOfferDeclines`, `appLaunchCount`, update-notice seen flags,
///   `myMedsMissedNoticeDismissedDays`);
/// - `skinOwnedProducts`, which StoreKit re-establishes on the new install;
/// - backup state (`backup.*`), which describes this device's backup;
/// - navigation state (`AppNavigator.selectedTab`) and debug launch arguments.
enum ExportedSettings {
    static let all: [ExportedSetting] = appGroup + standard

    static let appGroup: [ExportedSetting] = [
        .init(key: SkinDefaults.skinKey, domain: .appGroup, kind: .string),
        .init(key: SkinDefaults.colorSchemeKey, domain: .appGroup, kind: .string),
        .init(key: SkinDefaults.decorationsKey, domain: .appGroup, kind: .bool),
        .init(key: "dockShortcuts", domain: .appGroup, kind: .data),
        .init(key: "dockLabels", domain: .appGroup, kind: .data),
        .init(key: "stackRedoses", domain: .appGroup, kind: .bool),
        .init(key: "showSessionVitals", domain: .appGroup, kind: .bool),
        .init(key: "timelineZoom", domain: .appGroup, kind: .double),
        .init(key: "timelineCompression", domain: .appGroup, kind: .bool),
        .init(key: "timelinePKCurves", domain: .appGroup, kind: .bool),
        .init(key: "timelineShowsAxis", domain: .appGroup, kind: .bool),
        .init(key: "timelineBubbleStyle", domain: .appGroup, kind: .string),
        .init(key: "journalGrouping", domain: .appGroup, kind: .string),
        .init(key: "journalGroupKey", domain: .appGroup, kind: .string),
        .init(key: Calendar.dayBoundaryHourKey, domain: .appGroup, kind: .int),
        .init(key: LaneModeDefaults.enabledKey, domain: .appGroup, kind: .bool),
        .init(key: LaneModeDefaults.thresholdKey, domain: .appGroup, kind: .int),
        .init(key: SessionGraphDefaults.enlargedKey, domain: .appGroup, kind: .bool),
        .init(key: DoseTimeDefaults.choicesKey, domain: .appGroup, kind: .string),
        .init(key: "piru.searchHistory.v1", domain: .appGroup, kind: .data),
    ]

    static let standard: [ExportedSetting] = [
        .init(key: "injLevelsPersonalMultiplier", domain: .standard, kind: .double),
        .init(key: "injLevelsAutoCalibrate", domain: .standard, kind: .bool),
        .init(key: "injLevelsFitRates", domain: .standard, kind: .bool),
        .init(key: "injLevelsVolumeConcentration.estradiol", domain: .standard, kind: .double),
        .init(key: "injLevelsVolumeConcentration.testosterone", domain: .standard, kind: .double),
        .init(key: "quickLogFixedOrder", domain: .standard, kind: .bool),
        .init(key: "quickLogSuppressedRecents", domain: .standard, kind: .strings),
        .init(key: "quickLogRoutinesCollapsed", domain: .standard, kind: .bool),
        .init(key: "alcoholEditorByDrink", domain: .standard, kind: .bool),
        .init(key: "esterEditorByVolume", domain: .standard, kind: .bool),
        .init(key: "byVolumePreferredVolumeUnit", domain: .standard, kind: .string),
        .init(key: "liveActivityEnabled", domain: .standard, kind: .bool),
        .init(key: "inventory.sort", domain: .standard, kind: .string),
        .init(key: "inventory.grouped", domain: .standard, kind: .bool),
        .init(key: "inventory.collapsedCategories", domain: .standard, kind: .strings),
        .init(key: "inventory.categoryOrder", domain: .standard, kind: .strings),
        .init(key: "usageSection.coUse", domain: .standard, kind: .bool),
        .init(key: "usageSection.doseLevels", domain: .standard, kind: .bool),
        .init(key: "usageSection.regularity", domain: .standard, kind: .bool),
        .init(key: "usageSection.routes", domain: .standard, kind: .bool),
    ]
}

// MARK: - Wire types

/// One setting's value, tagged with its type: `{"bool": true}`,
/// `{"strings": ["a"]}`, `{"data": "<base64>"}`.
nonisolated enum PiruSettingValue: Codable, Equatable, Sendable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case strings([String])
    case data(Data)

    private enum CodingKeys: String, CodingKey {
        case bool
        case int
        case double
        case string
        case strings
        case data
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(Bool.self, forKey: .bool) {
            self = .bool(v)
        } else if let v = try c.decodeIfPresent(Int.self, forKey: .int) {
            self = .int(v)
        } else if let v = try c.decodeIfPresent(Double.self, forKey: .double) {
            self = .double(v)
        } else if let v = try c.decodeIfPresent(String.self, forKey: .string) {
            self = .string(v)
        } else if let v = try c.decodeIfPresent([String].self, forKey: .strings) {
            self = .strings(v)
        } else if let v = try c.decodeIfPresent(Data.self, forKey: .data) {
            self = .data(v)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Unknown setting value type"))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .bool(v): try c.encode(v, forKey: .bool)
        case let .int(v): try c.encode(v, forKey: .int)
        case let .double(v): try c.encode(v, forKey: .double)
        case let .string(v): try c.encode(v, forKey: .string)
        case let .strings(v): try c.encode(v, forKey: .strings)
        case let .data(v): try c.encode(v, forKey: .data)
        }
    }

    var object: Any {
        switch self {
        case let .bool(v): v
        case let .int(v): v
        case let .double(v): v
        case let .string(v): v
        case let .strings(v): v
        case let .data(v): v
        }
    }
}

/// One data source's rank and switch in the user's source priority.
nonisolated struct PiruSourcePreferenceData: Codable, Equatable, Sendable {
    var slug: String
    var priority: Int
    var enabled: Bool
}

/// The settings section of a Piru-native file.
nonisolated struct PiruSettingsData: Codable, Equatable, Sendable {
    /// Keyed by domain, then key. Every key in ``ExportedSettings`` is written;
    /// `null` means it was unset on the exporting install. A key the exporting
    /// build did not know is absent, which an import leaves alone.
    var standard: [String: PiruSettingValue?]
    var appGroup: [String: PiruSettingValue?]
    /// The full source-priority table, or `nil` when none could be read.
    var sourcePreferences: [PiruSourcePreferenceData]?

    private enum CodingKeys: String, CodingKey {
        case standard
        case appGroup
        case sourcePreferences
    }

    init(standard: [String: PiruSettingValue?], appGroup: [String: PiruSettingValue?], sourcePreferences: [PiruSourcePreferenceData]?) {
        self.standard = standard
        self.appGroup = appGroup
        self.sourcePreferences = sourcePreferences
    }

    /// Hand-written because the synthesized coding drops the `null` entries a
    /// `[String: T?]` needs to say "unset".
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        standard = try Self.decodeValues(c, .standard)
        appGroup = try Self.decodeValues(c, .appGroup)
        sourcePreferences = try c.decodeIfPresent([PiruSourcePreferenceData].self, forKey: .sourcePreferences)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try Self.encodeValues(standard, into: &c, .standard)
        try Self.encodeValues(appGroup, into: &c, .appGroup)
        try c.encodeIfPresent(sourcePreferences, forKey: .sourcePreferences)
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? {
            nil
        }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue _: Int) {
            nil
        }
    }

    private static func decodeValues(
        _ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys,
    ) throws -> [String: PiruSettingValue?] {
        guard c.contains(key) else { return [:] }
        let nested = try c.nestedContainer(keyedBy: Key.self, forKey: key)
        var values: [String: PiruSettingValue?] = [:]
        for k in nested.allKeys {
            if try nested.decodeNil(forKey: k) {
                values.updateValue(nil, forKey: k.stringValue)
            } else {
                values[k.stringValue] = try nested.decode(PiruSettingValue.self, forKey: k)
            }
        }
        return values
    }

    private static func encodeValues(
        _ values: [String: PiruSettingValue?], into c: inout KeyedEncodingContainer<CodingKeys>, _ key: CodingKeys,
    ) throws {
        var nested = c.nestedContainer(keyedBy: Key.self, forKey: key)
        for (k, value) in values {
            if let value {
                try nested.encode(value, forKey: Key(stringValue: k))
            } else {
                try nested.encodeNil(forKey: Key(stringValue: k))
            }
        }
    }
}

// MARK: - Export / import

extension DataExportImport {
    /// Where settings are read from and written to. Tests pass scratch suites
    /// and an isolated ``SubstanceStore``.
    struct SettingsScope {
        var standard: UserDefaults
        var appGroup: UserDefaults
        var sources: SubstanceStore?

        static var live: SettingsScope {
            SettingsScope(
                standard: .standard,
                appGroup: UserDefaults(suiteName: AppIdentity.appGroup) ?? .standard,
                sources: .shared,
            )
        }

        func defaults(_ domain: SettingsDomain) -> UserDefaults {
            switch domain {
            case .standard: standard
            case .appGroup: appGroup
            }
        }
    }

    static func exportSettings(from scope: SettingsScope) -> PiruSettingsData {
        func values(_ domain: SettingsDomain) -> [String: PiruSettingValue?] {
            let defaults = scope.defaults(domain)
            var result: [String: PiruSettingValue?] = [:]
            for setting in ExportedSettings.all where setting.domain == domain {
                result.updateValue(read(setting, from: defaults), forKey: setting.key)
            }
            return result
        }
        return PiruSettingsData(
            standard: values(.standard),
            appGroup: values(.appGroup),
            sourcePreferences: scope.sources?.sourcePreferences().map {
                PiruSourcePreferenceData(slug: $0.slug, priority: $0.priority, enabled: $0.enabled)
            },
        )
    }

    /// Applies an exported settings section. A replace restores every listed
    /// key the file carries, removing the ones it records as unset, and takes
    /// the file's source priority. A merge only fills keys this install has
    /// never set, and takes the file's source priority only while this
    /// install's is still the bundled default — the same "never overwrite a
    /// choice made here" rule the store rows follow. Keys outside
    /// ``ExportedSettings`` are ignored whatever the file says.
    static func applySettings(_ settings: PiruSettingsData, mode: ImportMode, to scope: SettingsScope) {
        for setting in ExportedSettings.all {
            let defaults = scope.defaults(setting.domain)
            let fileValues = setting.domain == .standard ? settings.standard : settings.appGroup
            guard let entry = fileValues[setting.key] else { continue }
            if mode == .merge, defaults.object(forKey: setting.key) != nil { continue }
            if let value = entry, value.matches(setting.kind) {
                defaults.set(value.object, forKey: setting.key)
            } else if entry == nil, mode == .replace {
                defaults.removeObject(forKey: setting.key)
            }
        }
        if let sources = scope.sources, let preferences = settings.sourcePreferences,
           mode == .replace || sources.sourcePreferencesAreDefault() {
            sources.restoreSourcePreferences(preferences.map {
                SubstanceStore.SourcePreference(slug: $0.slug, priority: $0.priority, enabled: $0.enabled)
            })
        }
    }

    private static func read(_ setting: ExportedSetting, from defaults: UserDefaults) -> PiruSettingValue? {
        guard defaults.object(forKey: setting.key) != nil else { return nil }
        switch setting.kind {
        case .bool: return .bool(defaults.bool(forKey: setting.key))
        case .int: return .int(defaults.integer(forKey: setting.key))
        case .double: return .double(defaults.double(forKey: setting.key))
        case .string: return defaults.string(forKey: setting.key).map(PiruSettingValue.string)
        case .strings: return defaults.stringArray(forKey: setting.key).map(PiruSettingValue.strings)
        case .data: return defaults.data(forKey: setting.key).map(PiruSettingValue.data)
        }
    }
}

private extension PiruSettingValue {
    /// Whether the value has the type the key is read as — a hand-edited file
    /// cannot put a string where the app reads a bool.
    func matches(_ kind: SettingKind) -> Bool {
        switch (self, kind) {
        case (.bool, .bool), (.int, .int), (.double, .double), (.string, .string),
             (.strings, .strings), (.data, .data): true
        default: false
        }
    }
}
