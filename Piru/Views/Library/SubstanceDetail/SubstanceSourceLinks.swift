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
    static func mergedLinks(for substance: Substance) -> [DetailSourceLink] {
        var seenURLs = Set<String>()
        var out: [DetailSourceLink] = []
        func add(label: String, url: URL?) {
            // The same work can arrive as both a database row and a citation
            // (e.g. TiHKAL — the source only knows the book's homepage, the
            // citation has this substance's chapter). Dedup by display label,
            // and let a *linked* candidate upgrade an already-added bare-text
            // one so the chapter URL wins over the missing homepage.
            let labelKey = label.lowercased()
            if let idx = out.firstIndex(where: { $0.label.lowercased() == labelKey }) {
                if out[idx].url == nil, let url {
                    seenURLs.insert(url.absoluteString)
                    out[idx] = DetailSourceLink(label: out[idx].label, url: url)
                }
                return
            }
            if let url {
                if seenURLs.contains(url.absoluteString) { return }
                seenURLs.insert(url.absoluteString)
            }
            out.append(DetailSourceLink(label: label, url: url))
        }
        // `substance.sources` holds wire slugs ("peer-review-primary",
        // "tripsit") — map each to a human source name and its per-substance page.
        for slug in substance.sources {
            add(label: label(forSlug: slug), url: deepLink(slug, substance: substance))
        }
        for ref in substance.references {
            add(label: friendlyReferenceLabel(ref), url: ref.resolvedURL)
        }
        return out
    }
}
