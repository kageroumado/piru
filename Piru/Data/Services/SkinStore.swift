import Foundation
import Observation
import WidgetKit

/// The active skin and colour-scheme override, persisted to the app group.
///
/// `Theme`'s accessors read `current` on every access, so any view that touches
/// `Theme.accent` (or the card modifiers) inside its `body` is tracked by
/// Observation and re-renders when the skin changes — the ~1,000 existing
/// `Theme.*` call sites become skin-reactive without being edited.
@Observable
@MainActor
final class SkinStore {
    static let shared = SkinStore(defaults: UserDefaults(suiteName: SkinDefaults.suite) ?? .standard)

    private(set) var current: Skin
    private(set) var colorScheme: SkinColorScheme
    /// Whether a decorated skin draws its glyphs and blinkies. Ignored by
    /// skins without decorations.
    private(set) var decorationsEnabled: Bool

    private let defaults: UserDefaults

    /// Installs itself as `Skin.current`'s provider so `Shared/` code (the
    /// semantic-colour shorthands) reads the observable choice, not a stale
    /// UserDefaults snapshot.
    static func activate() {
        // The shorthands are read inside view bodies, on the main actor;
        // `assumeIsolated` states that and traps on any off-main read rather
        // than racing the store.
        Skin.currentProvider = { MainActor.assumeIsolated { shared.current } }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        current = SkinDefaults.storedSkin(in: defaults)
        if let raw = defaults.string(forKey: SkinDefaults.colorSchemeKey),
           let scheme = SkinColorScheme(rawValue: raw) {
            colorScheme = scheme
        } else {
            colorScheme = SkinDefaults.colorSchemeDefault
        }
        decorationsEnabled = defaults.object(forKey: SkinDefaults.decorationsKey) as? Bool ?? SkinDefaults.decorationsDefault
        #if DEBUG
            // `-piruNoDecor` launches with the decoration layer off, to tell a
            // backdrop problem from everything else on a device.
            if ProcessInfo.processInfo.arguments.contains("-piruNoDecor") { decorationsEnabled = false }
        #endif
    }

    func setDecorationsEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: SkinDefaults.decorationsKey)
        if enabled != decorationsEnabled { decorationsEnabled = enabled }
    }

    /// Always writes, so the app-group key exists for the extensions even when
    /// the choice equals the default; only mutates `current` on a real change.
    func setSkin(_ skin: Skin) {
        defaults.set(skin.rawValue, forKey: SkinDefaults.skinKey)
        if skin != current {
            current = skin
            // Widgets read the persisted choice; they only re-render on reload.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func setColorScheme(_ scheme: SkinColorScheme) {
        defaults.set(scheme.rawValue, forKey: SkinDefaults.colorSchemeKey)
        if scheme != colorScheme { colorScheme = scheme }
    }
}
