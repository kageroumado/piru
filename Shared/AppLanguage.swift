import Foundation
import ObjectiveC
import os

/// The language the app runs in, chosen in Settings ▸ Language, or ``system`` to follow
/// the device. The cases are exactly the localizations the string catalogs ship.
///
/// The app's own `AppleLanguages` default is the source of truth: it is what iOS's
/// per-app language page writes too, so the two settings stay one setting, and it is
/// what `Locale.current`, system sheets and App Intents read at the next launch. The
/// app group carries a mirror for the widget and the Live Activity, whose own defaults
/// the app cannot write. ``AppLanguageRuntime`` makes a change take effect in the
/// running process.
nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case spanish = "es"
    case spanishSpain = "es-ES"

    var id: String {
        rawValue
    }

    /// The `.lproj` this choice loads, or `nil` to follow the device.
    var localization: String? {
        self == .system ? nil : rawValue
    }

    /// The language's name in that language, so a person can find their own
    /// language whatever the app is showing. ``system`` has no fixed name and is
    /// localized by the caller.
    var nativeName: String? {
        switch self {
        case .system: nil
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .spanish: "Español"
        case .spanishSpain: "Español (España)"
        }
    }

    /// The choice an `AppleLanguages` list expresses. Only an exact shipped
    /// localization counts as a choice; anything else (absent, a language the app
    /// does not ship) is the device's.
    init(appleLanguages: [String]?) {
        guard let first = appleLanguages?.first,
              let match = Self.allCases.first(where: { $0.localization == first })
        else {
            self = .system
            return
        }
        self = match
    }

    /// The localization the app shows for `choice`: the choice itself, or for
    /// ``system`` the best of `available` for the device's `preferred` languages,
    /// as Foundation picks it.
    static func resolvedLocalization(
        for choice: AppLanguage,
        preferred: [String],
        available: [String],
    ) -> String {
        if let localization = choice.localization { return localization }
        let shipped = available.filter { $0 != "Base" }
        return Bundle.preferredLocalizations(from: shipped, forPreferences: preferred).first ?? "en"
    }
}

// MARK: - Storage

/// Where the choice is kept: the app's `AppleLanguages`, mirrored into the app group.
nonisolated enum AppLanguageStore {
    /// App group key the widget and the Live Activity read.
    static let mirrorKey = "appLanguage"
    static let appleLanguagesKey = "AppleLanguages"

    /// The choice as the app's own defaults hold it. `persistentDomain` reads this
    /// app's domain alone, so the device's global language list never reads as a
    /// choice.
    ///
    /// A launch argument (`-AppleLanguages (zh-Hans)`, as `pipeline/screenshots.py`
    /// passes) outranks it for that launch, as it does for Foundation.
    static func storedChoice(
        in defaults: UserDefaults = .standard,
        domain: String? = Bundle.main.bundleIdentifier,
        launchArgument: [String]? = launchArgumentLanguages(),
    ) -> AppLanguage {
        if let launch = launchArgument {
            return AppLanguage(appleLanguages: launch)
        }
        let own = domain.flatMap { defaults.persistentDomain(forName: $0) }
        return AppLanguage(appleLanguages: own?[appleLanguagesKey] as? [String])
    }

    /// `AppleLanguages` as passed on the command line, if it was.
    static func launchArgumentLanguages() -> [String]? {
        UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[appleLanguagesKey] as? [String]
    }

    /// The choice as the app group mirror holds it, for the extensions.
    static func mirroredChoice(in group: UserDefaults?) -> AppLanguage {
        group?.string(forKey: mirrorKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// Persist `choice`: `AppleLanguages` for the next launch, the mirror for the
    /// extensions.
    static func save(_ choice: AppLanguage, in defaults: UserDefaults = .standard, group: UserDefaults?) {
        if let localization = choice.localization {
            defaults.set([localization], forKey: appleLanguagesKey)
        } else {
            defaults.removeObject(forKey: appleLanguagesKey)
        }
        mirror(choice, in: group)
    }

    /// Write only the extensions' copy.
    static func mirror(_ choice: AppLanguage, in group: UserDefaults?) {
        if choice.localization != nil {
            group?.set(choice.rawValue, forKey: mirrorKey)
        } else {
            group?.removeObject(forKey: mirrorKey)
        }
    }

    /// The device's language list, read from the global domain so the app's own
    /// `AppleLanguages` does not shadow it; a launch argument stands in for it.
    static var deviceLanguages: [String] {
        if let launch = launchArgumentLanguages() { return launch }
        let global = CFPreferencesCopyValue(
            appleLanguagesKey as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost,
        ) as? [String]
        return global ?? Locale.preferredLanguages
    }
}

// MARK: - Runtime

/// Applies a language to the running process. `Bundle.main` is re-classed once so
/// every localized lookup that goes through it (SwiftUI `Text`, `String(localized:)`,
/// `NSLocalizedString`) reads the chosen `.lproj`; ``locale`` is the matching
/// `Locale` for the SwiftUI environment and for formatters that take one.
nonisolated enum AppLanguageRuntime {
    private struct State {
        var choice: AppLanguage = .system
        /// What Foundation picked at launch, and so what a lookup that names
        /// no language of its own asks for.
        let launchLocalization: String
        var localization: String
        var bundle: Bundle?
        var installed = false

        init() {
            launchLocalization = Bundle.main.preferredLocalizations.first ?? "en"
            localization = launchLocalization
        }
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    /// The choice in effect.
    static var choice: AppLanguage {
        state.withLock { $0.choice }
    }

    /// The `.lproj` in effect ("en", "zh-Hans", "es-ES", …).
    static var localization: String {
        state.withLock { $0.localization }
    }

    /// The device locale with its language swapped for the one in effect, so a
    /// region's number, date and calendar conventions survive the switch.
    static var locale: Locale {
        locale(for: localization, base: .current)
    }

    static func locale(for localization: String, base: Locale) -> Locale {
        let language = Locale.Language(identifier: localization)
        var components = Locale.Components(locale: base)
        components.languageComponents.languageCode = language.languageCode
        components.languageComponents.script = language.script
        return Locale(components: components)
    }

    /// Apply `choice`. Safe to call from any thread, any number of times.
    static func apply(_ choice: AppLanguage) {
        let main = Bundle.main
        let localization = AppLanguage.resolvedLocalization(
            for: choice,
            preferred: AppLanguageStore.deviceLanguages,
            available: main.localizations,
        )
        let bundle = table(for: localization)
        let needsInstall = state.withLock { state in
            state.choice = choice
            state.localization = localization
            state.bundle = bundle
            defer { state.installed = true }
            return !state.installed
        }
        if needsInstall {
            object_setClass(main, LanguageOverrideBundle.self)
        }
    }

    /// The `.lproj` for `localization`, or the source-language table.
    private static func table(for localization: String) -> Bundle? {
        Bundle.main.path(forResource: localization, ofType: "lproj").flatMap(Bundle.init(path:))
            ?? sourceLanguageBundle
    }

    /// English has no `.lproj`: the catalogs' keys are the English text. An empty
    /// table answers every lookup with its key, as an English device does, with
    /// the markdown and inflection a key carries still parsed.
    private static let sourceLanguageBundle: Bundle? = {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiruSourceLanguage.lproj", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return Bundle(path: directory.path)
    }()

    /// Apply the app's choice inside an extension, from the app group mirror.
    static func applyMirroredChoice() {
        apply(AppLanguageStore.mirroredChoice(in: UserDefaults(suiteName: AppIdentity.appGroup)))
    }

    fileprivate static var overrideBundle: Bundle? {
        state.withLock { $0.bundle }
    }

    /// The table for a lookup that names its languages. Foundation fills them in
    /// from the launch locale when the caller gave none, so a request for the
    /// launch language reads the language in effect; any other is a caller's own
    /// explicit locale and is honored.
    fileprivate static func overrideBundle(requested: [String]?) -> Bundle? {
        let (bundle, launch) = state.withLock { ($0.bundle, $0.launchLocalization) }
        guard let requested, !requested.isEmpty,
              let best = Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: requested).first,
              best != launch
        else { return bundle }
        return table(for: best)
    }
}

/// `Bundle.main`'s class once ``AppLanguageRuntime`` is installed: localized
/// lookups answer from the chosen `.lproj`; everything else is the main bundle.
///
/// SwiftUI `Text` reads `localizedString(forKey:value:table:)`, but
/// `String(localized:)` and `AttributedString(localized:)` ask with an explicit
/// localization list taken from the launch locale, through other selectors.
/// Those are answered here too, or every string a body computes would stay in
/// the launch language until a relaunch.
private final nonisolated class LanguageOverrideBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = AppLanguageRuntime.overrideBundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }

    @objc(localizedStringForKey:value:table:localization:)
    func localizedString(forKey key: String, value: String?, table tableName: String?, localization: String?) -> String {
        __localizedString(forKey: key, value: value, table: tableName, localizations: localization.map { [$0] })
    }

    override func __localizedString(forKey key: String, value: String?, table tableName: String?, localizations: [String]?) -> String {
        guard let bundle = AppLanguageRuntime.overrideBundle(requested: localizations) else {
            return localizedString(forKey: key, value: value, table: tableName)
        }
        return bundle.localizedString(forKey: key, value: value, table: tableName)
    }

    @objc(_localizedStringForKey:value:table:localizations:)
    func _localizedString(forKey key: String, value: String?, table tableName: String?, localizations: [String]?) -> String {
        __localizedString(forKey: key, value: value, table: tableName, localizations: localizations)
    }

    /// Never `super` here: `NSBundle`'s implementation calls the
    /// `localization:` variant below, which lands back in this method.
    override func __localizedAttributedString(forKey key: String, value: String?, table tableName: String?) -> NSAttributedString {
        guard let bundle = AppLanguageRuntime.overrideBundle else {
            return NSAttributedString(string: value.flatMap { $0.isEmpty ? nil : $0 } ?? key)
        }
        return bundle.__localizedAttributedString(forKey: key, value: value, table: tableName)
    }

    @objc(localizedAttributedStringForKey:value:table:localization:)
    func localizedAttributedString(forKey key: String, value: String?, table tableName: String?, localization: String?) -> NSAttributedString {
        guard let bundle = AppLanguageRuntime.overrideBundle(requested: localization.map { [$0] }) else {
            return __localizedAttributedString(forKey: key, value: value, table: tableName)
        }
        return bundle.__localizedAttributedString(forKey: key, value: value, table: tableName)
    }

    override var preferredLocalizations: [String] {
        [AppLanguageRuntime.localization]
    }
}
