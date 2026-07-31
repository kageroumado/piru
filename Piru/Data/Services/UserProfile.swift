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
/// **Show vs expand:** "shows" means the section appears in the view at all;
/// "default expanded" means the `DisclosureGroup` starts open. A casual user
/// never sees the pharma-nerd surfaces (no manual override). A harm-reduction
/// user sees mechanism/subjective effects but they start collapsed.
struct DisclosurePolicy: Hashable {
    let profile: UserProfile

    /// Mechanism summary + binding affinity grid (the in-app curated
    /// summary, distinct from the literature table below).
    var showsMechanism: Bool {
        profile != .casual
    }
    /// Rich subjective effects with PsychonautWiki-style descriptions.
    var showsRichSubjective: Bool {
        profile != .casual
    }
    /// Substance-level "Sources" disclosure at the bottom. Shown to every
    /// tier — even casual users may want to see source attribution.
    var showsSources: Bool {
        true
    }
    /// The full receptor-binding literature table with Ki/EC50 and per-row
    /// citations. Only pharma-nerd surface.
    var showsReceptorLiterature: Bool {
        profile == .pharmaNerd
    }
    /// Per-route pharmacokinetics (bioavailability/tmax/half-life) + CYP
    /// metabolism tables with per-row citations. Only pharma-nerd surface.
    var showsPharmacokinetics: Bool {
        profile == .pharmaNerd
    }

    var mechanismDefaultExpanded: Bool {
        profile == .pharmaNerd
    }
    var subjectiveDefaultExpanded: Bool {
        profile == .pharmaNerd
    }
    var sourcesDefaultExpanded: Bool {
        profile != .casual
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
        // Mechanism + "in the body" (PK): hidden for Casual, on-page from there.
        //
        // `.showAll` — a row that pushed a whole screen holding one card — is
        // gone from this matrix. The cards already fold; wrapping a fold in a
        // navigation push meant two taps and a screen transition to reach a
        // disclosure triangle, and it split one substance's pharmacology across
        // two backgrounds. Depth on this screen is a fold, not a destination.
        case .mechanism, .pharmacokinetics:
            tiered(casual: .hidden, curious: .inlineCollapsed, nerd: .inline)
        // The full Kᵢ/EC₅₀ literature table: Pharma Nerd only, and collapsed even
        // there — it is long, and nobody scrolls past it by accident. Kept at
        // `.hidden` for Curious so this matrix agrees with `showsReceptorLiterature`,
        // which `PharmacologySections` still gates on; a matrix that promised the
        // table at Curious while the boolean withheld it would just be a lie in
        // the one place that documents the tiers.
        case .receptorLiterature:
            tiered(casual: .hidden, curious: .hidden, nerd: .inlineCollapsed)
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
