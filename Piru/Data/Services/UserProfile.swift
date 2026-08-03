import Foundation
import SwiftUI

/// The user's chosen disclosure tier. Controls *default* expanded state for
/// progressive-disclosure sections in views like ``SubstanceDetailView``; the
/// user can always override a section manually. Persisted to the
/// `user_profile` key-value table in the user-prefs SQLite DB.
///
/// ## Tiers
///
/// - ``casual`` — basics only. Dose ladder, duration, top-line warnings. No
///   mechanism detail, no receptor data, no advanced filters. Aimed at people
///   tracking everyday medications.
/// - ``harmReduction`` — adds interaction depth, summary mechanism, subjective
///   effects, sources. The default. Matches the "TripSit + PsychonautWiki"
///   surface most harm-reduction users expect.
/// - ``pharmaNerd`` — everything: receptor binding tables with Ki/Kd/EC50,
///   biased agonism, CYP metabolism, pharmacogenetics, off-targets, full
///   per-source attribution. Aimed at researchers and people who, in the
///   project goal's own words, "take tons of various chemicals and want to
///   learn how different substances could interact with each other or
///   influence tolerance, or the biased agonism".
enum UserProfile: String, CaseIterable, Codable, Identifiable {
    case casual
    case harmReduction = "harm-reduction"
    case pharmaNerd = "pharma-nerd"

    var id: String {
        rawValue
    }

    var displayName: LocalizedStringResource {
        switch self {
        case .casual: "Casual"
        case .harmReduction: "Curious"
        case .pharmaNerd: "Pharma Nerd"
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .casual:
            "Dose ladders, durations, top-line warnings. Skip the deep pharmacology."
        case .harmReduction:
            "Interactions, mechanisms, subjective effects, and source citations."
        case .pharmaNerd:
            "Everything — receptor binding tables, biased agonism, CYP metabolism, citations down to DOI."
        }
    }

    /// SF Symbol used in pickers and the settings row.
    var icon: String {
        switch self {
        case .casual: "leaf"
        case .harmReduction: "heart.text.square"
        case .pharmaNerd: "atom"
        }
    }
}

/// Pure policy describing which detail-view sections are visible and which
/// are expanded by default for a given profile tier. Extracted from
/// ``SubstanceDetailView`` so the tier matrix is independently testable —
/// regressions in tier visibility would otherwise need a SwiftUI snapshot
/// test to catch.
///
/// **The tier folds, it does not delete.** Every section is present at every
/// tier; what the tier decides is whether a section arrives *open* or *folded*.
/// A Casual user still has the mechanism, the class signature, the receptor
/// table and the PK data on the page — collapsed, one tap away — rather than
/// being silently denied that they exist.
///
/// **Do not make any `shows*` gate tier-dependent, and do not return `.hidden`
/// from the placement matrix for a tier.** A tier is a statement about
/// *density*, not about who is allowed to know things — the app is a reference,
/// and a reference does not hide its evidence. Tiering belongs entirely in the
/// `*DefaultExpanded` flags and in `.inline` vs `.inlineCollapsed`.
struct DisclosurePolicy: Hashable {
    let profile: UserProfile

    /// Mechanism summary + binding affinity grid (the in-app curated
    /// summary, distinct from the literature table below).
    var showsMechanism: Bool {
        true
    }
    /// Rich subjective effects with PsychonautWiki-style descriptions.
    var showsRichSubjective: Bool {
        true
    }
    /// Substance-level "Sources" disclosure at the bottom. Shown to every
    /// tier — even casual users may want to see source attribution.
    var showsSources: Bool {
        true
    }
    /// The full receptor-binding literature table with Ki/EC50 and per-row
    /// citations. Dense, so it starts folded below Pharma Nerd — but present.
    var showsReceptorLiterature: Bool {
        true
    }
    /// Per-route pharmacokinetics (bioavailability/tmax/half-life) + CYP
    /// metabolism tables with per-row citations. Folded below Pharma Nerd.
    var showsPharmacokinetics: Bool {
        true
    }

    var mechanismDefaultExpanded: Bool {
        profile == .pharmaNerd
    }
    var subjectiveDefaultExpanded: Bool {
        profile == .pharmaNerd
    }
    /// Folded at every tier. Attribution is reference material you go looking
    /// for, not something to scroll past on the way out of the page — and the
    /// ledger is one row per source, so unfolded it is the longest block on the
    /// screen for the reader least likely to want it.
    var sourcesDefaultExpanded: Bool {
        false
    }
    var receptorLitDefaultExpanded: Bool {
        profile == .pharmaNerd
    }
    /// Pharmacokinetics starts collapsed even for pharma-nerds — it's dense
    /// reference data that would otherwise dominate the scroll.
    var pharmacokineticsDefaultExpanded: Bool {
        false
    }
}

// MARK: - Section placement matrix (redesigned detail view)

/// Where a detail section lands for a given tier — the redesign's replacement
/// for the show/expand booleans above. Consumed by ``SubstanceDetailLayout``.
/// The booleans survive because individual section views still read them for
/// their own internal gating (``DisclosurePolicy/showsMechanism`` and friends).
enum SectionPlacement: Hashable {
    /// Render the full section view in the main scroll.
    case inline
    /// Render a compact summary inline with a "Show all ›" affordance that
    /// pushes the deep-data page (the coordinator may fold several `showAll`
    /// sections into one "For the curious" launcher at the Casual tier).
    case showAll
    /// Render inline as a **collapsed** `DisclosureGroup` (dense reference data
    /// that shouldn't dominate the scroll, but a Pharma Nerd wants on-page).
    case inlineCollapsed
    /// Omit entirely at this tier.
    case hidden

    /// True when the section renders in the main scroll — either fully (`inline`)
    /// or as a collapsed group (`inlineCollapsed`).
    var isInline: Bool {
        self == .inline || self == .inlineCollapsed
    }
    /// True when the section contributes nothing to the main scroll — used to
    /// decide whether a page is legitimately short vs. hiding reachable depth.
    var isHidden: Bool {
        self == .hidden
    }
    /// True when the section's real content lives on a pushed deep-data page.
    var leadsToDeepData: Bool {
        self == .showAll
    }
}

/// The two presentational spines the detail page chooses between up front. A
/// recreational/dual-use/OTC compound gets the dose-gauge/effects/combinations
/// spine; a prescription/non-recreational compound gets the medical spine
/// (indications, boxed warning, contraindications) with no dose gauge, no
/// effects-by-dose, no misconceptions.
enum DetailSpine: Hashable {
    case recreational
    case medical
}

/// A placement-matrix row — one detail section. Identity/header are always
/// present and are not matrix rows.
enum DetailSection: Hashable, CaseIterable {
    // Shared
    case history
    case mechanism
    case receptorLiterature
    case pharmacokinetics
    case chemistry
    case sources
    // Recreational spine
    case doseDuration
    case effects
    case combinations
    case water
    case misconceptions
    // Medical spine
    case medicalUses
    case boxedWarning
    case contraindications
}

extension DisclosurePolicy {
    /// Which spine a compound's display class selects. Mirrors
    /// ``CompoundDisplayClass/showsDoseLadder`` so the two never diverge:
    /// recreational/dual-use/OTC → recreational spine; medical-Rx /
    /// non-recreational → medical spine.
    func spine(for displayClass: CompoundDisplayClass) -> DetailSpine {
        displayClass.showsDoseLadder ? .recreational : .medical
    }

    /// Placement of `section` at this tier, for the compound's `spine`. Pure —
    /// the single source of truth for the redesigned view's row set, and the
    /// thing `DisclosurePolicyTests` pins.
    /// The two spines differ *only* in the body rows — the pharmacology ladder
    /// (mechanism/receptor/PK/chemistry/sources) and the always-inline
    /// safety/medical lead are identical on both. One exhaustive switch keeps
    /// them from drifting apart.
    func placement(for section: DetailSection, spine: DetailSpine) -> SectionPlacement {
        switch section {
        // Mechanism + "in the body" (PK): on-page at every tier. Casual gets it
        // folded rather than deleted — the tier controls density, not access.
        //
        // `.showAll` — a row that pushed a whole screen holding one card — is
        // gone from this matrix. The cards already fold; wrapping a fold in a
        // navigation push meant two taps and a screen transition to reach a
        // disclosure triangle, and it split one substance's pharmacology across
        // two backgrounds. Depth on this screen is a fold, not a destination.
        case .mechanism, .pharmacokinetics:
            tiered(casual: .inlineCollapsed, curious: .inlineCollapsed, nerd: .inline)
        // The full Kᵢ/EC₅₀ literature table: present everywhere, collapsed
        // everywhere — it is long, and nobody scrolls past it by accident, so
        // even a Pharma Nerd gets it folded. This now agrees with
        // `showsReceptorLiterature`, which is a constant: the matrix and the
        // boolean must never disagree, because between them they are the only
        // documentation of what a tier means.
        case .receptorLiterature:
            tiered(casual: .inlineCollapsed, curious: .inlineCollapsed, nerd: .inlineCollapsed)
        // Chemistry / sources: collapsed on-page at every tier.
        case .chemistry, .sources:
            tiered(casual: .inlineCollapsed, curious: .inlineCollapsed, nerd: .inlineCollapsed)
        // The recreational body — shown on the recreational spine, never on the
        // medical one (no dose gauge / effects / water / misconceptions on a statin).
        case .doseDuration, .effects, .combinations, .water, .misconceptions:
            spine == .recreational ? .inline : .hidden
        // The user's own history + the safety/medical lead (indications, boxed
        // warning, contraindications): always inline on both spines. Sections
        // self-hide when empty, so a recreational compound with no boxed warning
        // simply renders nothing here.
        case .history, .medicalUses, .boxedWarning, .contraindications:
            .inline
        }
    }

    /// Convenience: resolve the spine from `displayClass` first.
    func placement(for section: DetailSection, displayClass: CompoundDisplayClass) -> SectionPlacement {
        placement(for: section, spine: spine(for: displayClass))
    }

    private func tiered(
        casual: SectionPlacement,
        curious: SectionPlacement,
        nerd: SectionPlacement,
    ) -> SectionPlacement {
        switch profile {
        case .casual: casual
        case .harmReduction: curious
        case .pharmaNerd: nerd
        }
    }
}
