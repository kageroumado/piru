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

    // MARK: - PSID (substance_uid) resolution

    /// The PSID FAMILY (`substance_uid`) for the substance named or aliased
    /// `nameOrAlias`, or `nil` when it doesn't resolve. The forward name→uid map
    /// the Stage 0.3 dose backfill uses. Name resolution still runs in parallel —
    /// this is additive; it changes no existing behavior.
    static func substanceUID(for nameOrAlias: String) -> String? {
        SubstanceStore.shared.substanceUID(forNameOrAlias: nameOrAlias)
    }

    /// The isomer form-code a logged name/alias names ("Focalin" → `"D"`), from
    /// the facet-annotated alias table, or `nil` for the racemic/unspecified form.
    /// Used by the PSID backfill to recover the form a legacy string logged.
    static func isomer(for nameOrAlias: String) -> String? {
        SubstanceStore.shared.isomer(forNameOrAlias: nameOrAlias)
    }

    /// The release form-code a logged name/alias names ("Concerta" → `"XR"`), or
    /// `nil` for the standard/unspecified form. Used by the PSID backfill to
    /// recover the form a legacy brand string logged.
    static func releaseForm(for nameOrAlias: String) -> String? {
        SubstanceStore.shared.releaseForm(forNameOrAlias: nameOrAlias)
    }

    /// The composed display title for the form a name/alias names ("Concerta" →
    /// "Methylphenidate XR"), or `nil` when it resolves to no enumerated form.
    /// Used by the PSID backfill to snapshot a resolved dose's title.
    static func formTitle(for nameOrAlias: String) -> String? {
        SubstanceStore.shared.formTitle(forNameOrAlias: nameOrAlias)
    }

    /// The tablet/capsule strengths a logged product name ships in ("Concerta" →
    /// 18/27/36/54 mg), or `nil` when the name isn't a known branded product.
    /// Lets the quick-log editor offer a *pill* picker instead of raw milligrams —
    /// display/entry only (see ``ProductStrengths``).
    static func productStrengths(for name: String) -> ProductStrengths? {
        SubstanceStore.shared.productStrengths(forProduct: name)
    }

    /// ``formTitle(for:)`` with the facets a logged dose recorded, rather than the
    /// ones its name implies — see ``SubstanceStore/formTitle(forNameOrAlias:isomer:release:)``.
    static func formTitle(for nameOrAlias: String, isomer: String?, release: String?) -> String? {
        SubstanceStore.shared.formTitle(forNameOrAlias: nameOrAlias, isomer: isomer, release: release)
    }

    /// The substances sharing a PSID FAMILY `uid` (a fold family — a racemate and
    /// its enantiomers, or IR and XR), each overlaid with any custom edit. Empty
    /// when the uid is unknown.
    static func substances(uid: String) -> [Substance] {
        SubstanceStore.shared.substances(uid: uid).map {
            overlayCustom(library: $0, query: $0.name) ?? $0
        }
    }

    static func search(_ query: String, limit: Int = 50) -> [Substance] {
        SubstanceStore.shared.search(query, limit: limit)
    }

    /// ``search(_:limit:)``, keeping the alias each hit matched so the caller can
    /// title a row with the name the user typed ("Concerta") rather than the one
    /// the catalog resolved to ("Methylphenidate").
    static func searchMatches(_ query: String, limit: Int = 50) -> [SubstanceMatch] {
        SubstanceStore.shared.searchMatches(query, limit: limit)
    }

    /// Off-main ranked search for the interactive search field — ranks + resolves
    /// on a background task so typing never stalls the keyboard.
    static func searchAsync(_ query: String, limit: Int = 50) async -> [Substance] {
        await SubstanceStore.shared.searchAsync(query, limit: limit)
    }

    /// ``searchAsync(_:limit:)``, keeping the matched alias on each hit.
    static func searchMatchesAsync(_ query: String, limit: Int = 50) async -> [SubstanceMatch] {
        await SubstanceStore.shared.searchMatchesAsync(query, limit: limit)
    }

    /// Resolve the user-defined entry that should overlay (or replace) the
    /// library result, then apply it. Looks up the custom by the library's
    /// canonical name first — the canonical match is what the user is most
    /// likely to recognize as "their" substance — and falls back to the raw
    /// query so a custom-only entry (no library row at all) still resolves.
    private static func overlayCustom(library: Substance?, query: String) -> Substance? {
        guard var result = resolveCustomOverride(library: library, query: query) else { return nil }
        // Fold the user's own units ("1 capsule = 30 mg") onto whichever record
        // resolved — every substance passes through here, so this is the one place
        // custom units reach the unit picker and the log-time unit→mass conversion.
        result.customUnitAliases = CustomUnitStore.shared.aliases(forSubstanceNamed: result.name)
        return result
    }

    private static func resolveCustomOverride(library: Substance?, query: String) -> Substance? {
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
