import Foundation
import SwiftData

/// The system of record for user-defined ``CustomUnitPreset`` rows, and the
/// in-memory cache the ``SubstanceLibrary`` façade reads to fold each substance's
/// custom units into its ``Substance/unitAliases``. A singleton (not a view
/// `@Query`) because the aliases must be available wherever a substance is
/// resolved — the dose form's unit picker, the live dose-level preview, and the
/// commit-time unit→mass conversion — not only on the management screen.
///
/// Mirrors ``CustomSubstanceStore``: bound to the shared container at launch via
/// ``configure(container:)``, mutations route through here so the cache stays
/// fresh, and `all` is `@Observable` so the management UI updates in place.
@Observable @MainActor
final class CustomUnitStore {
    static let shared = CustomUnitStore()

    /// Every preset, sorted by substance then the user's order — the projection
    /// the management screen renders.
    private(set) var all: [CustomUnitPreset] = []

    /// `lowercased substance name → its aliases`, rebuilt on every ``reload()``.
    /// The façade's per-resolution lookup, so it must stay a cheap dictionary hit.
    private var aliasCache: [String: [UnitAlias]] = [:]

    /// The SwiftData context. `nil` until ``configure(container:)`` binds it —
    /// reads return empty, writes no-op.
    private var context: ModelContext?
    /// Strong container reference — a `ModelContext` does not retain its
    /// container, so without this a test-supplied context can be freed under us.
    private var heldContainer: ModelContainer?

    private init() {}

    /// Bind to the app's shared container at launch (before any view or lookup
    /// reads custom units) and load the cache. Idempotent.
    func configure(container: ModelContainer) {
        heldContainer = container
        context = container.mainContext
        reload()
    }

    /// Test-only factory bound to an explicit (usually in-memory) context.
    static func forTesting(context: ModelContext) -> CustomUnitStore {
        let store = CustomUnitStore()
        store.heldContainer = context.container
        store.context = context
        store.reload()
        return store
    }

    // MARK: - Queries

    /// The custom-unit aliases for a substance, by canonical (or any) name —
    /// what the façade folds into ``Substance/unitAliases``. Empty for a
    /// substance the user has defined no units for (the overwhelming majority).
    func aliases(forSubstanceNamed name: String) -> [UnitAlias] {
        aliasCache[name.lowercased()] ?? []
    }

    /// The presets for one substance, in display order — for the per-substance
    /// editor.
    func presets(forSubstanceNamed name: String) -> [CustomUnitPreset] {
        let needle = name.lowercased()
        return all.filter { $0.substanceName == needle }
    }

    /// Whether the user has defined a unit label for this substance already
    /// (case-insensitive) — so the editor can reject a duplicate.
    func hasLabel(_ label: String, forSubstanceNamed name: String) -> Bool {
        let needle = label.lowercased()
        return presets(forSubstanceNamed: name).contains { $0.label.lowercased() == needle }
    }

    // MARK: - Mutations

    func add(substanceName: String, label: String, amountPerUnit: Double, unit: String) {
        guard let context else { return }
        let order = (presets(forSubstanceNamed: substanceName).map(\.sortOrder).max() ?? -1) + 1
        context.insert(CustomUnitPreset(
            substanceName: substanceName,
            label: label,
            amountPerUnit: amountPerUnit,
            unit: unit,
            sortOrder: order,
        ))
        save()
    }

    func update(_ preset: CustomUnitPreset, label: String, amountPerUnit: Double, unit: String) {
        preset.label = label
        preset.amountPerUnit = max(0, amountPerUnit)
        preset.unit = unit
        save()
    }

    func delete(_ preset: CustomUnitPreset) {
        guard let context else { return }
        context.delete(preset)
        save()
    }

    func delete(at offsets: IndexSet, forSubstanceNamed name: String) {
        guard let context else { return }
        let rows = presets(forSubstanceNamed: name)
        for index in offsets where index < rows.count {
            context.delete(rows[index])
        }
        save()
    }

    // MARK: - Internals

    private func save() {
        try? context?.save()
        reload()
    }

    private func reload() {
        guard let context else {
            all = []
            aliasCache = [:]
            return
        }
        let fetched = (try? context.fetch(FetchDescriptor<CustomUnitPreset>())) ?? []
        all = fetched.sorted {
            $0.substanceName == $1.substanceName
                ? $0.sortOrder < $1.sortOrder
                : $0.substanceName < $1.substanceName
        }
        var cache: [String: [UnitAlias]] = [:]
        for preset in all where !preset.label.isEmpty && preset.amountPerUnit > 0 {
            cache[preset.substanceName, default: []].append(
                UnitAlias(label: preset.label, amountPerUnit: preset.amountPerUnit, unit: preset.unit),
            )
        }
        aliasCache = cache
    }
}
