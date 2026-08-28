import SwiftUI

struct SubjectiveEffect: Codable {
    let name: String
    let description: String
}

struct ToleranceInfo: Codable {
    let halfLife: Double // days for tolerance to halve
    let fullResetDays: Double // days for full tolerance reset
    let buildRate: String // "rapid" | "moderate" | "slow"
}

enum BindingAction: String, Codable {
    case agonist
    case partialAgonist
    case antagonist
    case inverseAgonist
    case positiveAllostericModulator
    case negativeAllostericModulator
    case reuptakeInhibitor
    case releasingAgent
    case enzymeInhibitor
    case channelBlocker
    case modulator

    var displayName: LocalizedStringResource {
        switch self {
        case .agonist: "Agonist"
        case .partialAgonist: "Partial Agonist"
        case .antagonist: "Antagonist"
        case .inverseAgonist: "Inverse Agonist"
        case .positiveAllostericModulator: "PAM"
        case .negativeAllostericModulator: "NAM"
        case .reuptakeInhibitor: "Reuptake Inhibitor"
        case .releasingAgent: "Releasing Agent"
        case .enzymeInhibitor: "Enzyme Inhibitor"
        case .channelBlocker: "Channel Blocker"
        case .modulator: "Modulator"
        }
    }

    /// A small glyph that visually splits the *kind* of action — releasers (efflux, the
    /// MDMA/amphetamine mechanism) read differently at a glance from agonists (activate) and
    /// blockers/antagonists (shut down). Distinct shapes, no color, so it stays calm.
    var symbolName: String {
        switch self {
        case .agonist, .partialAgonist: "bolt.fill" // activates the target
        case .inverseAgonist: "bolt.slash.fill"
        case .releasingAgent: "arrow.up.forward.circle.fill" // pumps the neurotransmitter out
        case .reuptakeInhibitor: "arrow.uturn.up.circle" // blocks the re-uptake pump
        case .antagonist, .channelBlocker, .enzymeInhibitor: "hand.raised.fill" // blocks
        case .positiveAllostericModulator: "plus.circle"
        case .negativeAllostericModulator: "minus.circle"
        case .modulator: "slider.horizontal.3"
        }
    }
}

enum BindingAffinity: Int, Codable, Comparable {
    case weak = 1
    case significant = 2
    case primary = 3

    static func < (lhs: BindingAffinity, rhs: BindingAffinity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The single, systematic source of truth for the 3-tier receptor "strength" dots — shared by the
/// Mechanism card, the Receptor Literature card, and (eventually) advanced-search sorting/comparison,
/// so a substance never shows one strength in one place and another elsewhere.
///
/// **Measurement-aware bands.** Binding affinity (Kᵢ/Kd) and functional potency (EC₅₀/IC₅₀) live on
/// different concentration scales — a releaser's EC₅₀ runs ~10× higher than a blocker's Kᵢ for the same
/// "strong" — so each measurement type gets its own thresholds. Lower concentration = more potent = more
/// dots. Tier 3 = strong, 2 = moderate, 1 = weak (at *that* target, releaser or blocker alike).
///
/// The SQL in `SubstanceStore.resolvedMechanism` mirrors these exact cutoffs; keep them in lock-step.
enum ReceptorStrength {
    /// Resolve a binding's tier from whichever measurement it carries, preferring binding affinity
    /// (Kᵢ) over functional potency (EC₅₀, then IC₅₀). Returns nil when the row has no measured value.
    static func tier(kiNm: Double?, ec50Nm: Double?, ic50Nm: Double?) -> Int? {
        if let ki = kiNm { return bindingTier(ki) }
        if let ec = ec50Nm { return functionalTier(ec) }
        if let ic = ic50Nm { return functionalTier(ic) }
        return nil
    }

    /// Binding affinity (Kᵢ/Kd) bands: < 100 nM strong, 100–1000 nM moderate, ≥ 1000 nM weak.
    static func bindingTier(_ nm: Double) -> Int {
        if nm < 100 { return 3 }
        if nm < 1_000 { return 2 }
        return 1
    }

    /// Functional potency (EC₅₀/IC₅₀) bands, shifted ~10× from binding: < 1 µM strong, 1–10 µM moderate,
    /// ≥ 10 µM weak — so a potent releaser (MDMA NET EC₅₀ ≈ 77 nM) reads strong, not weak.
    static func functionalTier(_ nm: Double) -> Int {
        if nm < 1_000 { return 3 }
        if nm < 10_000 { return 2 }
        return 1
    }
}

struct ReceptorBinding: Codable, Identifiable {
    let target: String
    let action: BindingAction
    let affinity: BindingAffinity
    var id: String {
        "\(target)-\(action.rawValue)"
    }
}

/// Long-form substance overview prose, resolved locale-first. `machineTranslated`
/// flags FreeOD Wiki text auto-translated into the app's language so the UI can
/// label it.
struct SubstanceOverview: Codable, Hashable {
    let text: String
    let machineTranslated: Bool
    /// DB slug of the source that actually supplied the resolved text (e.g.
    /// `psychonautwiki` for an authentic English lead, `freeodwiki` for native
    /// Chinese or a machine translation). Drives the attribution row + deep link.
    var sourceSlug: String = "freeodwiki"
}

struct MechanismOfAction: Codable {
    let summary: String
    let description: String
    let primaryTargets: [String]
    let bindings: [ReceptorBinding]
    /// The language code of the DB row the summary came from (e.g. "en", "zh-Hans").
    /// `nil` when the text is from the category floor (already localized via xcstrings).
    var summaryLanguage: String?

    private enum CodingKeys: String, CodingKey {
        case summary
        case description
        case primaryTargets
        case bindings
    }

    init(summary: String, description: String, primaryTargets: [String] = [], bindings: [ReceptorBinding] = [], summaryLanguage: String? = nil) {
        self.summary = summary
        self.description = description
        self.primaryTargets = primaryTargets.isEmpty ? bindings.map(\.target) : primaryTargets
        self.bindings = bindings
        self.summaryLanguage = summaryLanguage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decode(String.self, forKey: .summary)
        description = try container.decode(String.self, forKey: .description)
        primaryTargets = try container.decodeIfPresent([String].self, forKey: .primaryTargets) ?? []
        bindings = try container.decodeIfPresent([ReceptorBinding].self, forKey: .bindings) ?? []
    }
}
