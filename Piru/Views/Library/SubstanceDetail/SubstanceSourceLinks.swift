import Foundation

/// Source-attribution link resolution, shared by every section of the substance
/// detail screen that shows a "where this came from" affordance (Overview,
/// Dose & Duration, Info, and the merged Sources list). Pure functions of the
/// substance, factored out of the view so each section resolves links without
/// carrying the logic or forcing the parent to pass closures down.
enum SubstanceSourceLinks {
    /// Deep link for a source-attribution row. drug.community's `/drug/<slug>`
    /// page resolves only the canonical slug captured at build time (no alias
    /// fallback), so it can't be derived from the app's name; every other source
    /// deep-links from the substance name via ``AppSources``.
    static func deepLink(_ slug: String, substance: Substance) -> URL? {
        if slug == "drug.community" {
            guard let dc = substance.drugCommunitySlug else { return nil }
            return URL(string: "https://drug.community/drug/\(dc)")
        }
        // FreeOD Wiki pages are titled in Chinese, so deep-link the captured
        // page slug rather than the app's (English) substance name.
        if slug == "freeodwiki" {
            return AppSources.freeodwikiURL(slug: substance.freeodwikiSlug)
        }
        // The Shulgin books (PiHKAL/TiHKAL) only have a book homepage, not a
        // per-substance page. The citation carries the real chapter link, so
        // don't offer the misleading homepage — `mergedLinks` upgrades the
        // bare "TiHKAL" row to the citation's chapter URL.
        if slug == "erowid-pihkal" || slug == "erowid-tihkal" { return nil }
        // The hand-curated overlay has no per-substance page of its own. When we
        // curated a real reference for the compound (NIH ODS / examine.com for a
        // supplement, a paper for an RC), link the attribution to that source
        // instead of dead-ending on the bare "Piru hand-curated overlay" label.
        if slug == "piru-curated" {
            return substance.references.first(where: { $0.resolvedURL != nil })?.resolvedURL
        }
        return AppSources.substanceURL(forSlug: slug, substance: substance.name)
    }

    /// Human-readable name for a source slug — preferring the clean website
    /// names in ``AppSources`` (PubMed, TripSit…), falling back to the bundled
    /// `sources` table's display name (drug.community, Wikidata…).
    static func label(forSlug slug: String) -> String {
        if let name = AppSources.slugToName[slug] { return name }
        return SubstanceStore.shared.sourceDisplayName(forSlug: slug)
    }

    /// The content license a source's material is bundled under, when it carries
    /// one. Only the copyleft community wikis do (CC BY-SA 4.0), and naming the
    /// license is part of what that license asks for — ``SourceInfo/license`` has
    /// been populated since the sources were added but was never displayed
    /// anywhere, so the Sources list is where that obligation is discharged.
    static func license(forSlug slug: String) -> String? {
        guard let name = AppSources.slugToName[slug] else { return nil }
        return AppSources.info(for: name)?.license
    }

    /// The facets a source supplies, as a static fallback for the identifier-only
    /// sources — the one place a "provides" claim is *not* read from the DB.
    ///
    /// PubChem, NPS Data Hub and Wikidata write into `substances`' identifier
    /// columns (formula / CAS / InChIKey / SMILES / CID), and those columns carry
    /// no `source_id`, so no query can attribute them per field. What makes the
    /// claim safe rather than a guess is that these three ingest *nothing else*:
    /// each is documented in the bundled `sources` table as identifier-only, so
    /// "chemistry" is the complete answer for them by construction. Still gated
    /// on the compound actually having an identifier to show.
    private static let identifierOnlySlugs: Set<String> = ["pubchem", "nps-datahub", "wikidata"]

    private static func staticFacets(forSlug slug: String, substance: Substance) -> [SubstanceStore.SourceFacet] {
        guard identifierOnlySlugs.contains(slug) else { return [] }
        let hasIdentifier = substance.formula != nil || substance.cas != nil || substance.inchikey != nil
            || substance.smiles != nil || substance.pubchemCID != nil
        return hasIdentifier ? [.chemistry] : []
    }

    /// A tidy display name for a citation that lacks a title — the bare URL
    /// (the old `Citation.label` fallback) reads as clutter, so name the work
    /// (TiHKAL / PiHKAL) when recognisable, else show the host.
    static func friendlyReferenceLabel(_ ref: Citation) -> String {
        if let title = ref.title, !title.isEmpty { return title }
        if let doi = ref.doi, !doi.isEmpty { return "DOI \(doi)" }
        if let pmid = ref.pmid { return "PMID \(pmid)" }
        if let urlString = ref.url?.lowercased() {
            if urlString.contains("tihkal") { return "TiHKAL" }
            if urlString.contains("pihkal") { return "PiHKAL" }
        }
        if let host = ref.resolvedURL?.host() {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return ref.label
    }

    /// The merged, de-duplicated provenance list: the databases that contributed
    /// this compound's data followed by any primary literature, each deep-linked
    /// to the substance's own page where one exists. Used to be two near-identical
    /// "Databases" / "References" subsections; collapsed into one tappable list.
    ///
    /// Pass the substance's ``SubstanceStore/SourceContributions`` to get the
    /// two-column ledger (each row paired with what that source actually
    /// supplied). Without it — the presence check in ``SubstanceDetailLayout``,
    /// which runs on every `body` and must stay free of DB reads — the same rows
    /// come back with an empty `provides`.
    static func mergedLinks(
        for substance: Substance,
        contributions: SubstanceStore.SourceContributions = .empty,
    ) -> [DetailSourceLink] {
        var seenURLs = Set<String>()
        var out: [DetailSourceLink] = []
        func add(label: String, url: URL?, provides: [SubstanceStore.SourceFacet] = [], license: String? = nil) {
            // The same work can arrive as both a database row and a citation
            // (e.g. TiHKAL — the source only knows the book's homepage, the
            // citation has this substance's chapter). Dedup by display label,
            // and let a *linked* candidate upgrade an already-added bare-text
            // one so the chapter URL wins over the missing homepage. A merged
            // row keeps the union of both sides' facets — under-crediting a
            // source is the one failure mode this list must not have.
            let labelKey = label.lowercased()
            if let idx = out.firstIndex(where: { $0.label.lowercased() == labelKey }) {
                var merged = out[idx]
                if merged.url == nil, let url {
                    seenURLs.insert(url.absoluteString)
                    merged.url = url
                }
                merged.provides = union(merged.provides, provides)
                merged.license = merged.license ?? license
                out[idx] = merged
                return
            }
            if let url {
                if seenURLs.contains(url.absoluteString) { return }
                seenURLs.insert(url.absoluteString)
            }
            out.append(DetailSourceLink(label: label, url: url, provides: provides, license: license))
        }
        // Wire slugs ("peer-review-primary", "tripsit") mapped to a human source
        // name and its per-substance page. `substance.sources` is the narrower
        // set — it only counts six tables — so a source that supplied *only* the
        // effects list or the overview is absent from it. The ledger knows about
        // those, and an uncredited copyleft wiki is a licensing defect, so the
        // two sets are unioned rather than intersected.
        for slug in orderedSlugs(for: substance, contributions: contributions) {
            add(
                label: label(forSlug: slug),
                url: deepLink(slug, substance: substance),
                provides: union(
                    contributions.bySourceSlug[slug] ?? [],
                    staticFacets(forSlug: slug, substance: substance),
                ),
                license: license(forSlug: slug),
            )
        }
        for ref in substance.references {
            add(
                label: friendlyReferenceLabel(ref),
                url: ref.resolvedURL,
                provides: contributions.facets(for: ref),
            )
        }
        return out
    }

    /// Contributing slugs in the user's own source-priority order, so the row the
    /// app most often resolves *from* leads the list. Slugs the priority order
    /// doesn't know about (a newer bundled DB than the stored order) sort last,
    /// alphabetically, instead of vanishing.
    private static func orderedSlugs(
        for substance: Substance,
        contributions: SubstanceStore.SourceContributions,
    ) -> [String] {
        let slugs = Set(substance.sources).union(contributions.bySourceSlug.keys)
        let priority = SubstanceStore.shared.enabledSourceOrder
        let rank = Dictionary(uniqueKeysWithValues: priority.enumerated().map { ($0.element, $0.offset) })
        return slugs.sorted { lhs, rhs in
            let lhsRank = rank[lhs] ?? priority.count
            let rhsRank = rank[rhs] ?? priority.count
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs < rhs
        }
    }

    /// Facet union that preserves ``SubstanceStore/SourceFacet/displayOrder``.
    private static func union(
        _ lhs: [SubstanceStore.SourceFacet],
        _ rhs: [SubstanceStore.SourceFacet],
    ) -> [SubstanceStore.SourceFacet] {
        if rhs.isEmpty { return lhs }
        if lhs.isEmpty { return rhs }
        let combined = Set(lhs).union(rhs)
        return SubstanceStore.SourceFacet.displayOrder.filter(combined.contains)
    }
}
