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

    /// The skin this person picked, persisted.
    private(set) var chosen: Skin
    /// A skin being looked at in the picker. It dresses the whole app exactly
    /// as a chosen one would, so a paid skin can be seen on the person's own
    /// screens before it is bought; it is never persisted, so the extensions
    /// and the next launch never see it.
    private(set) var tryingOn: Skin?

    /// The skin the app is wearing.
    var current: Skin {
        tryingOn ?? chosen
    }

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
        chosen = SkinDefaults.storedSkin(in: defaults)
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
    /// A skin this person does not own is refused.
    func setSkin(_ skin: Skin) {
        guard SkinDefaults.usable(skin, in: defaults) else { return }
        defaults.set(skin.rawValue, forKey: SkinDefaults.skinKey)
        if tryingOn != nil { tryingOn = nil }
        if skin != chosen {
            chosen = skin
            // Widgets read the persisted choice; they only re-render on reload.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Wears `skin` without choosing it. `nil`, or the chosen skin, ends the
    /// try-on.
    func tryOn(_ skin: Skin?) {
        let next = skin == chosen ? nil : skin
        if next != tryingOn { tryingOn = next }
    }

    /// Ends a try-on for good: a skin this person may wear becomes their choice,
    /// and one they do not own comes off.
    func settleTryOn() {
        guard let skin = tryingOn else { return }
        if SkinDefaults.usable(skin, in: defaults) { setSkin(skin) } else { tryingOn = nil }
    }

    /// Re-resolves `current` after `SkinShop` rewrites the owned set: a refunded
    /// skin falls back to the default, and a restored one comes back, because
    /// the stored choice outlives both.
    func ownershipChanged() {
        let resolved = SkinDefaults.storedSkin(in: defaults)
        guard resolved != chosen else { return }
        chosen = resolved
        WidgetCenter.shared.reloadAllTimelines()
    }

    func setColorScheme(_ scheme: SkinColorScheme) {
        defaults.set(scheme.rawValue, forKey: SkinDefaults.colorSchemeKey)
        if scheme != colorScheme { colorScheme = scheme }
    }
}
