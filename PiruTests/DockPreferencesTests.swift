import Foundation
import Testing
@testable import Piru

@Suite("DockPreferences")
@MainActor
struct DockPreferencesTests {
    /// A throwaway suite per test so runs never share state.
    private func makeDefaults() -> UserDefaults {
        let name = "DockPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Fresh store yields the defaults")
    func defaults() {
        let prefs = DockPreferences(defaults: makeDefaults())
        #expect(prefs.shortcuts == [.inventory])
        #expect(prefs.labels == [.due, .text("Log a dose")])
    }

    @Test("Shortcuts round-trip through the store, favorites included")
    func shortcutsRoundTrip() {
        let defaults = makeDefaults()
        let prefs = DockPreferences(defaults: defaults)
        prefs.shortcuts = [.favorite(substance: "Memantine"), .addNote, .timeline]

        let reloaded = DockPreferences(defaults: defaults)
        #expect(reloaded.shortcuts == [.favorite(substance: "Memantine"), .addNote, .timeline])
    }

    @Test("Labels round-trip through the store, every kind")
    func labelsRoundTrip() {
        let defaults = makeDefaults()
        let prefs = DockPreferences(defaults: defaults)
        let labels: [DockLabel] = [
            .timer(.untilNextMed),
            .timed("Morning meds?", startHour: 7, endHour: 10),
            .due,
            .text("Log a dose"),
        ]
        prefs.labels = labels

        let reloaded = DockPreferences(defaults: defaults)
        #expect(reloaded.labels == labels)
    }

    @Test("Adding caps at three slots and ignores duplicates")
    func shortcutCap() {
        let prefs = DockPreferences(defaults: makeDefaults())
        prefs.addShortcut(.inventory)
        prefs.addShortcut(.myMeds)
        prefs.addShortcut(.interactions)
        #expect(prefs.shortcuts == [.inventory, .myMeds, .interactions])
        #expect(!prefs.canAddShortcut)
        prefs.addShortcut(.timeline)
        #expect(prefs.shortcuts.count == 3)
    }

    @Test("Adding an identical label is a no-op")
    func duplicateLabel() {
        let prefs = DockPreferences(defaults: makeDefaults())
        prefs.addLabel(.due)
        #expect(prefs.labels == [.due, .text("Log a dose")])
        prefs.addLabel(.timer(.sinceLastDose))
        #expect(prefs.labels.last == .timer(.sinceLastDose))
    }

    @Test("Undecodable stored data falls back to the defaults")
    func corruptStore() {
        let defaults = makeDefaults()
        defaults.set(Data("nope".utf8), forKey: "dockShortcuts")
        let prefs = DockPreferences(defaults: defaults)
        #expect(prefs.shortcuts == [.inventory])
    }
}
