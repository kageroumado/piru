import Foundation

struct SourceInfo {
    let name: String
    let url: String
    /// One line under the name: the site's address, or what the source is.
    let detail: LocalizedStringResource
    let description: LocalizedStringResource
    /// The license identifier shown beside a source whose text or data Piru
    /// bundles. `nil` when the source's own terms are linked through ``url``.
    var license: String?
}

enum AppSources {
    /// Display name of the European Union Drugs Agency entry, shared by ``all``
    /// and ``substanceURL(for:substance:)``.
    private static let euda = "EUDA (formerly EMCDDA)"

    static let all: [SourceInfo] = [
        SourceInfo(
            name: "TripSit",
            url: "https://tripsit.me",
            detail: "tripsit.me",
            description: "Community database. TripSit's combination data is a quick overview; research each combination further.",
            license: "Free for non-commercial use",
        ),
        SourceInfo(
            name: "OpenFDA",
            url: "https://open.fda.gov",
            detail: "open.fda.gov — National Drug Code directory",
            description: "U.S. government open data.",
            license: "CC0 1.0",
        ),
        SourceInfo(
            name: "PsychonautWiki",
            url: "https://psychonautwiki.org",
            detail: "psychonautwiki.org",
            description: "Community encyclopedia.",
            license: "CC BY-SA 4.0",
        ),
        SourceInfo(
            name: "FreeOD Wiki",
            url: "https://freeodwiki.org",
            detail: "freeodwiki.org",
            description: "Chinese-language community wiki.",
            license: "CC BY-SA 4.0",
        ),
        SourceInfo(
            name: "dose.wiki",
            url: "https://dose.wiki",
            detail: "dose.wiki",
            description: "Community encyclopedia.",
            license: "CC0 1.0",
        ),
        SourceInfo(
            name: "PubMed",
            url: "https://pubmed.ncbi.nlm.nih.gov",
            detail: "pubmed.ncbi.nlm.nih.gov",
            description: "Biomedical literature index.",
        ),
        SourceInfo(
            name: "PiHKAL",
            url: "https://isomerdesign.com/pihkal/browse/pk",
            detail: "Phenethylamines I Have Known and Loved — Shulgin & Shulgin (1991)",
            description: "Reference text by Alexander and Ann Shulgin.",
            license: "Book II · non-commercial reproduction",
        ),
        SourceInfo(
            name: "TiHKAL",
            url: "https://isomerdesign.com/pihkal/browse/tk",
            detail: "Tryptamines I Have Known and Loved — Shulgin & Shulgin (1997)",
            description: "Reference text by Alexander and Ann Shulgin.",
            license: "Book II · non-commercial reproduction",
        ),
        SourceInfo(
            name: "DailyMed",
            url: "https://dailymed.nlm.nih.gov",
            detail: "dailymed.nlm.nih.gov — NLM/FDA Drug Label Database",
            description: "U.S. product label database. Label text is written by each manufacturer.",
        ),
        SourceInfo(
            name: euda,
            url: "https://www.euda.europa.eu",
            detail: "European Union Drugs Agency",
            description: "European Union agency publications.",
        ),
        SourceInfo(
            name: "SubFxOnEx",
            url: "https://github.com/Di-lemma/SubFxOnEx",
            detail: "github.com/Di-lemma/SubFxOnEx — subjective-effects ontology",
            description: "Subjective-effects vocabulary.",
            license: "LGPL-2.1",
        ),
        SourceInfo(
            name: "substance.wiki",
            url: "https://substance.wiki",
            detail: "substance.wiki",
            description: "Community database.",
        ),
        SourceInfo(
            name: "PubChem",
            url: "https://pubchem.ncbi.nlm.nih.gov",
            detail: "pubchem.ncbi.nlm.nih.gov — National Library of Medicine",
            description: "Open chemistry database.",
        ),
        SourceInfo(
            name: "Wikidata",
            url: "https://www.wikidata.org",
            detail: "wikidata.org",
            description: "Open knowledge base.",
            license: "CC0 1.0",
        ),
        SourceInfo(
            name: "WHO",
            url: "https://www.who.int/groups/ecdd",
            detail: "WHO Expert Committee on Drug Dependence",
            description: "Expert committee reviews.",
        ),
    ]

    static func info(for name: String) -> SourceInfo? {
        all.first { $0.name == name }
    }

    /// Maps the bundled DB's wire `slug` (e.g. "tripsit", "psychonautwiki") to
    /// the display-name keys used by ``all`` / ``substanceURL(for:substance:)``.
    /// Only sources with a usable per-substance page are listed; others have no
    /// deep link.
    static let slugToName: [String: String] = [
        "tripsit": "TripSit",
        "psychonautwiki": "PsychonautWiki",
        "dailymed": "DailyMed",
        "peer-review-primary": "PubMed",
        "erowid-pihkal": "PiHKAL",
        "erowid-tihkal": "TiHKAL",
        "freeodwiki": "FreeOD Wiki",
        "dosewiki": "dose.wiki",
        "drug.community": "substance.wiki",
    ]

    /// Deep link to a FreeOD Wiki substance page. The pages are titled in
    /// Chinese, so the per-substance `freeodwiki_slug` captured at build time is
    /// required; without it there is no link.
    ///
    /// Returns `nil` rather than the site root deliberately. A row labelled with
    /// a substance that silently opens a homepage reads as a broken link, and it
    /// hides the real defect (a missing slug) behind something that looks like it
    /// worked. No link is the honest outcome.
    static func freeodwikiURL(slug: String?) -> URL? {
        guard let slug, !slug.isEmpty,
              let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        // MkDocs renders each page as `药物/<title>.html` (not a directory URL).
        return URL(string: "https://freeodwiki.org/药物/\(encoded).html")
    }

    /// Deep link to a dose.wiki substance page. Its slugs are lowercase-
    /// hyphenated forms of names Piru often spells differently, so the
    /// per-substance `dosewiki_slug` captured at build time is required.
    ///
    /// Returns `nil` rather than the site root, for the reason spelled out on
    /// ``freeodwikiURL(slug:)``.
    static func dosewikiURL(slug: String?) -> URL? {
        guard let slug, !slug.isEmpty,
              let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "https://dose.wiki/\(encoded)")
    }

    /// Deep link to a source's page for a substance, keyed by the DB `slug`
    /// rather than the display name. Used by the dose/duration source rows so
    /// "Dose data · TripSit" becomes a tappable link to that compound's page.
    static func substanceURL(forSlug slug: String, substance: String) -> URL? {
        guard let name = slugToName[slug] else { return nil }
        return substanceURL(for: name, substance: substance)
    }

    /// A search on Erowid's Experience Vaults for first-hand reports of a
    /// substance. We can't deep-link a specific vault page or show a report
    /// count — Erowid blocks automated access (403), so we can neither verify a
    /// page exists nor scrape counts — but a search always resolves for a person
    /// tapping it in their browser, with no dead-link or scraping concerns.
    static func erowidSearchURL(substance: String) -> URL? {
        let query = substance.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? substance
        return URL(string: "https://www.erowid.org/search.php?q=\(query)")
    }

    static func substanceURL(for source: String, substance: String) -> URL? {
        switch source {
        case "PsychonautWiki":
            let slug = substance.replacingOccurrences(of: " ", with: "_")
            return URL(string: "https://psychonautwiki.org/wiki/\(slug)")
        case "TripSit":
            let slug = substance.lowercased()
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? substance.lowercased()
            return URL(string: "https://drugs.tripsit.me/\(slug)")
        case "DailyMed":
            let query = substance
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? substance
            return URL(string: "https://dailymed.nlm.nih.gov/dailymed/search.cfm?labeltype=all&query=\(query)")
        case "PubMed":
            let query = substance
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? substance
            return URL(string: "https://pubmed.ncbi.nlm.nih.gov/?term=\(query)+pharmacology")
        case euda:
            let query = substance
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? substance
            return URL(string: "https://www.euda.europa.eu/publications/drug-profiles_en?search=\(query)")
        default:
            // No per-substance page for this source. Never fall back to the
            // source homepage: it renders as a substance-specific link that
            // isn't (the FreeOD Wiki case). Callers that do know how to build
            // one (see ``SubstanceSourceLinks.deepLink``) handle it before
            // reaching here.
            return nil
        }
    }
}
