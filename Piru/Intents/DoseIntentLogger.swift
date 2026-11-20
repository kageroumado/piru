import Foundation
import SwiftData

/// The headless save behind the Log Dose action: the quick-log tray's commit
/// with no tray on screen. The dose is staged through ``DoseTrayModel`` so its
/// release form, isomer, identity and display snapshot derive exactly as a
/// tapped chip's do, then written through ``DoseLogService/logBatch`` with the
/// same chip curation and notification bookkeeping as the tray's Log button.
@MainActor
enum DoseIntentLogger {
    /// The app's container, set by `PiruApp.init` right after it opens the
    /// store. An intent runs in the app process with no view hierarchy to pull
    /// a context from; App Intents launch the app in the background first, so
    /// the store is open before `perform()` runs.
    static var modelContainer: ModelContainer?

    /// One dose as an automation describes it. Everything but the name is
    /// optional and defaults the way the tray would: the substance's default
    /// route (an ester's injection route), that route's unit, now.
    struct Request {
        /// The name the automation used: canonical, a brand, a synonym, an
        /// ester, or a custom substance's name. What it names beyond the
        /// substance (the product, the ester) stays on the dose.
        var name: String
        /// `nil` logs the dose with its amount unknown, which is what "I took
        /// some" means; the journal never invents a number.
        var amount: Double?
        var unit: String?
        var route: RouteOfAdministration?
        var time: Date?
        /// Committed onto oral doses only, like the tray's chip.
        var meal: MealState?
        var notes: String?
        var tags: [String] = []
    }

    enum Failure: Error, CustomLocalizedStringResourceConvertible {
        case unknownSubstance(String)
        case storeUnavailable

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case let .unknownSubstance(name): "Piru does not know a substance named “\(name)”."
            case .storeUnavailable: "The journal could not be opened."
            }
        }
    }

    /// Save what the request names to the app's journal: one entry for a
    /// compound, one per component for a combination product.
    static func log(_ request: Request) async throws -> [DoseEntry] {
        guard let container = modelContainer else { throw Failure.storeUnavailable }
        await SubstanceStore.shared.ensureAllLoaded()
        return try await logAll(request, in: container.mainContext)
    }

    /// Save one dose into `context` and return it; for a combination product,
    /// its first component. The catalog must be loaded.
    static func log(_ request: Request, in context: ModelContext, customs: [CustomSubstanceEntry]? = nil) async throws -> DoseEntry {
        guard let first = try await logAll(request, in: context, customs: customs).first else {
            throw Failure.unknownSubstance(request.name)
        }
        return first
    }

    /// Save every entry the request produces into `context`. `customs` stands
    /// in for the custom-substance store (tests); the catalog must be loaded.
    static func logAll(_ request: Request, in context: ModelContext, customs: [CustomSubstanceEntry]? = nil) async throws -> [DoseEntry] {
        let staged: [StagedDose]
        if let combination = CustomSubstanceStore.combination(named: request.name, in: customs ?? CustomSubstanceStore.shared.all) {
            staged = stage(request, as: combination)
        } else if let named = await SubstanceLibrary.resolveNamed(request.name) {
            staged = [stage(request, as: named)]
        } else {
            throw Failure.unknownSubstance(request.name)
        }
        guard !staged.isEmpty else { throw Failure.unknownSubstance(request.name) }

        let timestamp = request.time ?? .now
        let entries = staged.map { $0.makeEntry(timestamp: timestamp, tags: request.tags, meal: request.meal) }

        // Prior entries feed the redose and cumulative-dose checks, as the tray
        // passes them; fetched before the insert so the new doses are not in them.
        let recents = recentEntries(in: context)
        let colors = (try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []
        let fixedOrder = UserDefaults.standard.bool(forKey: QuickLogManager.fixedOrderDefaultsKey)
        // An unknown amount tapped no chip and mints none.
        let curation: [QuickLogManager.LoggedDose] = staged.filter { !$0.isUnknownAmount }.map { row in
            QuickLogManager.LoggedDose(
                substance: row.substanceName, route: row.route, amount: row.totalAmount, unit: row.unit,
                substanceUID: row.substanceUID, isomer: row.isomer,
                releaseForm: row.releaseForm, saltForm: row.saltForm, productName: row.productName,
            )
        }
        DoseLogService.shared.logBatch(
            zip(entries, staged).map { ($0, $1.librarySubstance) },
            colors: colors,
            in: context,
            beforeSave: {
                QuickLogManager.record(curation, fixedOrder: fixedOrder, context: context, save: false)
            },
            deferredBookkeeping: {
                for entry in entries {
                    DoseNotificationManager.doseLogged(entry: entry, recentEntries: recents)
                }
            },
        )
        return entries
    }

    /// A combination product as the tray stages it: one row per component,
    /// the request's amount counting units of the product (two co-codamol),
    /// each component on its own route and unit. A request's route and unit
    /// name a single dose and do not apply here. For a liquid product the
    /// amount is the volume taken in mL (0.25 mL of a 2 g/mL solution), and
    /// each component stages at volume × its amount per mL.
    private static func stage(_ request: Request, as combination: CustomSubstanceEntry) -> [StagedDose] {
        let tray = DoseTrayModel()
        if combination.isLiquidCombination {
            tray.stage(combination: combination, volumeML: CombinationComponent.volumeML(for: request.amount))
        } else {
            tray.stage(combination: combination, quantity: CombinationComponent.units(for: request.amount))
        }
        let note = request.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return tray.staged.map { row in
            var row = row
            row.note = note
            return row
        }
    }

    /// The dose as the tray would stage it from a search hit: the request's
    /// route, unit and amount over the substance's defaults, under the product
    /// or ester the name carried.
    private static func stage(_ request: Request, as named: NamedSubstance) -> StagedDose {
        let substance = named.substance
        let route = request.route ?? named.esterRoute ?? substance.defaultRoute
        let unit = request.unit?.trimmingCharacters(in: .whitespaces).nonEmpty
            ?? substance.unit(for: route, saltForm: named.saltForm)
        let tray = DoseTrayModel()
        tray.stage(
            substance: substance.name,
            route: route,
            amount: request.amount ?? 0,
            unit: unit,
            tint: nil,
            librarySubstance: substance,
            productName: named.productName,
            saltForm: named.saltForm,
        )
        var staged = tray.staged[0]
        staged.isUnknownAmount = request.amount == nil
        staged.note = request.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return staged
    }

    private static func recentEntries(in context: ModelContext) -> [DoseEntry] {
        var descriptor = FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 25
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Dialog

    /// What the action says back for everything it saved: the one dose's
    /// summary, or for a combination "Co-codamol: 1000 mg Acetaminophen,
    /// 60 mg Codeine, oral, 9:30".
    static func summary(for entries: [DoseEntry]) -> String {
        guard entries.count > 1, let first = entries.first else {
            return entries.first.map(summary(for:)) ?? ""
        }
        let doses = entries.map { entry in
            entry.isUnknownDose
                ? DoseTitle.resolve(for: entry)
                : "\(entry.amount.doseFormatted) \(entry.unit) \(DoseTitle.resolve(for: entry))"
        }.joined(separator: ", ")
        let routes = Set(entries.map(\.route))
        var parts = [first.combinationName.map { "\($0): \(doses)" } ?? doses]
        if routes.count == 1 {
            parts.append(String(localized: first.route.localizedName))
        }
        parts.append(clock(for: first.timestamp))
        return parts.joined(separator: ", ")
    }

    /// "27 mg Concerta, oral, 9:30" — what the action says back. The title is
    /// the journal row's, the time is today's clock or a dated one.
    static func summary(for entry: DoseEntry) -> String {
        let amount = entry.isUnknownDose
            ? String(localized: "unknown amount")
            : "\(entry.amount.doseFormatted) \(entry.unit)"
        let route = String(localized: entry.route.localizedName)
        return [
            entry.isUnknownDose ? "\(DoseTitle.resolve(for: entry)) (\(amount))" : "\(amount) \(DoseTitle.resolve(for: entry))",
            route,
            clock(for: entry.timestamp),
        ].joined(separator: ", ")
    }

    /// Today's clock time, or a dated one.
    private static func clock(for timestamp: Date) -> String {
        Calendar.current.isDateInToday(timestamp)
            ? timestamp.formatted(date: .omitted, time: .shortened)
            : timestamp.formatted(date: .abbreviated, time: .shortened)
    }
}

private nonisolated extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
