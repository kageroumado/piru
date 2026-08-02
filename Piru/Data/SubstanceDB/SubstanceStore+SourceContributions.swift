import Foundation
import GRDB
import os

private nonisolated let logger = Logger(subsystem: "dev.yumeji.piru", category: "SubstanceStore")

/// "What did this source actually give me for *this* compound?" — the inverse of
/// ``SubstanceStore/provenance(forSubstanceName:)``.
///
/// Provenance answers *which source won a field* after priority resolution; this
/// answers *which fields a source carries at all*, winner or not. An attribution
/// ledger has to say the second thing: a source that supplied the effects list
/// and lost the dose ladder still contributed to the page, and a Sources screen
/// that only credited winners would under-credit it.
///
/// Every fact here is read from the bundled DB's per-row `source_id` /
/// `citation_id` columns. There is deliberately **no** hand-maintained
/// "PsychonautWiki provides dose and duration" table: the answer differs per
/// substance (PsychonautWiki has a mechanism for one compound and only aliases
/// for the next), so a static map would be wrong far more often than it was
/// right — and wrong attribution on copyleft content is a licensing problem, not
/// a cosmetic one.
extension SubstanceStore {
    /// One kind of content a source can supply for a substance.
    ///
    /// Deliberately coarse. It labels a caption in a two-column list, not a
    /// schema dump, so ~24 per-substance tables collapse into eleven words the
    /// reader already recognises from the screen they just scrolled through.
    enum SourceFacet: String, Hashable, Identifiable {
        case dose
        case duration
        case effects
        case overview
        case pharmacology
        case pharmacokinetics
        case tolerance
        case prescribing
        case interactions
        case chemistry
        case identity

        var id: String { rawValue }

        /// Most substantive first — the order facets are listed in, so a row
        /// reads "dose · duration · effects" rather than alphabetical noise.
        static let displayOrder: [SourceFacet] = [
            .dose, .duration, .effects, .overview, .pharmacology, .pharmacokinetics,
            .tolerance, .prescribing, .interactions, .chemistry, .identity,
        ]

        /// Lowercase on purpose: these are fragments of a phrase ("dose ·
        /// duration · overview"), not titles.
        var label: LocalizedStringResource {
            switch self {
            case .dose: LocalizedStringResource("dose", comment: "Sources list — what a source supplies")
            case .duration: LocalizedStringResource("duration", comment: "Sources list — what a source supplies")
            case .effects: LocalizedStringResource("effects", comment: "Sources list — what a source supplies")
            case .overview: LocalizedStringResource("overview", comment: "Sources list — what a source supplies")
            case .pharmacology: LocalizedStringResource("pharmacology", comment: "Sources list — what a source supplies")
            case .pharmacokinetics: LocalizedStringResource("pharmacokinetics", comment: "Sources list — what a source supplies")
            case .tolerance: LocalizedStringResource("tolerance", comment: "Sources list — what a source supplies")
            case .prescribing: LocalizedStringResource("prescribing", comment: "Sources list — what a source supplies")
            case .interactions: LocalizedStringResource("interactions", comment: "Sources list — what a source supplies")
            case .chemistry: LocalizedStringResource("chemistry", comment: "Sources list — what a source supplies")
            case .identity: LocalizedStringResource("names & tags", comment: "Sources list — what a source supplies")
            }
        }
    }

    /// The per-substance contribution ledger: which source, and which cited work,
    /// supplied which parts of the page.
    struct SourceContributions: Hashable {
        /// Source slug (`tripsit`, `freeodwiki`) → facets, ``SourceFacet/displayOrder`` order.
        let bySourceSlug: [String: [SourceFacet]]
        /// Citation key (see ``citationKey(doi:pmid:url:)``) → facets, same order.
        let byCitationKey: [String: [SourceFacet]]

        static let empty = SourceContributions(bySourceSlug: [:], byCitationKey: [:])

        /// A stable key for a cited work. Mirrors ``Citation/resolvedURL``'s
        /// precedence (DOI, then PMID, then URL) so a `Citation` decoded by the
        /// resolver and a row read here agree on identity without carrying the
        /// citations table's primary key into the domain model.
        static func citationKey(doi: String?, pmid: Int?, url: String?) -> String? {
            if let doi, !doi.isEmpty { return "doi:\(doi.lowercased())" }
            if let pmid { return "pmid:\(pmid)" }
            if let url, !url.isEmpty { return "url:\(url.lowercased())" }
            return nil
        }

        /// Facets this cited work supports, or empty when it is attached to the
        /// substance generally rather than to a specific fact.
        func facets(for citation: Citation) -> [SourceFacet] {
            guard let key = Self.citationKey(doi: citation.doi, pmid: citation.pmid, url: citation.url) else {
                return []
            }
            return byCitationKey[key] ?? []
        }
    }

    /// Which per-substance table proves which facet. Table names are compile-time
    /// constants interpolated into SQL — never user input.
    ///
    /// Not exhaustive by design: the rare pharma-nerd tables (`biased_agonism`,
    /// `downstream_signalling`, `receptor_oligomers`, `neuroimaging`) would each
    /// add a UNION leg to say "pharmacology" that a `bindings` row has already
    /// said for the same source.
    private static let facetTables: [(table: String, facet: SourceFacet)] = [
        ("dose_ranges", .dose),
        ("protocol_dosing", .dose),
        ("durations", .duration),
        ("durations_of_action", .duration),
        ("effects", .effects),
        ("reported_effects", .effects),
        ("subjective_effects", .effects),
        ("spectrum_levels", .effects),
        ("descriptions", .overview),
        ("mechanisms_summary", .pharmacology),
        ("bindings", .pharmacology),
        ("off_targets", .pharmacology),
        ("functional_assays", .pharmacology),
        ("half_lives", .pharmacokinetics),
        ("pk_routes", .pharmacokinetics),
        ("metabolism", .pharmacokinetics),
        ("pharmacogenetics", .pharmacokinetics),
        ("tolerance", .tolerance),
        ("indications", .prescribing),
        ("contraindications", .prescribing),
        ("drug_interactions_pk", .interactions),
        ("aliases", .identity),
        ("tags", .identity),
        ("categories", .identity),
    ]

    /// The tables whose `citation_id` can reach ``Substance/references`` — the
    /// same union ``resolvedReferences(db:substanceID:)`` builds that list from,
    /// so every literature row on the Sources screen can be asked what it backs.
    /// (`substance_citations` is excluded: it attaches a work to the compound in
    /// general, which is precisely "no specific facet".)
    private static let citationFacetTables: [(table: String, facet: SourceFacet)] = [
        ("dose_ranges", .dose),
        ("protocol_dosing", .dose),
        ("durations", .duration),
        ("half_lives", .pharmacokinetics),
        ("mechanisms_summary", .pharmacology),
    ]

    /// Builds the contribution ledger for one substance. A cheap local read (a
    /// few dozen indexed lookups over tables of a few thousand rows); call it
    /// from a `.task`, not from a view `body`.
    func sourceContributions(forSubstanceName name: String) -> SourceContributions {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return .empty }
        let enabledList = enabledSourceListSQL
        let sourceLegs = Self.facetTables
            .map { "SELECT source_id AS sid, '\($0.facet.rawValue)' AS facet FROM \($0.table) WHERE substance_id = :id" }
            .joined(separator: " UNION ALL ")
        let citationLegs = Self.citationFacetTables
            .map {
                """
                SELECT citation_id AS cid, '\($0.facet.rawValue)' AS facet FROM \($0.table) \
                WHERE substance_id = :id AND citation_id IS NOT NULL
                """
            }
            .joined(separator: " UNION ALL ")

        do {
            return try substancesDB.read { db in
                var bySlug: [String: Set<SourceFacet>] = [:]
                let sourceRows = try Row.fetchAll(db, sql: """
                    SELECT DISTINCT src.slug AS slug, u.facet AS facet
                      FROM (\(sourceLegs)) AS u
                      JOIN sources src ON src.id = u.sid
                     WHERE src.slug IN (\(enabledList))
                """, arguments: ["id": substanceID])
                for row in sourceRows {
                    let slug: String = row["slug"]
                    let raw: String = row["facet"]
                    guard let facet = SourceFacet(rawValue: raw) else { continue }
                    bySlug[slug, default: []].insert(facet)
                }

                var byCitation: [String: Set<SourceFacet>] = [:]
                let citationRows = try Row.fetchAll(db, sql: """
                    SELECT DISTINCT c.doi AS doi, c.pmid AS pmid, c.url AS url, u.facet AS facet
                      FROM (\(citationLegs)) AS u
                      JOIN citations c ON c.id = u.cid
                """, arguments: ["id": substanceID])
                for row in citationRows {
                    let raw: String = row["facet"]
                    guard let facet = SourceFacet(rawValue: raw),
                          let key = SourceContributions.citationKey(
                              doi: row["doi"],
                              pmid: (row["pmid"] as Int64?).map(Int.init),
                              url: row["url"],
                          )
                    else { continue }
                    byCitation[key, default: []].insert(facet)
                }

                return SourceContributions(
                    bySourceSlug: bySlug.mapValues(Self.inDisplayOrder),
                    byCitationKey: byCitation.mapValues(Self.inDisplayOrder),
                )
            }
        } catch {
            logger.error("sourceContributions(forSubstanceName:) failed: \(error.localizedDescription, privacy: .public)")
            return .empty
        }
    }

    private static func inDisplayOrder(_ facets: Set<SourceFacet>) -> [SourceFacet] {
        SourceFacet.displayOrder.filter(facets.contains)
    }
}
