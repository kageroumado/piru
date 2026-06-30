import Foundation
import Observation
import OSLog
import SwiftData

private nonisolated let customSubstanceLogger = Logger(subsystem: "dev.yumeji.piru", category: "CustomSubstance")

/// A user-defined substance, persisted as JSON in App Group UserDefaults.
/// We intentionally avoid SwiftData here: custom substances were added to the
/// schema after the initial app release, and SwiftData's auto-migration for
/// newly-added @Model types has proved unreliable — silently dropping inserts
/// on stores created before the schema change.
struct CustomSubstanceEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    /// Optional personal display label. When set, the substance is *shown* as
    /// this everywhere (Journal, Library, detail, exports) while `name` stays the
    /// canonical identity used for logging/lookup — so e.g. a user can log "THC"
    /// but see it labelled "joint" without breaking existing dose history.
    /// Added v1.4; decoders treat missing as `nil`.
    var displayName: String?
    var category: SubstanceCategory
    var defaultRoute: RouteOfAdministration
    var unit: String
    var notes: String
    /// Optional personal dose ladder for the default route. When set on an entry
    /// that overrides a library substance, it replaces that route's dose tiers;
    /// for a net-new custom it provides dose guidance the library can't. Added v1.4.
    var doses: DoseRange?
    /// Optional pharmacokinetic profile. When present, the substance participates
    /// in the same timeline / Live-Activity / PK-curve rendering as a library
    /// substance. Added in v1.3 — decoders treat missing as `nil` for
    /// backward compatibility with pre-1.3 stored entries.
    var duration: DurationProfile?
    /// Optional personal half-life (minutes). Overrides the library value when set. Added v1.4.
    var halfLifeMinutes: Double?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        displayName: String? = nil,
        category: SubstanceCategory = .other,
        defaultRoute: RouteOfAdministration = .oral,
        unit: String = "mg",
        notes: String = "",
        doses: DoseRange? = nil,
        duration: DurationProfile? = nil,
        halfLifeMinutes: Double? = nil,
        createdAt: Date = .now,
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.category = category
        self.defaultRoute = defaultRoute
        self.unit = unit
        self.notes = notes
        self.doses = doses
        self.duration = duration
        self.halfLifeMinutes = halfLifeMinutes
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case displayName
        case category
        case defaultRoute
        case unit
        case notes
        case doses
        case duration
        case halfLifeMinutes
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        category = try c.decode(SubstanceCategory.self, forKey: .category)
        defaultRoute = try c.decode(RouteOfAdministration.self, forKey: .defaultRoute)
        unit = try c.decode(String.self, forKey: .unit)
        notes = try c.decode(String.self, forKey: .notes)
        doses = try c.decodeIfPresent(DoseRange.self, forKey: .doses)
        duration = try c.decodeIfPresent(DurationProfile.self, forKey: .duration)
        halfLifeMinutes = try c.decodeIfPresent(Double.self, forKey: .halfLifeMinutes)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    /// The label to show the user — the personal override when set, else the name.
    var resolvedDisplayName: String {
        if let displayName, !displayName.trimmingCharacters(in: .whitespaces).isEmpty {
            return displayName
        }
        return name
    }

    @MainActor var asSubstance: Substance {
        let trimmedDisplay = displayName?.trimmingCharacters(in: .whitespaces)
        return Substance(
            name: name,
            displayName: (trimmedDisplay?.isEmpty == false) ? trimmedDisplay : nil,
            aliases: [],
            category: category,
            defaultRoute: defaultRoute,
            routes: [SubstanceRoute(route: defaultRoute, unit: unit, doses: doses ?? DoseRange(), duration: duration)],
            effects: [],
            halfLifeMinutes: halfLifeMinutes,
            sources: [Self.userDefinedSource],
        )
    }

    /// Slug appended to ``Substance/sources`` whenever a user-defined entry has
    /// contributed data to a resolved substance. Used by the detail view to
    /// surface "User-defined" attribution and by import logic to recognise its
    /// own writes on round-trip.
    static let userDefinedSource = "user-defined"
}

// MARK: - Substance overlay

extension Substance {
    /// Returns a copy of this library substance with the user-defined entry's
    /// personal data overlaid: display name, dose ladder, duration, and
    /// half-life for the matching route (appended as a new route when the
    /// library has none for it). Fields the entry leaves unset fall through to
    /// the library value — personal overrides fill or correct library data, they
    /// don't erase it. `name` (the canonical identity used for logging/lookup) is
    /// never changed; only `displayName` is.
    func applyingOverride(from custom: CustomSubstanceEntry) -> Substance {
        let trimmedDisplay = custom.displayName?.trimmingCharacters(in: .whitespaces)
        let hasDisplay = (trimmedDisplay?.isEmpty == false)
        // Nothing to contribute → return unchanged so an empty entry doesn't
        // falsely mark the substance as personalized (user-defined source).
        guard hasDisplay || custom.doses != nil || custom.duration != nil || custom.halfLifeMinutes != nil else {
            return self
        }
        let overriddenDisplayName = hasDisplay ? trimmedDisplay : displayName

        var updatedRoutes = routes
        if let idx = updatedRoutes.firstIndex(where: { $0.route == custom.defaultRoute }) {
            let existing = updatedRoutes[idx]
            updatedRoutes[idx] = SubstanceRoute(
                route: existing.route,
                unit: existing.unit,
                doses: custom.doses ?? existing.doses,
                duration: custom.duration ?? existing.duration,
            )
        } else if custom.doses != nil || custom.duration != nil {
            updatedRoutes.append(SubstanceRoute(
                route: custom.defaultRoute,
                unit: custom.unit,
                doses: custom.doses ?? DoseRange(),
                duration: custom.duration,
            ))
        }

        let mergedSources = sources.contains(CustomSubstanceEntry.userDefinedSource)
            ? sources
            : sources + [CustomSubstanceEntry.userDefinedSource]

        return Substance(
            name: name,
            displayName: overriddenDisplayName,
            aliases: aliases,
            category: category,
            defaultRoute: defaultRoute,
            routes: updatedRoutes,
            effects: effects,
            subjectiveEffects: subjectiveEffects,
            toleranceInfo: toleranceInfo,
            halfLifeMinutes: custom.halfLifeMinutes ?? halfLifeMinutes,
            sources: mergedSources,
            mechanismOfAction: mechanismOfAction,
            tags: tags,
            displayClass: displayClass,
            regulatoryStatus: regulatoryStatus,
            durationImplausible: durationImplausible,
            indications: indications,
            contraindications: contraindications,
            diazepamEquivalent: diazepamEquivalent,
            cas: cas,
            inchikey: inchikey,
            formula: formula,
            pubchemCID: pubchemCID,
            popularity: popularity,
        )
    }
}

/// Observable singleton storing custom substances in the SwiftData store, so
/// they're backed up and recovered with the rest of the user's data.
///
/// Backed by ``CustomSubstanceRecord`` (in `Shared/`); the value-type
/// ``CustomSubstanceEntry`` stays the public currency so the ~15 read sites and
/// the overlay engine are unchanged. They were *formerly* a JSON blob in
/// App-Group `UserDefaults` (key `piru.customSubstances.v1`); ``configure(container:)``
/// runs a one-time, verify-before-delete migration of that blob into the store.
///
/// A lightweight `[canonicalName.lowercased(): displayName]` map is still
/// mirrored into the app group (``displayNameMapKey``) so the widget/Live-Activity
/// targets can apply personal display names without reading the store.
@Observable @MainActor
final class CustomSubstanceStore {
    static let shared = CustomSubstanceStore()

    private static let appGroupID = "group.dev.yumeji.piru"
    /// Legacy App-Group `UserDefaults` key for the pre-migration JSON blob. Read
    /// once by ``migrateFromDefaultsIfNeeded()`` and removed after the rows are
    /// verified in the store.
    private static let legacyStorageKey = "piru.customSubstances.v1"
    /// Lightweight `[canonicalName.lowercased(): displayName]` map mirrored into
    /// the app group so the widget/Live-Activity targets can apply personal
    /// display names without linking the full custom-substance model.
    static let displayNameMapKey = "piru.substanceDisplayNames.v1"

    private(set) var all: [CustomSubstanceEntry] = []

    /// The SwiftData context. `nil` until ``configure(container:)`` (or
    /// ``forTesting(context:)``) binds it — reads return empty, writes no-op.
    private var context: ModelContext?

    /// Strong reference to the context's container. A `ModelContext` does **not**
    /// keep its `ModelContainer` alive, so without this the container can be
    /// deallocated out from under us (e.g. a test helper that builds a container,
    /// hands us its `mainContext`, and returns) — and the next `fetch` traps.
    private var heldContainer: ModelContainer?

    /// App-group defaults, used only for the legacy-blob migration and the
    /// widget display-name mirror — never as the substances' system of record.
    private let mirrorDefaults: UserDefaults

    private init(mirrorDefaults: UserDefaults) {
        self.mirrorDefaults = mirrorDefaults
    }

    private convenience init() {
        self.init(mirrorDefaults: UserDefaults(suiteName: Self.appGroupID) ?? .standard)
    }

    /// Bind to the app's shared container at launch (before any view reads
    /// custom substances), run the one-time `UserDefaults` → store migration,
    /// and load `all`. Idempotent.
    func configure(container: ModelContainer) {
        heldContainer = container
        context = container.mainContext
        migrateFromDefaultsIfNeeded()
        reload()
    }

    /// Test-only factory bound to an explicit (usually in-memory) context. The
    /// mirror/migration defaults default to a throwaway suite so tests never
    /// touch the real App Group; migration tests pass an explicit one carrying a
    /// seeded legacy blob. Runs the same migrate-then-load as ``configure(container:)``.
    static func forTesting(
        context: ModelContext,
        mirrorDefaults: UserDefaults? = nil,
    ) -> CustomSubstanceStore {
        let defaults = mirrorDefaults ?? UserDefaults(suiteName: "piru.tests.\(UUID().uuidString)")!
        let store = CustomSubstanceStore(mirrorDefaults: defaults)
        store.heldContainer = context.container
        store.context = context
        store.migrateFromDefaultsIfNeeded()
        store.reload()
        return store
    }

    // MARK: - Mutations

    func add(_ entry: CustomSubstanceEntry) {
        guard let context else { return }
        // Enforce unique lowercased names — replace any existing same-named
        // custom rather than inserting a second, so lookups stay unambiguous.
        let needle = entry.name.lowercased()
        for record in fetchRecords() where record.name.lowercased() == needle {
            context.delete(record)
        }
        context.insert(CustomSubstanceRecord(entry))
        save()
        reload()
    }

    func update(_ entry: CustomSubstanceEntry) {
        guard let context else { return }
        if let record = fetchRecords().first(where: { $0.id == entry.id }) {
            record.apply(entry)
        } else {
            context.insert(CustomSubstanceRecord(entry))
        }
        save()
        reload()
    }

    func delete(_ entry: CustomSubstanceEntry) {
        guard let context else { return }
        for record in fetchRecords() where record.id == entry.id {
            context.delete(record)
        }
        save()
        reload()
    }

    func delete(at offsets: IndexSet) {
        // `all` is the sorted projection the UI renders, so offsets index it.
        let targets = offsets.compactMap { $0 < all.count ? all[$0] : nil }
        guard !targets.isEmpty, let context else { return }
        let ids = Set(targets.map(\.id))
        for record in fetchRecords() where ids.contains(record.id) {
            context.delete(record)
        }
        save()
        reload()
    }

    // MARK: - Queries

    /// Case-insensitive name lookup.
    func contains(name: String) -> Bool {
        let needle = name.lowercased()
        return all.contains { $0.name.lowercased() == needle }
    }

    func first(whereName name: String) -> CustomSubstanceEntry? {
        let needle = name.lowercased()
        return all.first { $0.name.lowercased() == needle }
    }

    /// Find an entry by its personal display name (case-insensitive). Lets a
    /// relabelled substance be located by the name the user gave it — e.g.
    /// "joint" resolving to the entry whose canonical name is "THC".
    func first(whereDisplayName displayName: String) -> CustomSubstanceEntry? {
        let needle = displayName.lowercased()
        return all.first {
            guard let dn = $0.displayName?.trimmingCharacters(in: .whitespaces), !dn.isEmpty else { return false }
            return dn.lowercased() == needle
        }
    }

    /// The label to show for a substance identified by its canonical name. When
    /// a personal override sets a display name (e.g. THC → "joint") that wins;
    /// otherwise `fallback` (typically the library's `displayTitle`) is used, or
    /// the canonical name itself when no fallback is given. Use this at every
    /// site that renders a substance name from a raw `DoseEntry.substance` string.
    func displayName(for canonicalName: String, fallback: String? = nil) -> String {
        if let entry = first(whereName: canonicalName),
           let dn = entry.displayName?.trimmingCharacters(in: .whitespaces), !dn.isEmpty {
            return dn
        }
        return fallback ?? canonicalName
    }

    /// The personal display-name override for `substance`, or `nil` when none
    /// differs from the library title. Resolve this in the parent list (which
    /// holds the store) and pass the value into `SubstanceRowView` so each row
    /// doesn't subscribe to the whole override set — one personalization then
    /// re-evaluates only the affected row, not every visible row.
    func personalName(for substance: Substance) -> String? {
        let resolved = displayName(for: substance.name, fallback: substance.displayTitle)
        return resolved == substance.displayTitle ? nil : resolved
    }

    // MARK: - Persistence

    private func fetchRecords() -> [CustomSubstanceRecord] {
        guard let context else { return [] }
        return (try? context.fetch(FetchDescriptor<CustomSubstanceRecord>())) ?? []
    }

    private func save() {
        try? context?.save()
    }

    /// Refresh the in-memory `all` projection from the store and re-publish the
    /// widget display-name mirror. Called after every mutation.
    private func reload() {
        all = fetchRecords()
            .map(\.asEntry)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        writeMirror()
    }

    /// Mirror the personal display names into a plain `[String: String]` map the
    /// widget/Live-Activity targets can read without the full model.
    private func writeMirror() {
        let displayMap = Dictionary(
            all.compactMap { entry -> (String, String)? in
                guard let dn = entry.displayName?.trimmingCharacters(in: .whitespaces), !dn.isEmpty else { return nil }
                return (entry.name.lowercased(), dn)
            },
            uniquingKeysWith: { first, _ in first },
        )
        mirrorDefaults.set(displayMap, forKey: Self.displayNameMapKey)
    }

    // MARK: - One-time migration off UserDefaults

    /// Copy the legacy `UserDefaults` JSON blob into the store **once**, verify
    /// every entry landed, then delete the blob. If verification fails (the
    /// historical "SwiftData silently drops the insert" failure mode), the blob
    /// is *kept* so the next launch retries — data is never lost to a half-done
    /// migration. Idempotent: a no-op once the blob is gone.
    private func migrateFromDefaultsIfNeeded() {
        guard let context, let data = mirrorDefaults.data(forKey: Self.legacyStorageKey) else { return }

        guard let entries = try? JSONDecoder().decode([CustomSubstanceEntry].self, from: data),
              !entries.isEmpty
        else {
            // Empty or unreadable blob — nothing to preserve, clear it.
            mirrorDefaults.removeObject(forKey: Self.legacyStorageKey)
            return
        }

        var present = Set(fetchRecords().map { $0.name.lowercased() })
        for entry in entries where !present.contains(entry.name.lowercased()) {
            context.insert(CustomSubstanceRecord(entry))
            present.insert(entry.name.lowercased())
        }
        save()

        // Verify every legacy substance is now represented in the store before
        // discarding the blob — this catches a dropped insert / failed save.
        let stored = Set(fetchRecords().map { $0.name.lowercased() })
        let migrated = entries.allSatisfy { stored.contains($0.name.lowercased()) }
        if migrated {
            mirrorDefaults.removeObject(forKey: Self.legacyStorageKey)
            customSubstanceLogger.notice("Migrated \(entries.count, privacy: .public) custom substances from UserDefaults into the store.")
        } else {
            customSubstanceLogger.error("Custom-substance migration failed verification; keeping the UserDefaults blob to retry next launch.")
        }
    }
}

// MARK: - Record ⇄ Entry mapping

/// Bridges the store-resident ``CustomSubstanceRecord`` (primitive fields, in
/// `Shared/`) and the typed value-type ``CustomSubstanceEntry`` (the UI/overlay
/// currency). Lives in the Piru target because it touches `DoseRange`,
/// `DurationProfile`, and `SubstanceCategory`, which aren't in `Shared/`.
@MainActor
extension CustomSubstanceRecord {
    /// Build a store record from a value-type entry (Codable sub-structs encode
    /// to opaque JSON blobs the widget never has to decode). `@MainActor` because
    /// `DoseRange`/`DurationProfile`/`CustomSubstanceEntry` carry main-actor-isolated
    /// Codable conformances under the module's default isolation.
    convenience init(_ entry: CustomSubstanceEntry) {
        self.init(
            id: entry.id,
            name: entry.name,
            displayName: entry.displayName,
            categoryRaw: entry.category.rawValue,
            defaultRouteRaw: entry.defaultRoute.rawValue,
            unit: entry.unit,
            notes: entry.notes,
            dosesData: entry.doses.flatMap { try? JSONEncoder().encode($0) },
            durationData: entry.duration.flatMap { try? JSONEncoder().encode($0) },
            halfLifeMinutes: entry.halfLifeMinutes,
            createdAt: entry.createdAt,
        )
    }

    /// Overwrite this record's mutable fields from an edited entry. `id` is the
    /// identity and `createdAt` is provenance — both are left untouched.
    func apply(_ entry: CustomSubstanceEntry) {
        name = entry.name
        displayName = entry.displayName
        categoryRaw = entry.category.rawValue
        defaultRouteRaw = entry.defaultRoute.rawValue
        unit = entry.unit
        notes = entry.notes
        dosesData = entry.doses.flatMap { try? JSONEncoder().encode($0) }
        durationData = entry.duration.flatMap { try? JSONEncoder().encode($0) }
        halfLifeMinutes = entry.halfLifeMinutes
    }

    /// The value-type projection consumed by the UI and the overlay engine.
    var asEntry: CustomSubstanceEntry {
        CustomSubstanceEntry(
            id: id,
            name: name,
            displayName: displayName,
            category: SubstanceCategory(rawValue: categoryRaw) ?? .other,
            defaultRoute: RouteOfAdministration(rawValue: defaultRouteRaw) ?? .oral,
            unit: unit,
            notes: notes,
            doses: dosesData.flatMap { try? JSONDecoder().decode(DoseRange.self, from: $0) },
            duration: durationData.flatMap { try? JSONDecoder().decode(DurationProfile.self, from: $0) },
            halfLifeMinutes: halfLifeMinutes,
            createdAt: createdAt,
        )
    }
}
