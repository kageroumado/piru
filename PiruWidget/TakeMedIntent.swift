import AppIntents
import Foundation
import SwiftData
import WidgetKit

// MARK: - Take Med Intent

/// Logs one dose of a scheduled med from the Today's Meds widget — the whole
/// point of the widget: take a med from the Home Screen without opening the
/// app, without a notification ever buzzing.
///
/// ## What the write does (and deliberately doesn't do)
/// The intent inserts a `DoseEntry` stamped with the med's full template —
/// substance, amount, unit, route, and the PSID identity facets
/// (`substanceUID`/`isomer`/`releaseForm`/`saltForm`/`productName`) — so the
/// entry's `identityKey` equals the item's and every "taken today" check
/// (widget, MyMedsCard, adherence) matches it immediately. `isBackgroundMed`
/// is copied from the item.
///
/// The entry's `session` is left `nil`: `SessionService.assignSession` is
/// app-target (it pulls in the substance catalog and Live Activity stack) and
/// must not move into the extension. That's safe because the app sweeps
/// session-less doses on **every** launch — `PiruApp`'s root `.task` calls
/// `SessionService.ensureSessionsPopulated(in:)`, which clusters all
/// `session == nil` doses (honoring `isBackgroundMed`, so a background med
/// forms a quiet maintenance session). A widget-logged dose is therefore
/// adopted on the next app open; until then it simply renders as a plain
/// journal entry. The app-side bookkeeping funnel (PSID resolve, tolerance,
/// notifications) likewise catches up on next launch.
struct TakeMedIntent: AppIntent {
    static let title: LocalizedStringResource = "Take Med"
    static let description = IntentDescription("Logs one dose of a scheduled med.")
    /// Widget-button plumbing only — the identity-key parameter is meaningless
    /// in the Shortcuts gallery.
    static let isDiscoverable = false

    /// The target med's substance-identity key (``DailyDoseItem/identityKey``).
    @Parameter(title: "Med identity")
    var identityKey: String

    init() {}

    init(identityKey: String) {
        self.identityKey = identityKey
    }

    func perform() async throws -> some IntentResult {
        MedIntentLogger.logRemainingDose { $0.identityKey == identityKey }
        return .result()
    }
}

// MARK: - Take Supplements Intent

/// Logs one dose of every remaining quiet ("Supplements") med — the widget's
/// counterpart of MyMedsCard's Take All pill on the collapsed Supplements row.
struct TakeQuietMedsIntent: AppIntent {
    static let title: LocalizedStringResource = "Take Supplements"
    static let description = IntentDescription("Logs your remaining supplements for today.")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        MedIntentLogger.logRemainingDose { $0.isQuiet }
        return .result()
    }
}

// MARK: - Shared write path

enum MedIntentLogger {
    /// For each due, non-PRN med matching `include` that still has an
    /// unsatisfied dose slot today, logs exactly ONE dose now. Idempotent
    /// under stale-widget double taps: a med whose slots are all satisfied is
    /// skipped, so a second tap on an outdated snapshot can't over-log.
    static func logRemainingDose(matching include: (DailyDoseItem) -> Bool) {
        guard let container = WidgetStoreAccess.makeWritableContainer() else { return }
        let context = ModelContext(container)
        let now = Date.now

        let items = (try? context.fetch(
            FetchDescriptor<DailyDoseItem>(sortBy: [SortDescriptor(\.sortOrder)]),
        )) ?? []

        let dayStart = Calendar.current.startOfDay(for: now)
        let todayEntries = (try? context.fetch(
            FetchDescriptor<DoseEntry>(predicate: #Predicate { $0.timestamp >= dayStart }),
        )) ?? []

        let colors = (try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []
        var coloredNames = Set(colors.map { $0.substance.lowercased() })

        var loggedAny = false
        for item in items where !item.isAsNeeded && include(item) {
            guard MedSchedule.isDue(
                startDate: item.startDate, frequency: item.frequency,
                frequencyDays: item.frequencyDays, on: now,
            ) else { continue }

            let expected = max(1, item.reminderTimesMinutes.count)
            let matched = todayEntries.count { entry in
                MedSchedule.matches(
                    entryKey: entry.identityKey, entryName: entry.substance, entryRoute: entry.route,
                    itemKey: item.identityKey, itemName: item.substance, itemRoute: item.route,
                )
            }
            guard matched < expected else { continue }

            let entry = DoseEntry(
                substance: item.substance,
                amount: item.amount,
                unit: item.unit,
                route: item.route,
                saltForm: item.saltForm,
                isomer: item.isomer,
                releaseForm: item.releaseForm,
                productName: item.productName,
                substanceUID: item.substanceUID,
                timestamp: now,
                isBackgroundMed: item.isBackgroundMed,
            )
            context.insert(entry)
            loggedAny = true

            // Deterministic color on first log, mirroring MyMedsCard — so the
            // journal row doesn't render fallback pink until the next in-app log.
            if !coloredNames.contains(item.substance.lowercased()) {
                context.insert(SubstanceColor(
                    substance: item.substance,
                    hexColor: PresetColor.deterministic(for: item.substance).hex,
                ))
                coloredNames.insert(item.substance.lowercased())
            }
        }

        guard loggedAny else { return }
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
