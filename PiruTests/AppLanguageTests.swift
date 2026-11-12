import Foundation
import Testing
@testable import Piru

@Suite("AppLanguage")
struct AppLanguageTests {
    /// A throwaway defaults domain standing in for both the app's own defaults
    /// and the app group.
    private func scratchDefaults() -> (UserDefaults, String) {
        let name = "piru.tests.language.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test
    func `Offers exactly the localizations the catalogs ship`() {
        let offered = AppLanguage.allCases.compactMap(\.localization)
        #expect(offered == ["en", "zh-Hans", "zh-Hant", "es", "es-ES"])
        let shipped = Set(Bundle.main.localizations).subtracting(["Base"])
        #expect(Set(offered).isSubset(of: shipped))
    }

    @Test
    func `Each language is named in itself; System is named by the caller`() {
        #expect(AppLanguage.system.nativeName == nil)
        #expect(AppLanguage.simplifiedChinese.nativeName == "简体中文")
        #expect(AppLanguage.spanish.nativeName == "Español")
    }

    @Test
    func `An AppleLanguages list reads as a choice only for an exact shipped localization`() {
        #expect(AppLanguage(appleLanguages: nil) == .system)
        #expect(AppLanguage(appleLanguages: []) == .system)
        #expect(AppLanguage(appleLanguages: ["zh-Hans"]) == .simplifiedChinese)
        #expect(AppLanguage(appleLanguages: ["es-ES", "en"]) == .spanishSpain)
        #expect(AppLanguage(appleLanguages: ["fr-FR", "en"]) == .system)
    }

    @Test
    func `System resolves to the device's best shipped language; a choice resolves to itself`() {
        let shipped = ["Base", "en", "zh-Hans", "zh-Hant", "es", "es-ES"]
        #expect(AppLanguage.resolvedLocalization(for: .system, preferred: ["zh-Hans-FR", "en"], available: shipped) == "zh-Hans")
        #expect(AppLanguage.resolvedLocalization(for: .system, preferred: ["es-MX"], available: shipped) == "es")
        #expect(AppLanguage.resolvedLocalization(for: .system, preferred: ["fr-FR"], available: shipped) == "en")
        #expect(AppLanguage.resolvedLocalization(for: .spanish, preferred: ["zh-Hans"], available: shipped) == "es")
    }

    @Test
    func `Saving writes AppleLanguages and the mirror; System clears both`() {
        let (own, ownName) = scratchDefaults()
        let (group, groupName) = scratchDefaults()
        defer {
            own.removePersistentDomain(forName: ownName)
            group.removePersistentDomain(forName: groupName)
        }

        AppLanguageStore.save(.traditionalChinese, in: own, group: group)
        #expect(own.stringArray(forKey: AppLanguageStore.appleLanguagesKey) == ["zh-Hant"])
        #expect(AppLanguageStore.storedChoice(in: own, domain: ownName, launchArgument: nil) == .traditionalChinese)
        #expect(AppLanguageStore.mirroredChoice(in: group) == .traditionalChinese)

        AppLanguageStore.save(.system, in: own, group: group)
        #expect(AppLanguageStore.storedChoice(in: own, domain: ownName, launchArgument: nil) == .system)
        #expect(AppLanguageStore.mirroredChoice(in: group) == .system)
    }

    @Test
    func `A launch argument outranks the stored choice`() {
        let (own, name) = scratchDefaults()
        defer { own.removePersistentDomain(forName: name) }
        AppLanguageStore.save(.english, in: own, group: nil)
        #expect(AppLanguageStore.storedChoice(in: own, domain: name, launchArgument: ["zh-Hant"]) == .traditionalChinese)
        #expect(AppLanguageStore.storedChoice(in: own, domain: name, launchArgument: nil) == .english)
    }

    @Test
    func `A missing or unknown mirror reads as System`() {
        let (group, name) = scratchDefaults()
        defer { group.removePersistentDomain(forName: name) }
        #expect(AppLanguageStore.mirroredChoice(in: nil) == .system)
        group.set("klingon", forKey: AppLanguageStore.mirrorKey)
        #expect(AppLanguageStore.mirroredChoice(in: group) == .system)
    }

    @Test
    func `The runtime locale swaps the language and keeps the region`() {
        let locale = AppLanguageRuntime.locale(for: "es", base: Locale(identifier: "en_FR"))
        #expect(locale.language.languageCode == .spanish)
        #expect(locale.region == .france)
    }

    @Test
    func `Every offered language maps to its content language`() {
        #expect(ContentLanguage(localization: "es-ES") == .es)
        #expect(ContentLanguage(localization: "zh-Hant") == .zhHant)
        #expect(ContentLanguage(localization: "zh-Hans") == .zhHans)
        #expect(ContentLanguage(localization: "en") == .en)
    }
}
