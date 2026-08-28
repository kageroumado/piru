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
        overlayAll(SubstanceStore.shared.all)
    }

    /// Apply personal overrides across a browse list.
    ///
    /// The contract this establishes, and the point of it: **a `Substance` that
    /// came from `SubstanceLibrary` already carries the user's name for it.** No
    /// call site needs to re-resolve a personal name, and none can forget to —
    /// which is what left the Library list and Search showing "Mephedrone" while
    /// the detail screen showed "4-MMC".
    ///
    /// Free when the user has no customs, which is the overwhelming case: the
    /// early return skips the whole map rather than doing 1,736 dictionary hits
    /// to change nothing.
    static func overlayAll(_ substances: [Substance]) -> [Substance] {
        let customs = CustomSubstanceStore.shared
        guard !customs.all.isEmpty else { return substances }
        return substances.map { substance in
            customs.first(whereName: substance.name).map { substance.applyingOverride(from: $0) } ?? substance
        }
    }
    static var count: Int {
        SubstanceStore.shared.count
    }
    static var nonEmptyCategories: [SubstanceCategory] {
        SubstanceStore.shared.nonEmptyCategories
    }
    static func substances(in category: SubstanceCategory) -> [Substance] {
        overlayAll(SubstanceStore.shared.substances(in: category))
    }

    /// Browse-category histogram (count per browse category) — the cheap path
    /// for the Library cards' counts. See ``SubstanceStore/categorySummary()``.
    static func categorySummary() -> [SubstanceCategory: Int] {
        SubstanceStore.shared.categorySummary()
    }

    /// Browse-surfacing substance count per metadata tag — the tag cards'
    /// counterpart to ``categorySummary()``.
    static func tagSummary() -> [String: Int] {
        SubstanceStore.shared.tagSummary()
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
        overlayAll(SubstanceStore.shared.all.filter {
            $0.displayClass.surfacesInBrowse && $0.tags.contains(tag)
        })
    }

    /// The FULL per-field record — mechanism, bindings, chemistry identifiers,
    /// subjective effects — by canonical name **or any alias**, with the user's
    /// overrides applied. **Detail screens only**: uncached, this runs ~21 SQL
    /// on the main actor per substance, and ``SubstanceStore/ensureAllLoaded()``
    /// never warms its cache. Everything that reads name/category/routes/dose
    /// ladders/durations/half-life belongs on ``lookup(_:)`` — the name is heavy
    /// on purpose, so reaching for it is a deliberate act.
    ///
    /// Canonical-then-alias precedence, so a name that *is* canonical resolves
    /// exactly as before; the alias arm only runs when the canonical one misses.
    static func resolveFull(_ nameOrAlias: String) -> Substance? {
        overlayCustom(library: SubstanceStore.shared.lookupByNameOrAlias(nameOrAlias), query: nameOrAlias)
    }

    /// The default overlay-aware resolve. A dict hit over the lightweight batch
    /// cache (``SubstanceStore/timelineRow(_:)``) — name, category, routes,
    /// dose ranges (per-salt ladders included), durations, half-life — then any
    /// custom override. Falls back to the full heavy resolve when the batch
    /// cache hasn't matched (cold cache, or a custom-only substance with no
    /// library row), so it never silently drops an override or a custom. Await
    /// ``SubstanceStore/ensureAllLoaded()`` on the path first so the fallback
    /// never fires cold; reach for ``resolveFull(_:)`` only when a detail
    /// screen needs mechanism/bindings/chemistry.
    static func lookup(_ nameOrAlias: String) -> Substance? {
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

    /// The duration-of-effect envelope for a logged product name ("Concerta" →
    /// ~12 h), or `nil` for a name that isn't an authored extended-release
    /// formulation. Lets the timeline draw an ER brand's own curve rather than the
    /// parent's immediate-release one — see ``SubstanceStore/productDuration(forProduct:)``.
    static func productDuration(for name: String) -> DurationProfile? {
        SubstanceStore.shared.productDuration(forProduct: name)
    }

    /// ``formTitle(for:)`` with the facets a logged dose recorded, rather than the
    /// ones its name implies — see ``SubstanceStore/formTitle(forNameOrAlias:isomer:release:)``.
    static func formTitle(for nameOrAlias: String, isomer: String?, release: String?) -> String? {
        SubstanceStore.shared.formTitle(forNameOrAlias: nameOrAlias, isomer: isomer, release: release)
    }

    /// The branded products a substance ships under ("Concerta", "Ritalin LA"),
    /// keyed by PSID FAMILY `uid`, for the QuickLog brand picker. Raw library value.
    /// See ``SubstanceStore/brandProducts(forUID:)``.
    static func brandProducts(forUID uid: String) -> [SubstanceStore.BrandProduct] {
        SubstanceStore.shared.brandProducts(forUID: uid)
    }

    /// The substances sharing a PSID FAMILY `uid` (a fold family — a racemate and
    /// its enantiomers, or IR and XR), each overlaid with any custom edit. Empty
    /// when the uid is unknown.
    static func substances(uid: String) -> [Substance] {
        SubstanceStore.shared.substances(uid: uid).map {
            overlayCustom(library: $0, query: $0.name) ?? $0
        }
    }

    /// Whether the substance has at least one active metabolite whose elimination
    /// may outlast the parent — used by the body-load readout to qualify "fully
    /// eliminated" with a metabolite caveat.
    static func hasActiveMetabolite(_ canonicalName: String) -> Bool {
        SubstanceStore.shared.hasActiveMetabolite(canonicalName)
    }

    static func search(_ query: String, limit: Int = 50) -> [Substance] {
        overlaySearch(SubstanceStore.shared.searchMatches(query, limit: limit), query: query).map(\.substance)
    }

    /// The one place search results meet the personal overlay.
    ///
    /// Two things the raw store search cannot do, and every surface needs both:
    ///
    /// 1. **Carry the personal name.** A row for a relabelled substance was
    ///    titled with the catalog name, so the Library list and Search showed
    ///    "Mephedrone" while the detail screen showed "4-MMC".
    /// 2. **Match on the personal name.** The store's `nameIndex`/`aliasIndex`
    ///    are built from the database, which has never heard of a name the user
    ///    invented — so `lookup("joint")` found the THC override and
    ///    `search("joint")` found nothing.
    ///
    /// Applied here rather than at each call site because there are four search
    /// entry points and every one of them was missing it.
    static func overlaySearch(_ matches: [SubstanceMatch], query: String) -> [SubstanceMatch] {
        let customs = CustomSubstanceStore.shared
        var out = matches.map { match in
            guard let custom = customs.first(whereName: match.substance.name) else { return match }
            return SubstanceMatch(
                substance: match.substance.applyingOverride(from: custom),
                matchedAlias: match.matchedAlias,
            )
        }
        // A personal name the database cannot know. Only worth the scan when the
        // store found nothing under it — a hit means the catalog already answered.
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, !out.contains(where: { $0.substance.displayTitle.localizedCaseInsensitiveContains(trimmed) }),
           let byPersonalName = lookup(trimmed),
           !out.contains(where: { $0.substance.name == byPersonalName.name }) {
            out.insert(SubstanceMatch(substance: byPersonalName, matchedAlias: nil), at: 0)
        }
        return out
    }

    /// ``search(_:limit:)``, keeping the alias each hit matched so the caller can
    /// title a row with the name the user typed ("Concerta") rather than the one
    /// the catalog resolved to ("Methylphenidate").
    static func searchMatches(_ query: String, limit: Int = 50) -> [SubstanceMatch] {
        overlaySearch(SubstanceStore.shared.searchMatches(query, limit: limit), query: query)
    }

    /// Off-main ranked search for the interactive search field — ranks + resolves
    /// on a background task so typing never stalls the keyboard.
    static func searchAsync(_ query: String, limit: Int = 50) async -> [Substance] {
        await searchMatchesAsync(query, limit: limit).map(\.substance)
    }

    /// ``searchAsync(_:limit:)``, keeping the matched alias on each hit.
    static func searchMatchesAsync(_ query: String, limit: Int = 50) async -> [SubstanceMatch] {
        await overlaySearch(SubstanceStore.shared.searchMatchesAsync(query, limit: limit), query: query)
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
