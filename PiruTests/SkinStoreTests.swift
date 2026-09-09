import Foundation
import SwiftUI
import Testing
@testable import Piru

@MainActor
@Suite("Skin store")
struct SkinStoreTests {
    /// A throwaway suite per test so runs never see each other's state.
    private func freshDefaults() -> UserDefaults {
        let name = "test.skin.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test
    func `Starts on the default skin, following the system scheme`() {
        let store = SkinStore(defaults: freshDefaults())
        #expect(store.current == SkinDefaults.skinDefault)
        #expect(store.colorScheme == .system)
        #expect(store.colorScheme.colorScheme == nil)
    }

    @Test
    func `A chosen skin survives a new store on the same suite`() {
        let defaults = freshDefaults()
        let store = SkinStore(defaults: defaults)
        store.setSkin(.piru)
        #expect(defaults.string(forKey: SkinDefaults.skinKey) == Skin.piru.rawValue)
        #expect(SkinStore(defaults: defaults).current == .piru)
        #expect(SkinDefaults.storedSkin(in: defaults) == .piru)
    }

    @Test
    func `A chosen colour scheme survives a new store on the same suite`() {
        let defaults = freshDefaults()
        let store = SkinStore(defaults: defaults)
        store.setColorScheme(.dark)
        #expect(store.colorScheme == .dark)
        #expect(SkinStore(defaults: defaults).colorScheme == .dark)
        #expect(SkinColorScheme.dark.colorScheme == .dark)
        #expect(SkinColorScheme.light.colorScheme == .light)
    }

    @Test
    func `A stored skin this build doesn't know falls back to the default`() {
        let defaults = freshDefaults()
        defaults.set("not-a-skin", forKey: SkinDefaults.skinKey)
        #expect(SkinDefaults.storedSkin(in: defaults) == SkinDefaults.skinDefault)
        #expect(SkinStore(defaults: defaults).current == SkinDefaults.skinDefault)
    }

    @Test
    func `Decorations toggle persists and only decorated skins carry a set`() {
        let defaults = freshDefaults()
        let store = SkinStore(defaults: defaults)
        #expect(store.decorationsEnabled == SkinDefaults.decorationsDefault)
        store.setDecorationsEnabled(false)
        #expect(SkinStore(defaults: defaults).decorationsEnabled == false)
        #expect(Skin.piru.decorations == nil)
        #expect((Skin.elyPink.decorations?.glyphs.count ?? 0) >= 8)
    }

    @Test
    func `Theme resolves through the active skin's palette`() {
        let skin = SkinStore.shared.current
        #expect(Theme.accent == skin.accent)
        #expect(Theme.secondaryLabel == skin.secondaryLabel)
        #expect(Theme.background == skin.background)
        #expect(Theme.cardBackground == skin.cardBackground)
        #expect(Theme.inputBackground == skin.inputBackground)
    }

    @Test
    func `The default skin keeps the app's shipped treatment`() {
        #expect(Skin.piru.surface == .glass)
        #expect(Skin.piru.fontDesign == nil)
        #expect(Skin.allCases.first == .piru)
    }
}
