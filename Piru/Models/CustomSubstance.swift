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

/// Observable singleton storing custom substances as JSON in the App Group
/// UserDefaults. Both the main app and widget/Live-Activity extensions can
/// read from the same suite.
@Observable @MainActor
final class CustomSubstanceStore {
    static let shared = CustomSubstanceStore()

    private static let storageKey = "piru.customSubstances.v1"
    private static let appGroupID = "group.dev.yumeji.piru"
    /// Lightweight `[canonicalName.lowercased(): displayName]` map mirrored into
    /// the app group so the widget/Live-Activity targets can apply personal
    /// display names without linking the full custom-substance model.
    static let displayNameMapKey = "piru.substanceDisplayNames.v1"

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
        // Enforce unique lowercased names. A duplicate would later trap the
        // import merge (which builds a `[name: entry]` dictionary via
        // `Dictionary(_:uniquingKeysWith:)`) and the launch-time name index.
        // Replace any existing same-named custom rather than appending a second.
        all.removeAll { $0.name.lowercased() == entry.name.lowercased() }
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
        // Mirror the personal display names into a plain [String: String] map the
        // widget/Live-Activity targets can read without the full model.
        let displayMap = Dictionary(
            all.compactMap { entry -> (String, String)? in
                guard let dn = entry.displayName?.trimmingCharacters(in: .whitespaces), !dn.isEmpty else { return nil }
                return (entry.name.lowercased(), dn)
            },
            uniquingKeysWith: { first, _ in first },
        )
        defaults.set(displayMap, forKey: Self.displayNameMapKey)
    }
}
