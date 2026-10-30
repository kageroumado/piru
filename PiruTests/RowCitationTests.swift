import Foundation
import Testing
@testable import Piru

/// A pharmacology row's citation links where it says and is named for what it
/// links to. Two failures this pins: a URL citation (a DailyMed label, a
/// Wikipedia article) stored on a row but never shown, and an uncited research
/// row labeled "PubMed".
@Suite("Row citations")
@MainActor
struct RowCitationTests {
    @Test
    func `A row with no identifier has no citation`() {
        #expect(RowCitation(doi: nil, pmid: nil, url: nil) == nil)
        #expect(RowCitation(doi: "", pmid: nil, url: "") == nil)
    }

    @Test
    func `PMID links ahead of DOI, and DOI ahead of a URL`() {
        let all = RowCitation(doi: "10.1/x", pmid: 123, url: "https://example.org/x")
        #expect(all?.link?.absoluteString == "https://pubmed.ncbi.nlm.nih.gov/123/")
        let doi = RowCitation(doi: "10.1/x", pmid: nil, url: "https://example.org/x")
        #expect(doi?.link?.absoluteString == "https://doi.org/10.1/x")
        let url = RowCitation(doi: nil, pmid: nil, url: "https://en.wikipedia.org/wiki/Ketamine")
        #expect(url?.link?.absoluteString == "https://en.wikipedia.org/wiki/Ketamine")
    }

    @Test
    func `A free-text label is a citation with no link`() {
        let label = RowCitation(doi: nil, pmid: nil, url: "Ambien FDA label")
        #expect(label != nil)
        #expect(label?.link == nil)
        #expect(label?.linkName == nil)
    }

    @Test
    func `The name says what the link opens`() {
        #expect(RowCitation(doi: nil, pmid: 1, url: nil)?.linkName == "PubMed")
        #expect(RowCitation(doi: "10.1/x", pmid: nil, url: nil)?.linkName == "DOI")
        let label = "https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=abc"
        #expect(RowCitation(doi: nil, pmid: nil, url: label)?.linkName == "DailyMed")
        let article = "https://en.wikipedia.org/wiki/Ketamine"
        #expect(RowCitation(doi: nil, pmid: nil, url: article)?.linkName == "Wikipedia")
        let fda = "https://www.accessdata.fda.gov/drugsatfda_docs/label/x.pdf"
        #expect(RowCitation(doi: nil, pmid: nil, url: fda)?.linkName == "FDA")
        #expect(RowCitation(doi: nil, pmid: nil, url: "https://www.example.org/p")?.linkName == "example.org")
    }

    @Test
    func `An uncited research row names no source`() {
        #expect(rowSourceName(slug: AppSources.literatureSlug, citation: nil) == nil)
    }

    @Test
    func `A research row cited to a label is named for the label, never PubMed`() {
        let label = RowCitation(doi: nil, pmid: nil, url: "https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=abc")
        #expect(rowSourceName(slug: AppSources.literatureSlug, citation: label) == "DailyMed")
        let paper = RowCitation(doi: nil, pmid: 42, url: nil)
        #expect(rowSourceName(slug: AppSources.literatureSlug, citation: paper) == "PubMed")
    }

    @Test
    func `Any other source keeps its own name, cited or not`() {
        #expect(rowSourceName(slug: "tripsit", citation: nil) == "TripSit")
    }

    @Test
    func `A DailyMed citation on a metabolism row reaches the row`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        let hits = SubstanceStore.shared.metabolism(forSubstanceName: "Verapamil")
        let linked = hits.compactMap { $0.citation?.link?.host() }
        #expect(linked.contains("dailymed.nlm.nih.gov"), "the label URL must be read, not dropped")
    }
}
