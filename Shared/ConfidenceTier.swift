import Foundation

/// How much to trust a *predicted* pharmacology parameter (Vd, Kᵢ/EC₅₀, tolerance κ/τ, …).
///
/// Mirrors the grading of the citation-verification pipeline (the pharmacology axis "Foundation C"):
/// every curated parameter is graded HIGH/MEDIUM/LOW from primary literature, and anything that falls
/// back to a class default ships ``unverified``. The app renders this tier next to every prediction —
/// the house labeling rule is "predicted (model, confidence)", never "measured".
///
/// Lives in `Shared` (pure, no SwiftUI) so any target can carry the grade; the on-screen badge is a
/// separate view in the app target.
nonisolated enum ConfidenceTier: String, Codable, CaseIterable, Comparable {
    /// Literature Kᵢ/EC₅₀ + a measured Vd for this specific substance/target.
    case high
    /// Class-default (tier-mapped) parameters, or a single-source / caveated value.
    case medium
    /// Sparse binding data — ordinal affinity only, no reliable absolute number.
    case low
    /// No verified value for this substance; a class default stood in. Strongest caveat.
    case unverified

    /// Most-to-least trustworthy, for sorting and `Comparable`.
    private var rank: Int {
        switch self {
        case .high: 3
        case .medium: 2
        case .low: 1
        case .unverified: 0
        }
    }

    static func < (lhs: ConfidenceTier, rhs: ConfidenceTier) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Parse a pipeline grade string (`"HIGH"`/`"MEDIUM"`/`"LOW"`/`"NONE"`/…), case-insensitively.
    /// Unknown, empty, or `NONE` → ``unverified`` (a missing grade is not a trustworthy one).
    init(grade: String?) {
        switch grade?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "HIGH": self = .high
        case "MEDIUM", "MED": self = .medium
        case "LOW": self = .low
        default: self = .unverified
        }
    }

    /// Short user-facing label, localized. Used by the badge and any "(model, confidence)" caption.
    var label: LocalizedStringResource {
        switch self {
        case .high: "High confidence"
        case .medium: "Medium confidence"
        case .low: "Low confidence"
        case .unverified: "Unverified"
        }
    }
}
