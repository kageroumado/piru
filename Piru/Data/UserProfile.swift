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
        case .harmReduction: "Harm Reduction"
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
}
