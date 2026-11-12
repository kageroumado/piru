import Foundation

extension String {
    /// A localized string with its automatic grammar agreement applied, for
    /// the places that need a plain `String` (an accessibility value joined
    /// from parts, share text, a notification body).
    ///
    /// `String(localized:)` returns `^[2 item](inflect: true)` with the markup
    /// intact, and VoiceOver reads it out character for character. Only
    /// `AttributedString(localized:)` (and `Text`) parse the markdown and
    /// inflect it, so this resolves through it and keeps the characters.
    init(inflecting value: String.LocalizationValue, locale: Locale = AppLanguageRuntime.locale) {
        self = String(AttributedString(localized: value, locale: locale).characters)
    }
}
