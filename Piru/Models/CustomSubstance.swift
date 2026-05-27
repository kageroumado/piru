import Foundation
import Observation

/// A user-defined substance, persisted as JSON in App Group UserDefaults.
/// We intentionally avoid SwiftData here: custom substances were added to the
/// schema after the initial app release, and SwiftData's auto-migration for
/// newly-added @Model types has proved unreliable — silently dropping inserts
/// on stores created before the schema change.
struct CustomSubstanceEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var category: SubstanceCategory
    var defaultRoute: RouteOfAdministration
    var unit: String
    var notes: String
    /// Optional pharmacokinetic profile. When present, the substance participates
    /// in the same timeline / Live-Activity / PK-curve rendering as a library
    /// substance. Added in v1.3 — decoders treat missing as `nil` for
    /// backward compatibility with pre-1.3 stored entries.
    var duration: DurationProfile?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        category: SubstanceCategory = .other,
        defaultRoute: RouteOfAdministration = .oral,
        unit: String = "mg",
        notes: String = "",
        duration: DurationProfile? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.defaultRoute = defaultRoute
        self.unit = unit
        self.notes = notes
        self.duration = duration
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, category, defaultRoute, unit, notes, duration, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(SubstanceCategory.self, forKey: .category)
        defaultRoute = try c.decode(RouteOfAdministration.self, forKey: .defaultRoute)
        unit = try c.decode(String.self, forKey: .unit)
        notes = try c.decode(String.self, forKey: .notes)
        duration = try c.decodeIfPresent(DurationProfile.self, forKey: .duration)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    @MainActor var asSubstance: Substance {
        Substance(
            name: name,
            aliases: [],
            category: category,
            defaultRoute: defaultRoute,
            routes: [SubstanceRoute(route: defaultRoute, unit: unit, doses: DoseRange(), duration: duration)],
            effects: [],
            sources: [Self.userDefinedSource]
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
    /// data overlaid. Currently the custom's ``CustomSubstanceEntry/duration``
    /// replaces the library duration for the matching route (or is appended as
    /// a new route when the library has no route for it). All other library
    /// fields are preserved — custom substances are meant to fill gaps in (or
    /// correct) library data, not erase it.
    func applyingOverride(from custom: CustomSubstanceEntry) -> Substance {
        guard let customDuration = custom.duration else { return self }

        var updatedRoutes = routes
        if let idx = updatedRoutes.firstIndex(where: { $0.route == custom.defaultRoute }) {
            let existing = updatedRoutes[idx]
            updatedRoutes[idx] = SubstanceRoute(
                route: existing.route,
                unit: existing.unit,
                doses: existing.doses,
                duration: customDuration
            )
        } else {
            updatedRoutes.append(SubstanceRoute(
                route: custom.defaultRoute,
                unit: custom.unit,
                doses: DoseRange(),
                duration: customDuration
            ))
        }

        let mergedSources = sources.contains(CustomSubstanceEntry.userDefinedSource)
            ? sources
            : sources + [CustomSubstanceEntry.userDefinedSource]

        return Substance(
            name: name,
            aliases: aliases,
            category: category,
            defaultRoute: defaultRoute,
            routes: updatedRoutes,
            effects: effects,
            subjectiveEffects: subjectiveEffects,
            toleranceInfo: toleranceInfo,
            halfLifeMinutes: halfLifeMinutes,
            sources: mergedSources,
            mechanismOfAction: mechanismOfAction,
            tags: tags
        )
    }
}

/// Observable singleton storing custom substances as JSON in the App Group
/// UserDefaults. Both the main app and widget/Live-Activity extensions can
/// read from the same suite.
@Observable @MainActor
final class CustomSubstanceStore {
    static let shared = CustomSubstanceStore()

    private static let storageKey = "piru.customSubstances.v1"
    private static let appGroupID = "group.dev.yumeji.piru"

    private(set) var all: [CustomSubstanceEntry] = []

    private let defaults: UserDefaults

    /// Designated init used by the shared singleton; tests use `forTesting`.
    private init(defaults: UserDefaults) {
        self.defaults = defaults
        load()
    }

    private convenience init() {
        let suite = UserDefaults(suiteName: Self.appGroupID) ?? .standard
        self.init(defaults: suite)
    }

    /// Test-only factory that takes an explicit UserDefaults instance.
    static func forTesting(defaults: UserDefaults) -> CustomSubstanceStore {
        CustomSubstanceStore(defaults: defaults)
    }

    // MARK: - Mutations

    func add(_ entry: CustomSubstanceEntry) {
        all.append(entry)
        sortInPlace()
        persist()
    }

    func update(_ entry: CustomSubstanceEntry) {
        guard let idx = all.firstIndex(where: { $0.id == entry.id }) else { return }
        all[idx] = entry
        sortInPlace()
        persist()
    }

    func delete(_ entry: CustomSubstanceEntry) {
        all.removeAll { $0.id == entry.id }
        persist()
    }

    func delete(at offsets: IndexSet) {
        for idx in offsets.sorted(by: >) where idx < all.count {
            all.remove(at: idx)
        }
        persist()
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

    // MARK: - Persistence

    private func sortInPlace() {
        all.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([CustomSubstanceEntry].self, from: data) {
            all = decoded
            sortInPlace()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
