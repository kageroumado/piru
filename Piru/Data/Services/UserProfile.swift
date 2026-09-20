import Foundation
import SwiftUI

/// How much pharmacology the app opens with. Controls the *default* expanded
/// state of the folding sections on a substance page and the wording of the
/// Tolerance tool; every section is on the page at both levels, and the user
/// can always open or close one by hand. Persisted on ``UserProfileRecord``.
///
/// - ``casual`` — plain class names ("Sedatives"), pharmacology folded.
/// - ``curious`` — the default. Mechanism and pharmacokinetics open on the
///   page; receptor-level class names and contributor chips in the Tolerance tool.
enum UserProfile: String, CaseIterable, Codable, Identifiable {
    case casual
    /// The default. Its raw value is the wire value of the tier it grew out of
    /// and is what installed builds have stored — never rename it to match.
    case curious = "harm-reduction"

    /// Decodes a stored tier. `pharma-nerd` was a third, deeper tier whose only
    /// differences folded into Curious; a store still holding it opens as Curious.
    init?(wire: String) {
        switch wire {
        case "pharma-nerd": self = .curious
        default: self.init(rawValue: wire)
        }
    }

    var id: String {
        rawValue
    }

    var displayName: LocalizedStringResource {
        switch self {
        case .casual: "Casual"
        case .curious: "Curious"
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .casual: "Plain names, pharmacology folded away until you open it."
        case .curious: "Mechanism and pharmacokinetics open on the page, receptor names in the Tolerance tool."
        }
    }

    /// SF Symbol used in pickers and the settings row.
    var icon: String {
        switch self {
        case .casual: "leaf"
        case .curious: "atom"
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
    /// citations. Dense, so it starts folded for Casual — but present.
    var showsReceptorLiterature: Bool {
        true
    }
    /// Per-route pharmacokinetics (bioavailability/tmax/half-life) + CYP
    /// metabolism tables with per-row citations. Folded for Casual.
    var showsPharmacokinetics: Bool {
        true
    }

    var mechanismDefaultExpanded: Bool {
        profile == .curious
    }
    var subjectiveDefaultExpanded: Bool {
        profile == .curious
    }
    /// Folded at every tier. Attribution is reference material you go looking
    /// for, not something to scroll past on the way out of the page — and the
    /// ledger is one row per source, so unfolded it is the longest block on the
    /// screen for the reader least likely to want it.
    var sourcesDefaultExpanded: Bool {
        false
    }
    var receptorLitDefaultExpanded: Bool {
        profile == .curious
    }
    /// The per-route tables start collapsed even for Curious — they are dense
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
    /// that shouldn't dominate the scroll, but belongs on the page).
    case inlineCollapsed
    /// Omit entirely at this tier.
    case hidden

    /// True when the section renders in the main scroll — either fully (`inline`)
    /// or as a collapsed group (`inlineCollapsed`).
    var isInline: Bool {
        self == .inline || self == .inlineCollapsed
    }
}

/// The two presentational spines the detail page chooses between up front. A
/// recreational/dual-use/OTC compound gets the dose-gauge/effects/combinations
/// spine; a prescription/non-recreational compound gets the medical spine
/// with no dose gauge, no effects-by-dose, no misconceptions.
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
            tiered(casual: .inlineCollapsed, curious: .inline)
        // The full Kᵢ/EC₅₀ literature table: present everywhere, collapsed
        // everywhere — it is long, and nobody scrolls past it by accident, so
        // even Curious gets it folded. This now agrees with
        // `showsReceptorLiterature`, which is a constant: the matrix and the
        // boolean must never disagree, because between them they are the only
        // documentation of what a tier means.
        case .receptorLiterature:
            tiered(casual: .inlineCollapsed, curious: .inlineCollapsed)
        // Chemistry / sources: collapsed on-page at every tier.
        case .chemistry, .sources:
            tiered(casual: .inlineCollapsed, curious: .inlineCollapsed)
        // The recreational body — shown on the recreational spine, never on the
        // medical one (no dose gauge / effects / water / misconceptions on a statin).
        case .doseDuration, .effects, .combinations, .water, .misconceptions:
            spine == .recreational ? .inline : .hidden
        // The user's own history: always inline on both spines, and
        // self-hiding when empty.
        case .history:
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
    ) -> SectionPlacement {
        switch profile {
        case .casual: casual
        case .curious: curious
        }
    }
}
