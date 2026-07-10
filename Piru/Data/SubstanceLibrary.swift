import Foundation

// MARK: - Static façade

/// Static façade matching the legacy `SubstanceLibrary` API. Lets every call
/// site keep working with a stable shape while the store underneath is
/// GRDB-backed. Inlined into call sites would be the long-term cleanup, but
/// the façade is zero-cost so a one-line `enum` is the right level of
/// abstraction for the migration to land cleanly.
///
/// ## User-defined overlay
///
/// Single-substance lookups (`lookup`, `lookupByNameOrAlias`) consult
/// ``CustomSubstanceStore`` and overlay any user-defined entry on top of the
/// library result. This is what makes the timeline / PK pipeline pick up
/// user-corrected duration profiles for substances where the bundled DB has
/// nothing useful (e.g. 2-MMC, where neither piru-curated nor TripSit ships
/// duration data). The collection-level APIs (`all`, `substances(in:)`,
/// `search`) deliberately stay library-only — the Library tab keeps its
/// existing "Custom substances" section instead of folding them into the
/// main listing, which would surprise users who expect that section to be
/// authoritative.
@MainActor
enum SubstanceLibrary {
    static var all: [Substance] {
        SubstanceStore.shared.all
    }
    static var count: Int {
        SubstanceStore.shared.count
    }
    static var nonEmptyCategories: [SubstanceCategory] {
        SubstanceStore.shared.nonEmptyCategories
    }
    static func substances(in category: SubstanceCategory) -> [Substance] {
        SubstanceStore.shared.substances(in: category)
    }

    /// Browse-category histogram (count per browse category) — the cheap path
    /// for the Library cards' counts. See ``SubstanceStore/categorySummary()``.
    static func categorySummary() -> [SubstanceCategory: Int] {
        SubstanceStore.shared.categorySummary()
    }

    /// Exact-canonical lightweight detail shell from the warm batch cache, or
    /// `nil` (cache cold, or not a canonical substance). See
    /// ``SubstanceStore/shellRow(_:)``. Overlay-aware so a personalized display
    /// name shows on the shell too.
    static func shell(_ name: String) -> Substance? {
        guard let row = SubstanceStore.shared.shellRow(name) else { return nil }
        return overlayCustom(library: row, query: name)
    }

    /// Browsable substances flagged with a metadata `tag` (e.g. `"common"`,
    /// `"research-chemical"`). Unlike ``substances(in:)`` this cuts *across*
    /// categories — the Library's Common card surfaces alcohol, caffeine, and
    /// cannabis side by side regardless of their resolved class.
    static func substances(taggedWith tag: String) -> [Substance] {
        SubstanceStore.shared.all.filter {
            $0.displayClass.surfacesInBrowse && $0.tags.contains(tag)
        }
    }

    static func lookup(_ name: String) -> Substance? {
        overlayCustom(library: SubstanceStore.shared.lookup(name), query: name)
    }

    static func lookupByNameOrAlias(_ nameOrAlias: String) -> Substance? {
        overlayCustom(library: SubstanceStore.shared.lookupByNameOrAlias(nameOrAlias), query: nameOrAlias)
    }

    /// Overlay-aware lookup for the **journal / timeline** path. Resolves the
    /// library row from the lightweight batch cache (``SubstanceStore/timelineRow(_:)``)
    /// — category, routes, dose-ranges, durations, half-life — which is all the
    /// timeline derive needs, then applies any custom override. Falls back to the
    /// full heavy lookup when the batch cache hasn't matched (cold cache, or a
    /// custom-only substance with no library row), so it never silently drops an
    /// override or a custom. Use this from per-entry resolution where the heavy
    /// chem/mechanism fields are irrelevant; use ``lookupByNameOrAlias(_:)`` when
    /// the full detail record is required.
    static func timelineLookup(_ nameOrAlias: String) -> Substance? {
        if let row = SubstanceStore.shared.timelineRow(nameOrAlias) {
            return overlayCustom(library: row, query: nameOrAlias)
        }
        return overlayCustom(library: SubstanceStore.shared.lookupByNameOrAlias(nameOrAlias), query: nameOrAlias)
    }

    static func search(_ query: String, limit: Int = 50) -> [Substance] {
        SubstanceStore.shared.search(query, limit: limit)
    }

    /// Off-main ranked search for the interactive search field — ranks + resolves
    /// on a background task so typing never stalls the keyboard.
    static func searchAsync(_ query: String, limit: Int = 50) async -> [Substance] {
        await SubstanceStore.shared.searchAsync(query, limit: limit)
    }

    /// Resolve the user-defined entry that should overlay (or replace) the
    /// library result, then apply it. Looks up the custom by the library's
    /// canonical name first — the canonical match is what the user is most
    /// likely to recognize as "their" substance — and falls back to the raw
    /// query so a custom-only entry (no library row at all) still resolves.
    private static func overlayCustom(library: Substance?, query: String) -> Substance? {
        let customs = CustomSubstanceStore.shared

        if let library {
            let custom = customs.first(whereName: library.name)
            return custom.map { library.applyingOverride(from: $0) } ?? library
        }

        // No library row matched the query. Try a custom by its canonical name,
        // then by its personal display name — so a relabelled substance is
        // resolvable by the name the user gave it ("joint" → the THC override).
        guard let custom = customs.first(whereName: query) ?? customs.first(whereDisplayName: query) else {
            return nil
        }
        // A personal override of a library substance still has that substance's
        // canonical name; re-resolve and overlay so dose/duration come through.
        if let underlying = SubstanceStore.shared.lookupByNameOrAlias(custom.name) {
            return underlying.applyingOverride(from: custom)
        }
        return custom.asSubstance
    }
}
