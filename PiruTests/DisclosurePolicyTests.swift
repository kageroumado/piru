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

    // MARK: - Placement matrix (redesigned view)

    @Test
    func `Spine is chosen by display class, mirroring the dose-ladder split`() {
        let p = DisclosurePolicy(profile: .harmReduction)
        for dc in [CompoundDisplayClass.recreational, .dualUse, .otc] {
            #expect(p.spine(for: dc) == .recreational)
        }
        for dc in [CompoundDisplayClass.medicalRx, .nonRecreational] {
            #expect(p.spine(for: dc) == .medical)
        }
    }

    @Test
    func `Recreational body is inline at every tier`() {
        let body: [DetailSection] = [.history, .doseDuration, .effects, .combinations, .water, .misconceptions]
        for profile in UserProfile.allCases {
            let p = DisclosurePolicy(profile: profile)
            for section in body {
                #expect(p.placement(for: section, spine: .recreational) == .inline)
            }
        }
    }

    @Test
    func `Casual hides pharmacology and keeps chemistry and sources folded on the page`() {
        let p = DisclosurePolicy(profile: .casual)
        #expect(p.placement(for: .mechanism, spine: .recreational) == .hidden)
        #expect(p.placement(for: .receptorLiterature, spine: .recreational) == .hidden)
        #expect(p.placement(for: .pharmacokinetics, spine: .recreational) == .hidden)
        // The only depth a Casual user can reach — and it is a fold, not a push.
        #expect(p.placement(for: .chemistry, spine: .recreational) == .inlineCollapsed)
        #expect(p.placement(for: .sources, spine: .recreational) == .inlineCollapsed)
    }

    @Test
    func `Curious gets pharmacology on the page, folded`() {
        let p = DisclosurePolicy(profile: .harmReduction)
        #expect(p.placement(for: .mechanism, spine: .recreational) == .inlineCollapsed)
        #expect(p.placement(for: .pharmacokinetics, spine: .recreational) == .inlineCollapsed)
        #expect(p.placement(for: .chemistry, spine: .recreational) == .inlineCollapsed)
        // Matches `showsReceptorLiterature`, which PharmacologySections still gates
        // on: the Kᵢ table is Pharma Nerd only, and the matrix must not promise
        // what the boolean withholds.
        #expect(p.placement(for: .receptorLiterature, spine: .recreational) == .hidden)
    }

    @Test
    func `No section is ever a deep-page push`() {
        // `.showAll` is gone from the matrix: the cards already fold, so wrapping a
        // fold in a navigation push cost two taps and a screen transition to reach
        // a disclosure triangle — and split one substance's pharmacology across two
        // backgrounds. This test is what stops it coming back.
        for profile in [UserProfile.casual, .harmReduction, .pharmaNerd] {
            let p = DisclosurePolicy(profile: profile)
            for section in DetailSection.allCases {
                for spine in [DetailSpine.recreational, .medical] {
                    #expect(
                        p.placement(for: section, spine: spine) != .showAll,
                        "\(section) at \(profile) on the \(spine) spine still pushes a deep page",
                    )
                }
            }
        }
    }

    @Test
    func `Pharma Nerd inlines depth but keeps dense tables as collapsed groups`() {
        let p = DisclosurePolicy(profile: .pharmaNerd)
        #expect(p.placement(for: .mechanism, spine: .recreational) == .inline)
        #expect(p.placement(for: .pharmacokinetics, spine: .recreational) == .inline)
        // Dense reference data is inline-but-collapsed, never a flat wall.
        #expect(p.placement(for: .receptorLiterature, spine: .recreational) == .inlineCollapsed)
        #expect(p.placement(for: .chemistry, spine: .recreational) == .inlineCollapsed)
        #expect(p.placement(for: .sources, spine: .recreational) == .inlineCollapsed)
    }

    @Test
    func `Medical spine hides every recreational surface at all tiers`() {
        let recreationalOnly: [DetailSection] = [.doseDuration, .effects, .combinations, .water, .misconceptions]
        for profile in UserProfile.allCases {
            let p = DisclosurePolicy(profile: profile)
            for section in recreationalOnly {
                #expect(p.placement(for: section, spine: .medical) == .hidden)
            }
            // ...and leads with the medical sections, inline at every tier.
            for section in [DetailSection.medicalUses, .boxedWarning, .contraindications] {
                #expect(p.placement(for: section, spine: .medical) == .inline)
            }
        }
    }

    @Test
    func `Boxed warnings stay inline even on the recreational spine`() {
        // Safety-critical: an opioid (recreational spine) must still surface its
        // boxed warning inline at every tier.
        for profile in UserProfile.allCases {
            let p = DisclosurePolicy(profile: profile)
            #expect(p.placement(for: .boxedWarning, spine: .recreational) == .inline)
            #expect(p.placement(for: .contraindications, spine: .recreational) == .inline)
        }
    }

    @Test
    func `A pure Rx renders the medical spine with no dose or misconceptions`() {
        let p = DisclosurePolicy(profile: .harmReduction)
        let spine = p.spine(for: .medicalRx)
        #expect(spine == .medical)
        #expect(p.placement(for: .doseDuration, spine: spine) == .hidden)
        #expect(p.placement(for: .misconceptions, spine: spine) == .hidden)
        #expect(p.placement(for: .medicalUses, spine: spine) == .inline)
    }
}
