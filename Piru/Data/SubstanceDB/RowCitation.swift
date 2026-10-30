import Foundation

/// The citation behind one pharmacology row, as the row's `citation_id` resolves
/// in the bundled `citations` table: a PubMed id, a DOI, or a URL (an encyclopedia
/// article, a product label).
///
/// One type so every per-row surface links and names a citation the same way.
/// The name is what the link opens — "PubMed" only for a PubMed link — because the
/// row's source slug says how the row was written, which is a different question
/// from where its evidence is.
nonisolated struct RowCitation: Hashable, Sendable {
    let doi: String?
    let pmid: Int?
    let url: String?

    /// `nil` when the row carries no citation at all.
    init?(doi: String?, pmid: Int?, url: String?) {
        let doi = doi.flatMap { $0.isEmpty ? nil : $0 }
        let url = url.flatMap { $0.isEmpty ? nil : $0 }
        guard doi != nil || pmid != nil || url != nil else { return nil }
        self.doi = doi
        self.pmid = pmid
        self.url = url
    }

    /// PMID first, then DOI, then an http(s) URL. A free-text label stored in
    /// `url` ("Ambien FDA label") has no link.
    var link: URL? {
        if let pmid { return URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/") }
        if let doi { return URL(string: "https://doi.org/\(doi)") }
        if let url, url.lowercased().hasPrefix("http") { return URL(string: url) }
        return nil
    }

    /// The name of what ``link`` opens: "PubMed", "DOI", or the site ("Wikipedia",
    /// "DailyMed", "FDA", else the bare host). `nil` when there is no link.
    var linkName: String? {
        if pmid != nil { return "PubMed" }
        if doi != nil { return "DOI" }
        guard let host = link?.host()?.lowercased() else { return nil }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        for (suffix, name) in Self.siteNames where bare == suffix || bare.hasSuffix(".\(suffix)") {
            return name
        }
        return bare
    }

    /// Hosts whose own name reads better than their domain. Proper nouns, so
    /// they are not localized.
    private static let siteNames: [(suffix: String, name: String)] = [
        ("wikipedia.org", "Wikipedia"),
        ("dailymed.nlm.nih.gov", "DailyMed"),
        ("fda.gov", "FDA"),
        ("erowid.org", "Erowid"),
        ("ods.od.nih.gov", "NIH ODS"),
        ("examine.com", "Examine"),
    ]
}

/// A read-model row that carries a citation's three identifier columns.
nonisolated protocol RowCited {
    var doi: String? { get }
    var pmid: Int? { get }
    var url: String? { get }
}

extension RowCited {
    var citation: RowCitation? {
        RowCitation(doi: doi, pmid: pmid, url: url)
    }
}

extension PharmacogeneticHit: RowCited {}
extension SignallingCascade: RowCited {}
extension ClassContext.Reference: RowCited {}
extension ConcentrationThreshold: RowCited {}
extension TargetEvidence: RowCited {}
extension ActiveMetabolite: RowCited {}
extension PKInteractionHit: RowCited {}
extension SubstanceStore.MetabolismHit: RowCited {}
extension OffTargetHit: RowCited {}
extension PKRouteHit: RowCited {}
extension TherapeuticRangeHit: RowCited {}
extension BindingHit: RowCited {}
extension SignatureLeg: RowCited {}
