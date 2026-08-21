import Foundation

extension SubstanceCategory {
    /// What this class of substance *is*, in one or two sentences.
    ///
    /// Sits at the top of the category's browse list, above the substances. It
    /// answers the question a reader arriving at "Stimulant" actually has —
    /// what do these have in common? — which the list of names cannot.
    ///
    /// Written as description, never instruction: what the class does to a
    /// person, and the one thing that most distinguishes it from its
    /// neighbours. `nil` for the categories that are a filing convenience
    /// rather than a pharmacological family.
    var classSummary: LocalizedStringResource? {
        switch self {
        case .stimulant:
            "Raise dopamine and noradrenaline signalling, which raises drive, attention and wakefulness — and heart rate and temperature with them. They differ mostly in how they do it: releasing the neurotransmitter, or blocking its reuptake."
        case .psychedelic:
            "Agonists at the 5-HT2A receptor. That single action reshapes perception, thought and the sense of self; the family splits by chemistry — phenethylamines, tryptamines, and the ergolines LSD belongs to."
        case .dissociative:
            "Block the NMDA glutamate receptor, uncoupling perception from the body that reports it. The effect scales sharply with dose, from analgesia through anaesthesia."
        case .dysdelic:
            "Act at the κ-opioid receptor rather than 5-HT2A, which is why the experience is nothing like a classical psychedelic — dysphoric, disorienting, and usually brief."
        case .deliriant:
            "Block muscarinic acetylcholine receptors. Unlike psychedelics they produce true hallucinations — things that are not there and are not recognised as unreal — alongside amnesia and a narrow margin to toxicity."
        case .opioid:
            "Agonists at the µ-opioid receptor: analgesia, warmth and sedation, and depressed breathing by the same mechanism. Tolerance to the first outpaces tolerance to the last, which is what makes the margin narrow."
        case .benzodiazepine:
            "Positive allosteric modulators at GABA-A — they amplify the brain's own inhibitory signal rather than acting on their own. That ceiling is why they are relatively safe alone and dangerous with anything else that sedates."
        case .gabapentinoid:
            "Bind the α2δ subunit of voltage-gated calcium channels, reducing excitatory transmitter release. Not GABAergic despite the name."
        case .empathogen:
            "Release serotonin, along with dopamine and noradrenaline — warmth, closeness and emotional openness rather than the perceptual change of a psychedelic. Most are amphetamines with a methylenedioxy ring."
        case .cannabinoid:
            "Act at the CB1 receptor. The phytocannabinoids are partial agonists with a natural ceiling; the synthetic ones are full agonists without it, which is the whole of the difference in risk."
        case .nootropic:
            "A functional grouping rather than a mechanistic one: compounds taken for cognition, with radically different pharmacology and, mostly, thin human evidence."
        case .ampakine:
            "Positive allosteric modulators of the AMPA glutamate receptor. The high-impact ones carry convulsant liability; the low-impact ones are safer and weaker."
        case .eugeroic:
            "Promote wakefulness without the dopaminergic surge of a classical stimulant. Mechanism is still argued over; the effect is alertness without much euphoria."
        case .depressant:
            "Slow central nervous system activity, mostly through GABA. Their doses add up with each other in a way that is easy to underestimate."
        case .orexinAntagonist:
            "Block the orexin receptors that hold wakefulness in place, rather than enhancing GABA. They add next-day sedation with other depressants but not brainstem respiratory depression."
        case .antidepressant:
            "Raise serotonin, noradrenaline or dopamine signalling over weeks rather than hours. The class matters here mostly for what it blocks or stacks with."
        case .antipsychotic:
            "Block dopamine D2 receptors, and usually several serotonin receptors alongside. Sedating, and a common blunting agent for other substances."
        case .antihistamine:
            "Block histamine H1 receptors. The first-generation ones cross into the brain and are strongly anticholinergic, which is why they sedate — and, in quantity, deliriate."
        case .supplement:
            "Vitamins, minerals, amino acids and plant preparations. Pharmacologically a mixed bag, and the place where interactions are most often assumed to be absent."
        case .peptide:
            "Short chains of amino acids acting at hormone or growth-factor receptors. Almost all are injected, and almost none have long-term human data."
        case .anticonvulsant:
            "Damp excessive neuronal firing, by sodium-channel block, GABA enhancement or SV2A binding depending on the drug."
        case .analgesic, .cardiovascular, .antimicrobial, .gastrointestinal,
             .respiratory, .endocrine, .immunological, .other:
            nil
        }
    }
}
