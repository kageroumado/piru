import Foundation
import SwiftData

// MARK: - Dose Frequency

enum DoseFrequency: String, Codable, CaseIterable, Identifiable {
    case daily
    case everyOtherDay
    case weekly
    case biweekly
    case monthly
    case specificDays

    var id: String {
        rawValue
    }

    var displayName: LocalizedStringResource {
        switch self {
        case .daily: "Daily"
        case .everyOtherDay: "Every other day"
        case .weekly: "Weekly"
        case .biweekly: "Every 2 weeks"
        case .monthly: "Monthly"
        case .specificDays: "Specific days"
        }
    }

    var shortLabel: LocalizedStringResource {
        switch self {
        case .daily: "Daily"
        case .everyOtherDay: "Every 2 days"
        case .weekly: "Weekly"
        case .biweekly: "Biweekly"
        case .monthly: "Monthly"
        case .specificDays: "Custom days"
        }
    }
}

// MARK: - Model

/// A recurring medication or supplement scheduled on a fixed cadence.
///
/// SwiftData `@Model` shared across the main Piru app, the Home Screen widget
/// (`PiruWidget`), and the Lock Screen Live Activity extension
/// (`PiruLiveActivityExtension`).
///
/// ## Schedule Storage
/// - ``frequency`` is exposed as a ``DoseFrequency`` enum but persisted via
///   ``frequencyRaw`` (a `String`) so the column survives Swift-level renames.
/// - ``frequencyDays`` is exposed as `[Int]` but persisted via
///   ``frequencyDaysData`` (JSON-encoded `Data`). Arrays of value types are
///   awkward to model across SwiftData and our extension targets; JSON
///   storage keeps the schema flat and portable.
///
/// ## Schema Migration Note
/// All persisted properties have default values (e.g. `frequencyRaw`,
/// `frequencyDaysData`, `category`, `startDate`) so new fields can be added
/// non-destructively as the model evolves. When introducing a new field,
/// always supply a default so existing user data migrates without prompting.
@Model
final class DailyDoseItem {
    // Every daily-dose surface (settings, quick-log, the item form) fetches sorted by `sortOrder`.
    #Index<DailyDoseItem>([\.sortOrder])

    /// The substance's display name.
    var substance: String
    /// Quantity of one dose in ``unit``.
    var amount: Double
    /// Unit of measure for ``amount`` (e.g. `"mg"`, `"µg"`).
    var unit: String
    /// Route of administration; persisted as `rawValue` (a `String`).
    var route: RouteOfAdministration
    /// User-defined ordering within the daily list.
    var sortOrder: Int
    /// Optional category label used to group items in the UI.
    var category: String = ""

    /// The PSID identity this daily item resolves to, so its "logged today" check
    /// joins a matching dose by identity rather than a lowercased name — a
    /// "Concerta" daily item then matches a dose logged as Methylphenidate XR,
    /// which a name join never could. All `nil` for an item created before PSID
    /// (name join, as before) until the backfill resolves its ``substance``
    /// string. `productName` keeps the literal word the item was saved under.
    /// Additive optionals — a free lightweight migration.
    var substanceUID: String?
    var isomer: String?
    var releaseForm: String?
    var saltForm: String?
    var productName: String?

    /// When `true`, doses logged from this medication are *background*: they
    /// never open or extend a recreational session (they fold into the current
    /// session if one is active, otherwise form a quiet maintenance session that
    /// renders as a compact "Medications" row). Stamped onto each logged
    /// ``DoseEntry/isBackgroundMed``. Defaults `false`, so meds behave like any
    /// other dose unless the user opts in. See ``SessionClustering``.
    var isBackgroundMed: Bool = false

    // Schedule

    /// Backing storage for ``frequency``. Prefer reading/writing ``frequency``.
    var frequencyRaw: String = DoseFrequency.daily.rawValue
    /// JSON-encoded backing storage for ``frequencyDays``. Prefer reading/writing ``frequencyDays``.
    var frequencyDaysData: Data = Data()
    /// First day the schedule should be considered active.
    var startDate: Date = Date.distantPast

    /// Recurrence cadence; computed view over ``frequencyRaw``.
    var frequency: DoseFrequency {
        get { DoseFrequency(rawValue: frequencyRaw) ?? .daily }
        set { frequencyRaw = newValue.rawValue }
    }

    /// Weekday indices used when ``frequency`` is `.specificDays`.
    ///
    /// Encoded using Foundation's `Calendar` weekday convention:
    /// `1 = Sunday, 2 = Monday, …, 7 = Saturday`. Values are JSON-encoded into
    /// ``frequencyDaysData`` for SwiftData portability across extension targets.
    var frequencyDays: [Int] {
        get { (try? JSONDecoder().decode([Int].self, from: frequencyDaysData)) ?? [] }
        set { frequencyDaysData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(
        substance: String,
        amount: Double,
        unit: String = "mg",
        route: RouteOfAdministration = .oral,
        sortOrder: Int = 0,
        category: String = "",
        frequency: DoseFrequency = .daily,
        frequencyDays: [Int] = [],
        startDate: Date = .distantPast,
        isBackgroundMed: Bool = false,
        substanceUID: String? = nil,
        isomer: String? = nil,
        releaseForm: String? = nil,
        saltForm: String? = nil,
        productName: String? = nil,
    ) {
        self.substance = substance
        self.amount = amount
        self.unit = unit
        self.route = route
        self.sortOrder = sortOrder
        self.category = category
        self.frequencyRaw = frequency.rawValue
        self.frequencyDaysData = (try? JSONEncoder().encode(frequencyDays)) ?? Data()
        self.startDate = startDate
        self.isBackgroundMed = isBackgroundMed
        self.substanceUID = substanceUID
        self.isomer = isomer
        self.releaseForm = releaseForm
        self.saltForm = saltForm
        self.productName = productName
    }

    /// This daily item's substance-identity key — joined against a dose's
    /// ``DoseEntry/identityKey`` for the "logged today" check. See
    /// ``QuickLogDose/identityKey``.
    var identityKey: String {
        QuickLogDose.identityKey(
            substanceUID: substanceUID, substance: substance,
            isomer: isomer, releaseForm: releaseForm, saltForm: saltForm,
        )
    }
}

// MARK: - Routine

/// A named set of daily-dose items — "Pre-workout", "Night" — staged together
/// from one pill on the Log screen, with an optional time of day and a
/// repeating reminder.
///
/// Items join a routine by ``DailyDoseItem/category`` `== name` (string-keyed
/// like `SubstanceColor`; no SwiftData relationship, so the schema stays flat
/// and portable across the widget targets). Renaming a routine must cascade
/// the new name to its items' `category`.
@Model
final class DoseRoutine {
    @Attribute(.unique) var name: String
    /// User-defined position in the Routines list and the Log screen pills.
    var sortOrder: Int = 0
    /// Optional time of day as minutes from midnight (420 = 7:00). Drives
    /// pill ordering and, when ``remind`` is on, the daily reminder.
    var timeMinutes: Int?
    /// Schedule a repeating daily reminder notification at ``timeMinutes``.
    var remind: Bool = false

    init(name: String, sortOrder: Int = 0, timeMinutes: Int? = nil, remind: Bool = false) {
        self.name = name
        self.sortOrder = sortOrder
        self.timeMinutes = timeMinutes
        self.remind = remind
    }

    /// `timeMinutes` as a `Date` today, for `DatePicker` round-trips and
    /// time-style formatting.
    var timeAsDate: Date? {
        get {
            guard let timeMinutes else { return nil }
            return Calendar.current.date(
                bySettingHour: timeMinutes / 60,
                minute: timeMinutes % 60,
                second: 0,
                of: .now,
            )
        }
        set {
            guard let newValue else {
                timeMinutes = nil
                return
            }
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            timeMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        }
    }
}
