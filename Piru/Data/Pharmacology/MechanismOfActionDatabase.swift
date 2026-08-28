import Foundation

/// The **category floor** for the substance detail card's Pharmacology section, and the composer
/// that decides what that section shows.
///
/// This used to be a database: 226 substance names mapped onto 34 hand-written class templates,
/// each carrying prose and a receptor list. All of it now lives in the bundled SQLite —
/// per-substance rows in `mechanisms_summary` and `bindings`, class-level ones fanned out from
/// `data/curated/class-mechanisms.json`. What is left here is the floor beneath them: the
/// per-category text shown for a substance no source has described, which 1,149 substances reach.
///
/// **Do not rebuild the table.** Two failures came out of having one, and both are cheap to
/// repeat. Its generic binding lists *replaced* the cited DB panel rather than filling it,
/// dropping 150 measured targets across 67 substances. And its per-class prose could not say
/// where in a class a member sat, so the opioid floor called 66 substances full agonists —
/// 7-hydroxymitragynine's card read "μ-Opioid Receptor (MOR) Full Agonist" directly above its own
/// rows reading `μ Partial Agonist · Kᵢ 47 nM`. A class-level fact belongs in
/// `class-mechanisms.json`, whose ingester writes it only where the substance has nothing of its
/// own; a per-substance one belongs in `mechanisms.json`.
enum MechanismOfActionDatabase {
    static func categoryFallback(for category: SubstanceCategory) -> MechanismOfAction? {
        categoryData[category]
    }

    /// Composes the mechanism shown in the substance detail card.
    ///
    /// - **Summary text**: the DB `mechanisms_summary` (a non-empty summary on `dbMechanism`)
    ///   wins; otherwise the per-category floor.
    /// - **Bindings**: the DB set, or the floor's when it is empty. A substance with nothing
    ///   measured shows its summary and no receptor list — an absence, not a placeholder.
    ///
    /// Pure and deterministic so it can be unit-tested without a database.
    static func resolvedMechanism(
        dbMechanism: MechanismOfAction?,
        category: SubstanceCategory,
    ) -> MechanismOfAction? {
        let categoryMoa = categoryFallback(for: category)

        let hasDBSummary = !(dbMechanism?.summary.isEmpty ?? true)
        // A Chinese reader seeing English-only DB prose should get the localized
        // category floor instead — it is generic but in their language.
        let dbLanguageMismatch: Bool = {
            guard ContentLanguage.current.isChinese,
                  let lang = dbMechanism?.summaryLanguage else { return false }
            return !lang.hasPrefix("zh")
        }()
        let preferDB = hasDBSummary && !dbLanguageMismatch
        let textSource: MechanismOfAction? = preferDB ? dbMechanism : (categoryMoa ?? dbMechanism)
        guard let textSource else { return nil }

        var bindings = dbMechanism?.bindings ?? []
        if bindings.isEmpty { bindings = categoryMoa?.bindings ?? [] }

        return MechanismOfAction(
            summary: textSource.summary,
            description: textSource.description,
            bindings: bindings,
        )
    }

    // MARK: - Helpers

    private static func moa(
        _ summary: LocalizedStringResource, _ desc: LocalizedStringResource, _ bindings: [ReceptorBinding],
    ) -> MechanismOfAction {
        MechanismOfAction(
            summary: String(localized: summary),
            description: String(localized: desc),
            bindings: bindings,
        )
    }

    private static func b(_ target: String, _ action: BindingAction, _ affinity: BindingAffinity) -> ReceptorBinding {
        ReceptorBinding(target: target, action: action, affinity: affinity)
    }

    // MARK: - Category Fallbacks

    /// A category floor describes a substance NOTHING has described. It may name what the class
    /// does; it may never assert where in the class this member sits. Three of these used to do
    /// exactly that by aliasing a class template — the opioid floor said "Full Agonist" over 66
    /// substances, and 7-hydroxymitragynine's card carried that sentence directly above its own
    /// measured rows reading `μ Partial Agonist, Ki 47 nM`. Pentazocine and butorphanol, whose
    /// ceiling effect is the clinically important fact about them, read as full agonists too.
    private static let opioidUnspecified = moa(
        "μ-Opioid Receptor Ligand",
        "Acts at μ-opioid receptors (MOR), G-protein coupled receptors distributed throughout the central and peripheral nervous system. MOR activation inhibits adenylyl cyclase, opens inwardly rectifying potassium channels, and closes voltage-gated calcium channels, reducing neuronal excitability and neurotransmitter release — producing analgesia, euphoria, respiratory depression, and slowed gastrointestinal transit. How far this particular compound activates the receptor, and whether it also engages κ or δ, is not characterized here; the receptor panel below carries whatever has been measured for it.",
        [],
    )

    private static let antipsychoticUnspecified = moa(
        "Antipsychotic (Dopamine Receptor Antagonist)",
        "Blocks dopamine D2 receptors in the mesolimbic pathway, reducing positive psychotic symptoms. Whether this compound also carries the 5-HT2A antagonism that distinguishes the second-generation agents, and the histamine, muscarinic and adrenergic activity that drives sedation and orthostasis, varies across the class and is not characterized here.",
        [],
    )

    private static let antihistamineUnspecified = moa(
        "Histamine H1 Receptor Antagonist",
        "Blocks histamine H1 receptors, reducing the itching, flare, wheal and vasodilation of the histamine response. Whether this compound crosses into the central nervous system — the difference between a sedating first-generation antihistamine with a muscarinic load and a peripherally selective second-generation one — is not characterized here.",
        [],
    )

    // The category floor supplies PROSE. It supplies a binding list only where the category
    // names actual molecular targets — orexinAntagonist's OX1R/OX2R, and the entries that reuse
    // a class template above.
    //
    // No entry here may name a system, a pathway, or "Various" as a receptor. `Pain pathways`,
    // `Microbial targets`, `Cardiovascular system`, `GI system`, `Immune system` and `Various`
    // were all rendered as graded chips with filled strength dots — a claim of measured affinity
    // at something that is not a target, on 42% of the library. A substance with nothing
    // measured shows its summary and no receptor list; an empty section is the honest answer and
    // a placeholder is not.

    private static let categoryData: [SubstanceCategory: MechanismOfAction] = [
        .stimulant: moa(
            "Central Nervous System Stimulant",
            "Increases central nervous system activity by enhancing monoamine neurotransmission, typically through increased release or reduced reuptake of dopamine and/or norepinephrine. The specific mechanism varies by substance class (releasing agents, reuptake inhibitors, or receptor agonists). Effects include increased alertness, attention, and energy.",
            [],
        ),
        .psychedelic: moa(
            "Serotonin 5-HT2A Receptor Agonist (Classical Psychedelic)",
            "Primarily acts as an agonist or partial agonist at serotonin 5-HT2A receptors, particularly on layer V pyramidal neurons in the prefrontal cortex. 5-HT2A activation increases glutamate release and enhances cortical excitability, leading to altered perception, cognition, and consciousness. Most classical psychedelics also interact with 5-HT2C, 5-HT1A, and other serotonin receptor subtypes.",
            [],
        ),
        .dissociative: moa(
            "NMDA Receptor Antagonist (Dissociative)",
            "Blocks N-methyl-D-aspartate (NMDA) glutamate receptors, typically by binding within the ion channel pore as a non-competitive antagonist. NMDA receptor blockade reduces excitatory glutamatergic neurotransmission, producing dissociative anesthesia, analgesia, and altered states of consciousness characterized by feelings of detachment from body and environment.",
            [],
        ),
        .opioid: opioidUnspecified,
        .benzodiazepine: moa(
            "GABA-A Positive Allosteric Modulator (Benzodiazepine)",
            "Binds to the benzodiazepine site at the interface of α and γ subunits on GABA-A receptors, acting as a positive allosteric modulator. Enhances the effect of GABA by increasing the frequency of chloride channel opening, leading to neuronal hyperpolarization and reduced excitability. Produces anxiolytic, sedative, hypnotic, anticonvulsant, and muscle relaxant effects.",
            [],
        ),
        .gabapentinoid: moa(
            "Voltage-Gated Calcium Channel α2δ Subunit Ligand",
            "Binds to the α2δ-1 subunit of voltage-gated calcium channels (VGCCs), reducing calcium influx at presynaptic nerve terminals. This decreases the release of excitatory neurotransmitters including glutamate, norepinephrine, substance P, and calcitonin gene-related peptide. Despite the name, gabapentinoids do not interact with GABA receptors or GABA metabolism.",
            [],
        ),
        .empathogen: moa(
            "Monoamine Releasing Agent (Serotonin-Predominant)",
            "Increases synaptic serotonin, dopamine, and norepinephrine, with a predominant serotonergic component that distinguishes empathogens from classical stimulants. Many also stimulate the release of oxytocin from the hypothalamus, contributing to prosocial effects, emotional openness, and feelings of empathy and connectedness.",
            [],
        ),
        .cannabinoid: moa(
            "Cannabinoid CB1/CB2 Receptor Agonist",
            "Acts as an agonist at cannabinoid CB1 receptors in the central nervous system and CB2 receptors in immune tissues. CB1 activation inhibits adenylyl cyclase and modulates ion channels via Gi/Go proteins, reducing neurotransmitter release (particularly GABA and glutamate) in brain regions involved in reward, memory, coordination, and pain perception.",
            [],
        ),
        .nootropic: moa(
            "Cognitive-Enhancing Agent (Nootropic)",
            "Nootropic agents enhance cognitive function through diverse mechanisms which may include modulation of acetylcholine, glutamate, or monoamine neurotransmitter systems; improvement of cerebral blood flow; neuroprotection through antioxidant activity; or modulation of neuroplasticity signaling cascades. Mechanisms vary widely and are substance-specific.",
            [],
        ),
        .depressant: moa(
            "Central Nervous System Depressant",
            "Reduces central nervous system excitability, typically through enhancement of inhibitory GABAergic neurotransmission and/or reduction of excitatory glutamatergic neurotransmission. Produces sedation, anxiolysis, and muscle relaxation in a dose-dependent manner.",
            [],
        ),
        .orexinAntagonist: moa(
            "Dual Orexin Receptor Antagonist (DORA)",
            "Competitively blocks the orexin (hypocretin) receptors OX1R and OX2R, the targets of the wake-promoting neuropeptides orexin-A and orexin-B released from the lateral hypothalamus. Rather than broadly sedating the brain like a GABAergic hypnotic, it withdraws a specific \"stay awake\" drive that stabilizes arousal — permitting the natural transition into sleep with largely preserved sleep architecture and arousability. Because it does not enhance GABA or depress brainstem respiratory centers, it lacks the respiratory-depression synergy and dependence liability characteristic of benzodiazepines, Z-drugs, and other GABAergic sedatives.",
            [b("OX1R", .antagonist, .primary), b("OX2R", .antagonist, .primary)],
        ),
        .antidepressant: moa(
            "Antidepressant (Monoamine Modulator)",
            "Modulates monoamine neurotransmitter systems (serotonin, norepinephrine, and/or dopamine) through various mechanisms including reuptake inhibition, enzyme inhibition, or receptor modulation. The specific mechanism depends on the drug class. Therapeutic effects typically develop over 2–6 weeks.",
            [],
        ),
        .antipsychotic: antipsychoticUnspecified,
        .analgesic: moa(
            "Analgesic Agent",
            "Reduces pain perception through mechanisms that may include inhibition of prostaglandin synthesis, activation of endogenous opioid pathways, modulation of descending pain inhibitory circuits, or blockade of peripheral nociceptor sensitization. The specific mechanism depends on the drug class.",
            [],
        ),
        .antihistamine: antihistamineUnspecified,
        .cardiovascular: moa(
            "Cardiovascular Agent",
            "Modulates cardiovascular function through mechanisms including adrenergic receptor blockade, calcium channel inhibition, renin-angiotensin system modulation, or direct vasodilation. The specific mechanism depends on the drug class.",
            [],
        ),
        .antimicrobial: moa(
            "Antimicrobial Agent",
            "Eliminates or inhibits the growth of microorganisms by targeting microbial-specific processes such as cell wall synthesis, protein synthesis, nucleic acid replication, metabolic pathways, or cell membrane integrity.",
            [],
        ),
        .gastrointestinal: moa(
            "Gastrointestinal Agent",
            "Modulates digestive function through mechanisms such as acid secretion inhibition, motility modulation, mucosal protection, or neurotransmitter receptor interactions in the enteric nervous system.",
            [],
        ),
        .respiratory: moa(
            "Respiratory Agent",
            "Modulates airway function through mechanisms including bronchodilation via β2-adrenergic agonism or anticholinergic blockade, anti-inflammatory effects from corticosteroids, mast cell stabilization, or leukotriene receptor antagonism.",
            [],
        ),
        .endocrine: moa(
            "Endocrine Agent",
            "Modulates hormonal signaling through receptor agonism or antagonism, enzyme inhibition affecting hormone synthesis or metabolism, or direct hormone replacement. Interacts with the hypothalamic-pituitary-endocrine axes.",
            [],
        ),
        .immunological: moa(
            "Immunomodulatory Agent",
            "Modulates immune system function through mechanisms such as inhibition of inflammatory cytokine production, suppression of T-cell or B-cell activation, complement system modulation, or targeted inhibition of specific immune pathways.",
            [],
        ),
        .supplement: moa(
            "Dietary Supplement",
            "Supports physiological functions through various mechanisms including enzyme cofactor activity, antioxidant effects, neurotransmitter precursor supply, hormonal modulation, or direct receptor interactions. Mechanisms vary widely and are substance-specific.",
            [],
        ),
        .other: moa(
            "Pharmacological Agent",
            "This substance's mechanism of action may involve multiple pharmacological targets or may not be fully characterized. Consult specific pharmacological references for detailed mechanistic information.",
            [],
        ),
    ]
}
