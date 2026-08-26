import Foundation

/// What the clinical-trial literature found for one intervention tried alongside a benzodiazepine
/// taper, resolved from the bundled DB's `taper_interventions`.
///
/// The verdict and the trial arithmetic are data and come from the database; the sentence a reader
/// sees is copy and stays here, keyed by ``Kind`` — so a row can never ship an untranslated finding,
/// and the numbers inside those sentences are gated against the columns by
/// `TaperInterventionTests`.
nonisolated struct TaperIntervention: Identifiable, Sendable {
    let kind: Kind
    let verdict: Verdict
    /// n of the single controlled trial this row rests on; `nil` when it rests on several trials with
    /// different ns, or on synthesis rather than one study.
    let sampleSize: Int?
    /// How many trials the row summarizes, when the row is a count of them.
    let trialCount: Int?

    var id: String {
        kind.rawValue
    }

    enum Verdict: String, Sendable {
        case supported
        case notSupported = "not-supported"

        /// The section this verdict's rows read under.
        var sectionTitle: LocalizedStringResource {
            switch self {
            case .supported: "Supported by evidence"
            case .notSupported: "Not supported by evidence"
            }
        }
    }

    enum Kind: String, Sendable, CaseIterable {
        case cbtPlusTaper = "cbt-plus-taper"
        case gradualTaper = "gradual-taper"
        case imipramine
        case carbamazepine
        case pregabalin
        case valproate
        case flumazenil
        case melatonin
        case longActingSwitch = "long-acting-switch"
        case gabapentin
        case lithium
        case progesterone
        case magnesiumAspartate = "magnesium-aspartate"
        case ondansetron
        case buspirone
        case propranolol

        var name: LocalizedStringResource {
            switch self {
            case .cbtPlusTaper: "CBT + gradual taper"
            case .gradualTaper: "Gradual taper"
            case .imipramine: "Imipramine"
            case .carbamazepine: "Carbamazepine"
            case .pregabalin: "Pregabalin"
            case .valproate: "Valproate"
            case .flumazenil: "Flumazenil"
            case .melatonin: "Melatonin"
            case .longActingSwitch: "Long-acting benzo switch"
            case .gabapentin: "Gabapentin"
            case .lithium: "Lithium"
            case .progesterone: "Progesterone"
            case .magnesiumAspartate: "Magnesium aspartate"
            case .ondansetron: "Ondansetron"
            case .buspirone: "Buspirone"
            case .propranolol: "Propranolol"
            }
        }

        var finding: LocalizedStringResource {
            switch self {
            case .cbtPlusTaper:
                "The strongest result in the literature. Discontinuation significantly higher than taper alone at both 3 months and 6–12 months."
            case .gradualTaper:
                "About two-thirds discontinue short-term; roughly one-third sustain long-term. Consensus rate: 25% reduction per week over 4–6 weeks."
            case .imipramine:
                "Taper success 82.6% vs 37.5% placebo."
            case .carbamazepine:
                "More patients BZD-free at week 5; lower withdrawal incidence and anxiety in elderly."
            case .pregabalin:
                "Safe and effective for tapering off long-term use; improved sleep."
            case .valproate:
                "79% abstinent at 5 weeks post-taper vs placebo. No effect at 12 weeks."
            case .flumazenil:
                "Reversed withdrawal scores and craving vs oxazepam taper and placebo. Inpatient IV only — dangerous in chronic users (precipitated withdrawal)."
            case .melatonin:
                "One small positive trial (n = 34); two larger negative trials (n = 80, n = 38 at 1-year follow-up). Improved sleep quality without improving discontinuation."
            case .longActingSwitch:
                "Insufficient evidence to support the efficacy of this strategy — despite being the standard move and the core of the Ashton method."
            case .gabapentin:
                "No difference vs placebo."
            case .lithium:
                "More than 60% discontinuation in both arms; no difference."
            case .progesterone:
                "No difference on withdrawal severity, anxiety, or drug-free status."
            case .magnesiumAspartate:
                "No difference on any endpoint."
            case .ondansetron:
                "No effect on taper rate, withdrawal severity, or anxiety."
            case .buspirone:
                "Four small trials with contradictory results."
            case .propranolol:
                "Reduced symptom severity in completers; no effect on dropout rate or incidence."
            }
        }
    }

    /// The evidence line under the finding: what kind of study, and how big. Composed from the
    /// database's own `sample_size` and `trial_count` wherever the row carries them, so the line and
    /// the columns cannot drift apart.
    var detail: LocalizedStringResource? {
        switch kind {
        case .cbtPlusTaper: "Meta-analysis"
        case .gradualTaper: "Clinical consensus"
        case .pregabalin:
            sampleSize.map { "1 RCT (n = \($0)) + open study (n = 282)" }
        case .gabapentin:
            sampleSize.map { "n = \($0), underpowered" }
        case .imipramine, .valproate:
            sampleSize.map { "RCT, n = \($0)" }
        case .lithium, .progesterone, .magnesiumAspartate, .ondansetron, .propranolol:
            sampleSize.map { "n = \($0)" }
        case .carbamazepine:
            trialCount.map { "\($0) RCTs" }
        case .flumazenil:
            trialCount.map { "\($0) trials" }
        // Melatonin and buspirone count their own trials inside the finding, and the switch has no
        // trial of the strategy itself to count.
        case .melatonin, .buspirone, .longActingSwitch:
            nil
        }
    }
}
