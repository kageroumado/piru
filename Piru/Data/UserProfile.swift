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
enum UserProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    case casual
    case harmReduction = "harm-reduction"
    case pharmaNerd = "pharma-nerd"

    var id: String { rawValue }

    var displayName: LocalizedStringResource {
        switch self {
        case .casual:        "Casual"
        case .harmReduction: "Harm Reduction"
        case .pharmaNerd:    "Pharma Nerd"
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
        case .casual:        "leaf"
        case .harmReduction: "heart.text.square"
        case .pharmaNerd:    "atom"
        }
    }
}
