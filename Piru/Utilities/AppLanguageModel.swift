import Foundation
import Observation
import SwiftData
import WidgetKit

/// The app's side of Settings ▸ Language: applies a choice to the running app
/// and to everything that reads the language later.
///
/// What switches in place: every string looked up through `Bundle.main` (SwiftUI
/// `Text`, `String(localized:)`), the SwiftUI `locale` (dates and numbers drawn
/// by `Text`), substance titles and the database text chosen by
/// ``ContentLanguage``, interaction sentences, and the routine reminders, which
/// are rescheduled. What follows at its next refresh: the widgets (reloaded
/// here), the Live Activity (its next update), and notifications already
/// scheduled for a logged dose, which keep the language they were written in.
/// `Locale.current`, system sheets and App Intents follow from the next launch,
/// through `AppleLanguages`.
@Observable @MainActor
final class AppLanguageModel {
    static let shared = AppLanguageModel()

    /// The choice shown in Settings.
    private(set) var choice: AppLanguage

    /// The `.lproj` in effect. The root view keys its identity on this, so a
    /// switch redraws the tree once with every string re-read.
    private(set) var localization: String

    /// The locale for the SwiftUI environment.
    private(set) var locale: Locale

    /// Set by the app at launch, for the reminder reschedule.
    var modelContainer: ModelContainer?

    private init() {
        choice = AppLanguageRuntime.choice
        localization = AppLanguageRuntime.localization
        locale = AppLanguageRuntime.locale
    }

    /// Apply the stored choice before anything reads a string. A choice made in
    /// iOS's per-app language page lands in the same `AppleLanguages`, so it is
    /// picked up here too, and the mirror is brought in line for the extensions.
    nonisolated static func applyAtLaunch(group: UserDefaults? = UserDefaults(suiteName: AppIdentity.appGroup)) {
        let stored = AppLanguageStore.storedChoice()
        if AppLanguageStore.mirroredChoice(in: group) != stored {
            AppLanguageStore.mirror(stored, in: group)
        }
        AppLanguageRuntime.apply(stored)
        ContentLanguage.refresh()
    }

    func select(_ newChoice: AppLanguage) {
        guard newChoice != choice else { return }
        AppLanguageStore.save(newChoice, group: UserDefaults(suiteName: AppIdentity.appGroup))
        AppLanguageRuntime.apply(newChoice)
        ContentLanguage.refresh()
        choice = newChoice
        Task { await settle() }
    }

    /// Re-resolve what the old language left behind, then redraw. The catalog
    /// reloads before the redraw so the rebuilt tree never reads a cold store.
    private func settle() async {
        await SubstanceStore.shared.reloadForLanguageChange()
        InteractionChecker.invalidateRuleCopy()
        localization = AppLanguageRuntime.localization
        locale = AppLanguageRuntime.locale

        DoseNotificationManager.registerCategories()
        if let modelContainer {
            await DoseNotificationManager.syncMedRemindersIfNeeded(container: modelContainer)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
