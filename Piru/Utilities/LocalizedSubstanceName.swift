import Foundation
import os

/// The name a substance goes by in the app's language — "Ketamina" in Spanish,
/// "氯胺酮" in Simplified Chinese, "愷他命" in Traditional — where that language
/// has an established one. Research chemicals and code names (2C-B, MDMA) have
/// none and keep their canonical name.
///
/// The names are curated rows of the bundled DB's `localized_names`, loaded once
/// by ``SubstanceStore`` at index build and held in a lock-guarded static for the
/// same reason as ``RegionalSubstanceName``: the caller, ``Substance/displayTitle``,
/// is `nonisolated` and runs inside the detached library sort.
///
/// Display only, and switchable: a user who knows substances by their English
/// names turns ``usesEnglishNames`` on and every title falls back to the
/// canonical name. Search is unaffected either way — ``SubstanceStore`` adds
/// every row, in every language, to its search index.
nonisolated enum LocalizedSubstanceName {
    /// `UserDefaults.standard` key for the "show English names" preference.
    static let englishNamesKey = "substanceNamesInEnglish"

    /// Keyed by the canonical name, lowercased; each value by app language tag.
    private static let table = OSAllocatedUnfairLock<[String: [String: String]]>(initialState: [:])

    /// Install the names read from `localized_names`. Called once per store init.
    static func load(_ names: [String: [String: String]]) {
        table.withLock { $0 = names }
    }

    /// The app's language as a `localized_names.lang` tag, or `nil` in English.
    static var appLanguage: String? {
        language(for: ContentLanguage.current)
    }

    /// The `localized_names.lang` tag for a content language; English has none.
    static func language(for content: ContentLanguage) -> String? {
        content == .en ? nil : content.rawValue
    }

    /// Whether the user asked for English substance names. Read per call
    /// (`UserDefaults` is thread-safe) so flipping the setting takes effect on
    /// the next render without a relaunch.
    static var usesEnglishNames: Bool {
        UserDefaults.standard.bool(forKey: englishNamesKey)
    }

    /// Whether the app runs in a language that has localized names at all —
    /// the Settings toggle is hidden otherwise.
    static var isAvailable: Bool {
        appLanguage != nil
    }

    /// The localized title for `canonicalName`, or `nil` to keep the existing name.
    static func resolve(canonicalName: String) -> String? {
        guard !usesEnglishNames else { return nil }
        return resolve(canonicalName: canonicalName, language: appLanguage)
    }

    /// Language-injectable lookup against the installed table.
    static func resolve(canonicalName: String, language: String?) -> String? {
        table.withLock { resolve(canonicalName: canonicalName, language: language, in: $0) }
    }

    /// Pure core, exposed for tests so they never swap the process-wide table.
    static func resolve(canonicalName: String, language: String?, in names: [String: [String: String]]) -> String? {
        guard let language else { return nil }
        return names[canonicalName.lowercased()]?[language]
    }
}
