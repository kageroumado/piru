import Testing
@testable import Piru

/// The detail-view tier matrix is data-only after the extraction from
/// SubstanceDetailView, so it can be tested directly without spinning up a
/// SwiftUI view. Catches accidental reshuffling of who sees what.
@Suite("DisclosurePolicy")
struct DisclosurePolicyTests {
    @Test
    func `Casual tier hides every advanced section`() {
        let p = DisclosurePolicy(profile: .casual)
        #expect(!p.showsMechanism)
        #expect(!p.showsRichSubjective)
        #expect(!p.showsReceptorLiterature)
        // Sources stay visible to every tier — even casual users may want
        // attribution. Defaults collapsed though.
        #expect(p.showsSources)
        #expect(!p.sourcesDefaultExpanded)
    }

    @Test
    func `Harm-reduction shows mechanism + subjective, hides literature`() {
        let p = DisclosurePolicy(profile: .harmReduction)
        #expect(p.showsMechanism)
        #expect(p.showsRichSubjective)
        #expect(!p.showsReceptorLiterature) // Literature is pharma-nerd only
        #expect(p.showsSources)
        // Middle tier: sections visible but not default-expanded.
        #expect(!p.mechanismDefaultExpanded)
        #expect(!p.subjectiveDefaultExpanded)
        #expect(p.sourcesDefaultExpanded)
    }

    @Test
    func `Pharma-nerd shows everything default-expanded`() {
        let p = DisclosurePolicy(profile: .pharmaNerd)
        #expect(p.showsMechanism)
        #expect(p.showsRichSubjective)
        #expect(p.showsReceptorLiterature)
        #expect(p.showsSources)
        #expect(p.mechanismDefaultExpanded)
        #expect(p.subjectiveDefaultExpanded)
        #expect(p.sourcesDefaultExpanded)
        #expect(p.receptorLitDefaultExpanded)
    }

    @Test
    func `Receptor literature is exclusively a pharma-nerd surface`() {
        for profile in UserProfile.allCases {
            let p = DisclosurePolicy(profile: profile)
            #expect(p.showsReceptorLiterature == (profile == .pharmaNerd))
        }
    }
}
