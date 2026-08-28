import Foundation

enum MechanismOfActionDatabase {
    // MARK: - Lookup

    /// Class-template lookup by substance name or pharmacology alias — a brand
    /// name or synonym (`"xanax"`, `"4-mmc"`) resolves through
    /// ``PharmacologyNameKey/sharedAliases`` to the same template as its canonical
    /// spelling. Direct keys win over an alias claiming the same spelling.
    static func mechanism(for name: String) -> MechanismOfAction? {
        PharmacologyNameKey.resolve(name, in: substanceData, aliases: PharmacologyNameKey.sharedAliases)
    }

    static func categoryFallback(for category: SubstanceCategory) -> MechanismOfAction? {
        categoryData[category]
    }

    /// The curated per-substance keys, read-only — for the shadowing audit.
    static var substanceKeys: [String] {
        Array(substanceData.keys)
    }

    /// Composes the mechanism shown in the substance detail card by precedence,
    /// so real receptor data is never hidden behind a generic template.
    ///
    /// Per-substance curated prose + bindings live in the bundled DB
    /// (`piru-curated`, the highest-priority source), so `dbMechanism` already
    /// carries them — union-merged with any measured rows by
    /// ``SubstanceStore``. The Swift `substanceData` that this reads via
    /// ``mechanism(for:)`` holds the generic, xcstrings-localized **class
    /// templates** (SSRI, benzodiazepine, …) mapped per substance; it supplies the
    /// prose when the DB has none, and adds only targets the DB does not carry.
    ///
    /// - **Summary text**: the DB `mechanisms_summary` (non-empty summary on
    ///   `dbMechanism`) wins; otherwise the class-template entry, then the
    ///   per-category fallback.
    /// - **Bindings**: the DB set (curated ∪ measured, already deduped per
    ///   receptor and tier-ordered by ``SubstanceStore``) comes first, then the
    ///   class template contributes only the targets the DB does not carry;
    ///   the category fallback applies when both are empty.
    ///
    ///   **A class template must never replace the DB panel.** It is a
    ///   hand-written generic summary of a whole class, so substituting it drops
    ///   every per-substance target the class does not share — promethazine's
    ///   D2/M1–M5, ketamine's μ-opioid and σ1, diazepam's α-subunit rows. It is
    ///   additive here for exactly that reason.
    ///
    /// Pure and deterministic so it can be unit-tested without a database.
    static func resolvedMechanism(
        dbMechanism: MechanismOfAction?,
        substanceName: String,
        category: SubstanceCategory,
    ) -> MechanismOfAction? {
        let template = mechanism(for: substanceName)
        let categoryMoa = categoryFallback(for: category)

        let hasDBSummary = !(dbMechanism?.summary.isEmpty ?? true)
        let textSource: MechanismOfAction? = hasDBSummary ? dbMechanism : (template ?? categoryMoa ?? dbMechanism)
        guard let textSource else { return nil }

        // The DB rows carry their own measured tier and action, so the strength dots
        // stay on one systematic scale (`ReceptorStrength`) without a second merge
        // pass — ketamine's NMDA reads moderate from its ~300 nM Kᵢ because that IS
        // the row shown, and the template's downstream AMPA/mTOR arrive as additions.
        var seen = Set<String>()
        var bindings: [ReceptorBinding] = []
        for binding in (dbMechanism?.bindings ?? []) + (template?.bindings ?? [])
            where seen.insert(SubstanceReadModel.normalizedBindingTarget(binding.target)).inserted {
            bindings.append(binding)
        }
        if bindings.isEmpty { bindings = categoryMoa?.bindings ?? textSource.bindings }

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

    // MARK: - Shared Class Mechanisms

    private static let ssri = moa(
        "Selective Serotonin Reuptake Inhibitor (SSRI)",
        "Selectively inhibits the serotonin transporter (SERT), blocking the reuptake of serotonin (5-HT) from the synaptic cleft into the presynaptic neuron. This increases serotonin availability at postsynaptic receptors. Therapeutic effects typically require 2–4 weeks as presynaptic 5-HT1A autoreceptors desensitize, allowing sustained serotonergic neurotransmission.",
        [b("SERT", .reuptakeInhibitor, .primary)],
    )

    private static let snri = moa(
        "Serotonin-Norepinephrine Reuptake Inhibitor (SNRI)",
        "Inhibits both the serotonin transporter (SERT) and the norepinephrine transporter (NET), blocking reuptake of both monoamines from the synaptic cleft. At lower doses, serotonin reuptake inhibition predominates; norepinephrine reuptake inhibition becomes more significant at higher doses. This dual mechanism provides antidepressant and analgesic effects.",
        [b("SERT", .reuptakeInhibitor, .primary), b("NET", .reuptakeInhibitor, .primary)],
    )

    private static let tca = moa(
        "Tricyclic Antidepressant (TCA)",
        "Inhibits the reuptake of serotonin and norepinephrine by blocking SERT and NET. Unlike SSRIs and SNRIs, TCAs also significantly antagonize histamine H1, muscarinic M1, and α1-adrenergic receptors, which accounts for their sedative, anticholinergic, and orthostatic hypotension side effects. The ratio of serotonin to norepinephrine reuptake inhibition varies between individual TCAs.",
        [
            b("SERT", .reuptakeInhibitor, .primary),
            b("NET", .reuptakeInhibitor, .primary),
            b("H1", .antagonist, .significant),
            b("M1", .antagonist, .significant),
            b("α1", .antagonist, .significant),
        ],
    )

    private static let maoi = moa(
        "Irreversible Monoamine Oxidase Inhibitor (MAOI)",
        "Irreversibly inhibits monoamine oxidase enzymes (MAO-A and MAO-B), which are responsible for the oxidative deamination of monoamine neurotransmitters. MAO-A primarily metabolizes serotonin, norepinephrine, and dopamine; MAO-B primarily metabolizes phenylethylamine and dopamine. Inhibition increases synaptic levels of all monoamines. Requires dietary tyramine restriction due to risk of hypertensive crisis.",
        [b("MAO-A", .enzymeInhibitor, .primary), b("MAO-B", .enzymeInhibitor, .primary)],
    )

    private static let rima = moa(
        "Reversible Inhibitor of Monoamine Oxidase A (RIMA)",
        "Selectively and reversibly inhibits MAO-A, increasing synaptic serotonin and norepinephrine. Unlike irreversible MAOIs, the reversible binding allows dietary tyramine to compete for the enzyme, significantly reducing the risk of hypertensive crisis and eliminating the need for strict dietary restrictions.",
        [b("MAO-A", .enzymeInhibitor, .primary)],
    )

    private static let maobSelective = moa(
        "Selective MAO-B Inhibitor",
        "Selectively inhibits monoamine oxidase B (MAO-B), which preferentially metabolizes dopamine and phenylethylamine in the brain. At selective doses, increases dopamine availability without significantly affecting serotonin or norepinephrine metabolism, and without requiring dietary tyramine restriction. At higher doses, selectivity is lost and MAO-A is also inhibited.",
        [b("MAO-B", .enzymeInhibitor, .primary)],
    )

    private static let typicalAP = moa(
        "Dopamine D2 Receptor Antagonist (First-Generation Antipsychotic)",
        "Blocks dopamine D2 receptors in the mesolimbic pathway, reducing dopaminergic neurotransmission associated with positive psychotic symptoms. Also blocks D2 receptors in the nigrostriatal pathway (causing extrapyramidal symptoms), tuberoinfundibular pathway (causing hyperprolactinemia), and mesocortical pathway. Most also antagonize histamine H1, muscarinic, and α1-adrenergic receptors to varying degrees.",
        [b("D2", .antagonist, .primary), b("H1", .antagonist, .significant), b("α1", .antagonist, .significant)],
    )

    private static let atypicalAP = moa(
        "Serotonin-Dopamine Antagonist (Second-Generation Antipsychotic)",
        "Antagonizes both dopamine D2 and serotonin 5-HT2A receptors. The 5-HT2A antagonism modulates dopamine release in the nigrostriatal pathway, reducing extrapyramidal side effects compared to first-generation agents. May improve negative symptoms and cognitive function. Individual agents differ in their affinity for additional receptors including H1, α1, and muscarinic receptors.",
        [b("D2", .antagonist, .primary), b("5-HT2A", .antagonist, .primary)],
    )

    private static let benzo = moa(
        "GABA-A Positive Allosteric Modulator (Benzodiazepine)",
        "Binds to the benzodiazepine site at the interface of α and γ subunits on GABA-A receptors, acting as a positive allosteric modulator. Enhances the effect of GABA by increasing the frequency of chloride channel opening, leading to neuronal hyperpolarization and reduced excitability. Produces anxiolytic, sedative, hypnotic, anticonvulsant, and muscle relaxant effects.",
        [b("GABA-A", .positiveAllostericModulator, .primary)],
    )

    private static let zDrug = moa(
        "GABA-A Receptor Agonist (α1-Selective)",
        "Binds to the benzodiazepine site on GABA-A receptors with preferential selectivity for the α1 subunit, which is predominantly associated with sedation and hypnosis. This selectivity produces hypnotic effects with less anxiolytic, anticonvulsant, and muscle relaxant activity compared to benzodiazepines, though selectivity diminishes at higher doses.",
        [b("GABA-A (α1)", .agonist, .primary)],
    )

    private static let barb = moa(
        "GABA-A Positive Allosteric Modulator (Barbiturate)",
        "Binds to a distinct site on the GABA-A receptor, acting as a positive allosteric modulator that increases the duration of chloride channel opening (unlike benzodiazepines which increase frequency). At higher concentrations, can directly activate GABA-A receptors even without GABA, accounting for their greater overdose lethality. Also inhibits AMPA/kainate glutamate receptors.",
        [b("GABA-A", .positiveAllostericModulator, .primary), b("AMPA/kainate", .antagonist, .significant)],
    )

    private static let opioidFull = moa(
        "μ-Opioid Receptor (MOR) Full Agonist",
        "Acts as a full agonist at μ-opioid receptors (MOR), G-protein coupled receptors distributed throughout the central and peripheral nervous system. MOR activation inhibits adenylyl cyclase, opens inwardly rectifying potassium channels, and closes voltage-gated calcium channels, reducing neuronal excitability and neurotransmitter release. Produces analgesia, euphoria, respiratory depression, and decreased gastrointestinal motility.",
        [b("μ-opioid (MOR)", .agonist, .primary)],
    )

    private static let amphetamine = moa(
        "Monoamine Releasing Agent",
        "Enters monoaminergic nerve terminals via dopamine (DAT), norepinephrine (NET), and serotonin (SERT) transporters, then reverses their function to release stored neurotransmitters into the synaptic cleft. Also activates trace amine-associated receptor 1 (TAAR1), inhibits vesicular monoamine transporter 2 (VMAT2), and weakly inhibits monoamine oxidase. The net effect is a substantial increase in synaptic dopamine, norepinephrine, and to a lesser extent serotonin.",
        [
            b("DAT", .releasingAgent, .primary),
            b("NET", .releasingAgent, .primary),
            b("TAAR1", .agonist, .significant),
            b("VMAT2", .modulator, .significant),
        ],
    )

    /// Methamphetamine — the amphetamine releaser set plus SERT, which it touches
    /// measurably (it is more serotonergic than amphetamine). The DB's measured SERT
    /// potency sets the displayed dot tier; the editorial tier here is just a fallback.
    /// Summary/description text comes from the curated `mechanisms.json` entry at runtime.
    private static let methamphetamine = moa(
        "Monoamine Releasing Agent",
        "Enters dopamine (DAT), norepinephrine (NET), and serotonin (SERT) nerve terminals and reverses their transporters, releasing all three monoamines. Also agonizes TAAR1 and acts at VMAT2 to redistribute vesicular monoamines into the cytosol.",
        [
            b("DAT", .releasingAgent, .primary),
            b("NET", .releasingAgent, .primary),
            b("SERT", .releasingAgent, .weak),
            b("TAAR1", .agonist, .significant),
            b("VMAT2", .modulator, .significant),
        ],
    )

    /// Substrate-type (releaser) cathinones — mephedrone, methylone, the MMC
    /// series, etc. Enter the terminal via the transporter and reverse it.
    private static let cathinoneReleaser = moa(
        "Non-selective Monoamine Releaser (Substituted Cathinone)",
        "A β-keto amphetamine that enters dopamine, norepinephrine, and serotonin nerve terminals through their transporters (DAT/NET/SERT) and reverses them, releasing all three monoamines. The dopamine-to-serotonin release ratio sets the character — balanced (e.g. mephedrone) is entactogenic-stimulant, dopamine-dominant is more purely stimulating.",
        [b("DAT", .releasingAgent, .primary), b("NET", .releasingAgent, .primary), b("SERT", .releasingAgent, .significant)],
    )

    /// Pyrovalerone (pyrrolidinophenone) cathinones — MDPV, α-PVP, α-PHP, etc.
    /// Potent DAT/NET reuptake inhibitors with little/no monoamine release.
    private static let cathinonePyrovalerone = moa(
        "Dopamine–Norepinephrine Reuptake Inhibitor (Pyrovalerone Cathinone)",
        "A pyrrolidine cathinone that potently blocks the dopamine and norepinephrine transporters (DAT/NET) without releasing monoamines and with little serotonergic activity. The strong, long-lasting rise in dopamine and norepinephrine is intensely stimulating and carries a high risk of compulsive redosing.",
        [b("DAT", .reuptakeInhibitor, .primary), b("NET", .reuptakeInhibitor, .primary)],
    )

    private static let classicalPsychedelic = moa(
        "Serotonin 5-HT2A Receptor Agonist (Classical Psychedelic)",
        "Primarily acts as an agonist or partial agonist at serotonin 5-HT2A receptors, particularly on layer V pyramidal neurons in the prefrontal cortex. 5-HT2A activation increases glutamate release and enhances cortical excitability, leading to altered perception, cognition, and consciousness. Most classical psychedelics also interact with 5-HT2C, 5-HT1A, and other serotonin receptor subtypes.",
        [b("5-HT2A", .agonist, .primary), b("5-HT2C", .agonist, .significant), b("5-HT1A", .agonist, .weak)],
    )

    private static let nmdaDissociative = moa(
        "NMDA Receptor Antagonist (Dissociative)",
        "Blocks N-methyl-D-aspartate (NMDA) glutamate receptors, typically by binding within the ion channel pore as a non-competitive antagonist. NMDA receptor blockade reduces excitatory glutamatergic neurotransmission, producing dissociative anesthesia, analgesia, and altered states of consciousness characterized by feelings of detachment from body and environment.",
        [b("NMDA", .antagonist, .primary)],
    )

    private static let cannabinoidAgonist = moa(
        "Cannabinoid CB1/CB2 Receptor Agonist",
        "Acts as an agonist at cannabinoid CB1 receptors in the central nervous system and CB2 receptors in immune tissues. CB1 activation inhibits adenylyl cyclase and modulates ion channels via Gi/Go proteins, reducing neurotransmitter release (particularly GABA and glutamate) in brain regions involved in reward, memory, coordination, and pain perception.",
        [b("CB1", .agonist, .primary), b("CB2", .agonist, .significant)],
    )

    private static let gabapentinoid = moa(
        "Voltage-Gated Calcium Channel α2δ Subunit Ligand",
        "Binds to the α2δ-1 subunit of voltage-gated calcium channels (VGCCs), reducing calcium influx at presynaptic nerve terminals. This decreases the release of excitatory neurotransmitters including glutamate, norepinephrine, substance P, and calcitonin gene-related peptide. Despite the name, gabapentinoids do not interact with GABA receptors or GABA metabolism.",
        [b("α2δ-1 VGCC", .channelBlocker, .primary)],
    )

    private static let betaBlocker = moa(
        "β-Adrenergic Receptor Antagonist",
        "Competitively blocks β-adrenergic receptors, preventing the effects of catecholamines. β1-selective agents primarily reduce heart rate and cardiac contractility. Non-selective agents also block β2 receptors in bronchial smooth muscle and peripheral vasculature. Used for hypertension, arrhythmias, heart failure, and performance anxiety.",
        [b("β1-adrenergic", .antagonist, .primary), b("β2-adrenergic", .antagonist, .significant)],
    )

    private static let aceInhibitor = moa(
        "Angiotensin-Converting Enzyme (ACE) Inhibitor",
        "Inhibits angiotensin-converting enzyme (ACE), preventing the conversion of angiotensin I to angiotensin II, a potent vasoconstrictor. Also reduces degradation of bradykinin, a vasodilator. The net effect is decreased peripheral vascular resistance, reduced aldosterone secretion, and lower blood pressure. ACE inhibitors also reduce cardiac remodeling after myocardial infarction.",
        [b("ACE", .enzymeInhibitor, .primary)],
    )

    private static let arb = moa(
        "Angiotensin II Receptor Blocker (ARB)",
        "Selectively blocks angiotensin II type 1 (AT1) receptors, preventing the vasoconstrictive, aldosterone-secreting, and growth-promoting effects of angiotensin II. Unlike ACE inhibitors, ARBs do not affect bradykinin metabolism and therefore do not cause cough. Provides similar hemodynamic effects to ACE inhibitors through a different mechanism.",
        [b("AT1", .antagonist, .primary)],
    )

    private static let nsaid = moa(
        "Cyclooxygenase (COX) Inhibitor (NSAID)",
        "Reversibly inhibits cyclooxygenase enzymes COX-1 and COX-2, reducing the synthesis of prostaglandins from arachidonic acid. COX-2 inhibition mediates anti-inflammatory and analgesic effects, while COX-1 inhibition reduces gastric mucosal protection. Central prostaglandin inhibition contributes to antipyretic effects.",
        [b("COX-1", .enzymeInhibitor, .primary), b("COX-2", .enzymeInhibitor, .primary)],
    )

    private static let antihistamine1 = moa(
        "Histamine H1 Receptor Inverse Agonist (First-Generation)",
        "Acts as an inverse agonist at histamine H1 receptors, reducing constitutive receptor activity and blocking histamine-mediated signaling. Crosses the blood-brain barrier readily, producing sedation, anxiolysis, and antiemetic activity through central H1 blockade. Most also have significant anticholinergic (muscarinic antagonist) activity.",
        [b("H1", .inverseAgonist, .primary), b("Muscarinic", .antagonist, .significant)],
    )

    private static let antihistamine2 = moa(
        "Histamine H1 Receptor Inverse Agonist (Second-Generation)",
        "Selectively acts as an inverse agonist at peripheral histamine H1 receptors with minimal blood-brain barrier penetration. Provides antiallergic and antipruritic effects without significant sedation or cognitive impairment. Reduced CNS penetration is due to P-glycoprotein efflux at the blood-brain barrier.",
        [b("H1 (peripheral)", .inverseAgonist, .primary)],
    )

    private static let ppi = moa(
        "Proton Pump Inhibitor (PPI)",
        "Irreversibly inhibits the hydrogen-potassium ATPase (H⁺/K⁺ ATPase, the proton pump) on the luminal surface of gastric parietal cells. This blocks the final step of acid secretion regardless of the stimulus, producing a profound and long-lasting reduction in gastric acid production. Requires activation in the acidic environment of the parietal cell canaliculus.",
        [b("H⁺/K⁺ ATPase", .enzymeInhibitor, .primary)],
    )

    private static let racetam = moa(
        "Racetam Nootropic (Glutamatergic/Cholinergic Modulator)",
        "Exact mechanism not fully established. Modulates AMPA-type glutamate receptors (positive allosteric modulation), enhancing glutamatergic neurotransmission and synaptic plasticity. May also increase acetylcholine turnover and improve cerebral blood flow. Individual racetams vary in their receptor selectivity and additional mechanisms.",
        [b("AMPA", .positiveAllostericModulator, .primary), b("Acetylcholine", .modulator, .significant)],
    )

    private static let statin = moa(
        "HMG-CoA Reductase Inhibitor (Statin)",
        "Competitively inhibits 3-hydroxy-3-methylglutaryl-coenzyme A (HMG-CoA) reductase, the rate-limiting enzyme in hepatic cholesterol synthesis. Reduced intracellular cholesterol upregulates LDL receptor expression on hepatocytes, increasing LDL clearance from the blood. Also produces pleiotropic effects including improved endothelial function and anti-inflammatory activity.",
        [b("HMG-CoA reductase", .enzymeInhibitor, .primary)],
    )

    private static let triptan = moa(
        "Serotonin 5-HT1B/1D Receptor Agonist (Triptan)",
        "Selectively activates serotonin 5-HT1B receptors on cranial blood vessels (causing vasoconstriction of dilated meningeal arteries) and 5-HT1D receptors on trigeminal nerve terminals (inhibiting release of vasoactive neuropeptides including CGRP and substance P). This dual action reverses the pathophysiology of migraine: vasodilation and neurogenic inflammation.",
        [b("5-HT1B", .agonist, .primary), b("5-HT1D", .agonist, .primary)],
    )

    private static let corticosteroid = moa(
        "Glucocorticoid Receptor Agonist",
        "Binds to intracellular glucocorticoid receptors, which translocate to the nucleus and modulate gene transcription. Upregulates anti-inflammatory proteins (lipocortins, IL-10) and downregulates pro-inflammatory mediators (cytokines, prostaglandins, leukotrienes). Also suppresses immune cell activation and migration. Metabolic effects include increased gluconeogenesis and altered fat distribution.",
        [b("Glucocorticoid receptor", .agonist, .primary)],
    )

    private static let fluoroquinolone = moa(
        "Bacterial DNA Gyrase and Topoisomerase IV Inhibitor",
        "Inhibits bacterial DNA gyrase (topoisomerase II) and topoisomerase IV, enzymes essential for DNA replication, transcription, repair, and recombination. DNA gyrase inhibition prevents supercoil relaxation; topoisomerase IV inhibition prevents daughter chromosome separation. These actions are bactericidal. Human topoisomerases are structurally different, providing selectivity.",
        [b("DNA gyrase", .enzymeInhibitor, .primary), b("Topoisomerase IV", .enzymeInhibitor, .primary)],
    )

    private static let ccb = moa(
        "Calcium Channel Blocker (Dihydropyridine)",
        "Blocks L-type voltage-gated calcium channels in vascular smooth muscle, reducing calcium influx and causing vasodilation. Primarily acts on arterial smooth muscle with minimal cardiac effects at therapeutic doses. Reduces peripheral vascular resistance and blood pressure.",
        [b("L-type Ca²⁺ channels", .channelBlocker, .primary)],
    )

    // MARK: - Shared Unique Mechanisms

    private static let ketamineMOA = moa(
        "Non-Competitive NMDA Receptor Antagonist with Rapid Antidepressant Properties",
        "Acts as a non-competitive antagonist at the NMDA glutamate receptor by binding within the ion channel pore (use-dependent blockade). Produces dissociative anesthesia at higher doses and rapid antidepressant effects at sub-anesthetic doses. The antidepressant mechanism involves enhanced AMPA receptor signaling, increased brain-derived neurotrophic factor (BDNF) release, and activation of the mTOR signaling pathway, promoting rapid synaptic plasticity.",
        [b("NMDA", .antagonist, .primary), b("AMPA", .modulator, .significant), b("mTOR", .modulator, .significant)],
    )

    // MARK: - Category Fallbacks

    private static let categoryData: [SubstanceCategory: MechanismOfAction] = [
        .stimulant: moa(
            "Central Nervous System Stimulant",
            "Increases central nervous system activity by enhancing monoamine neurotransmission, typically through increased release or reduced reuptake of dopamine and/or norepinephrine. The specific mechanism varies by substance class (releasing agents, reuptake inhibitors, or receptor agonists). Effects include increased alertness, attention, and energy.",
            [b("Dopamine", .modulator, .primary), b("Norepinephrine", .modulator, .primary)],
        ),
        .psychedelic: classicalPsychedelic,
        .dissociative: nmdaDissociative,
        .opioid: opioidFull,
        .benzodiazepine: benzo,
        .gabapentinoid: gabapentinoid,
        .empathogen: moa(
            "Monoamine Releasing Agent (Serotonin-Predominant)",
            "Increases synaptic serotonin, dopamine, and norepinephrine, with a predominant serotonergic component that distinguishes empathogens from classical stimulants. Many also stimulate the release of oxytocin from the hypothalamus, contributing to prosocial effects, emotional openness, and feelings of empathy and connectedness.",
            [
                b("SERT", .releasingAgent, .primary),
                b("DAT", .releasingAgent, .significant),
                b("NET", .releasingAgent, .significant),
                b("Oxytocin", .modulator, .significant),
            ],
        ),
        .cannabinoid: cannabinoidAgonist,
        .nootropic: moa(
            "Cognitive-Enhancing Agent (Nootropic)",
            "Nootropic agents enhance cognitive function through diverse mechanisms which may include modulation of acetylcholine, glutamate, or monoamine neurotransmitter systems; improvement of cerebral blood flow; neuroprotection through antioxidant activity; or modulation of neuroplasticity signaling cascades. Mechanisms vary widely and are substance-specific.",
            [b("Various", .modulator, .primary)],
        ),
        .depressant: moa(
            "Central Nervous System Depressant",
            "Reduces central nervous system excitability, typically through enhancement of inhibitory GABAergic neurotransmission and/or reduction of excitatory glutamatergic neurotransmission. Produces sedation, anxiolysis, and muscle relaxation in a dose-dependent manner.",
            [b("GABA system", .modulator, .primary), b("Glutamate system", .antagonist, .primary)],
        ),
        .orexinAntagonist: moa(
            "Dual Orexin Receptor Antagonist (DORA)",
            "Competitively blocks the orexin (hypocretin) receptors OX1R and OX2R, the targets of the wake-promoting neuropeptides orexin-A and orexin-B released from the lateral hypothalamus. Rather than broadly sedating the brain like a GABAergic hypnotic, it withdraws a specific \"stay awake\" drive that stabilizes arousal — permitting the natural transition into sleep with largely preserved sleep architecture and arousability. Because it does not enhance GABA or depress brainstem respiratory centers, it lacks the respiratory-depression synergy and dependence liability characteristic of benzodiazepines, Z-drugs, and other GABAergic sedatives.",
            [b("OX1R", .antagonist, .primary), b("OX2R", .antagonist, .primary)],
        ),
        .antidepressant: moa(
            "Antidepressant (Monoamine Modulator)",
            "Modulates monoamine neurotransmitter systems (serotonin, norepinephrine, and/or dopamine) through various mechanisms including reuptake inhibition, enzyme inhibition, or receptor modulation. The specific mechanism depends on the drug class. Therapeutic effects typically develop over 2–6 weeks.",
            [b("Serotonin", .modulator, .primary), b("Norepinephrine", .modulator, .significant), b("Dopamine", .modulator, .weak)],
        ),
        .antipsychotic: atypicalAP,
        .analgesic: moa(
            "Analgesic Agent",
            "Reduces pain perception through mechanisms that may include inhibition of prostaglandin synthesis, activation of endogenous opioid pathways, modulation of descending pain inhibitory circuits, or blockade of peripheral nociceptor sensitization. The specific mechanism depends on the drug class.",
            [b("Pain pathways", .modulator, .primary)],
        ),
        .antihistamine: antihistamine1,
        .cardiovascular: moa(
            "Cardiovascular Agent",
            "Modulates cardiovascular function through mechanisms including adrenergic receptor blockade, calcium channel inhibition, renin-angiotensin system modulation, or direct vasodilation. The specific mechanism depends on the drug class.",
            [b("Cardiovascular system", .modulator, .primary)],
        ),
        .antimicrobial: moa(
            "Antimicrobial Agent",
            "Eliminates or inhibits the growth of microorganisms by targeting microbial-specific processes such as cell wall synthesis, protein synthesis, nucleic acid replication, metabolic pathways, or cell membrane integrity.",
            [b("Microbial targets", .modulator, .primary)],
        ),
        .gastrointestinal: moa(
            "Gastrointestinal Agent",
            "Modulates digestive function through mechanisms such as acid secretion inhibition, motility modulation, mucosal protection, or neurotransmitter receptor interactions in the enteric nervous system.",
            [b("GI system", .modulator, .primary)],
        ),
        .respiratory: moa(
            "Respiratory Agent",
            "Modulates airway function through mechanisms including bronchodilation via β2-adrenergic agonism or anticholinergic blockade, anti-inflammatory effects from corticosteroids, mast cell stabilization, or leukotriene receptor antagonism.",
            [b("Airway smooth muscle", .modulator, .primary), b("Inflammatory mediators", .modulator, .significant)],
        ),
        .endocrine: moa(
            "Endocrine Agent",
            "Modulates hormonal signaling through receptor agonism or antagonism, enzyme inhibition affecting hormone synthesis or metabolism, or direct hormone replacement. Interacts with the hypothalamic-pituitary-endocrine axes.",
            [b("Hormonal receptors", .modulator, .primary)],
        ),
        .immunological: moa(
            "Immunomodulatory Agent",
            "Modulates immune system function through mechanisms such as inhibition of inflammatory cytokine production, suppression of T-cell or B-cell activation, complement system modulation, or targeted inhibition of specific immune pathways.",
            [b("Immune system", .modulator, .primary)],
        ),
        .supplement: moa(
            "Dietary Supplement",
            "Supports physiological functions through various mechanisms including enzyme cofactor activity, antioxidant effects, neurotransmitter precursor supply, hormonal modulation, or direct receptor interactions. Mechanisms vary widely and are substance-specific.",
            [b("Various", .modulator, .primary)],
        ),
        .other: moa(
            "Pharmacological Agent",
            "This substance's mechanism of action may involve multiple pharmacological targets or may not be fully characterized. Consult specific pharmacological references for detailed mechanistic information.",
            [b("Various", .modulator, .primary)],
        ),
    ]

    // MARK: - Substance Data

    // Built programmatically to avoid slow large-dictionary-literal initialization in debug builds.
    // swiftlint:disable function_body_length
    private static let substanceData: [String: MechanismOfAction] = {
        var d = [String: MechanismOfAction](minimumCapacity: 300)

        // ── SSRIs ──────────────────────────────────────────────────
        for n in ["fluoxetine", "sertraline", "paroxetine", "citalopram", "escitalopram", "fluvoxamine"] {
            d[n] = ssri
        }

        // ── SNRIs ──────────────────────────────────────────────────
        for n in ["venlafaxine", "desvenlafaxine", "duloxetine", "milnacipran", "levomilnacipran"] {
            d[n] = snri
        }

        // ── TCAs ───────────────────────────────────────────────────
        for n in ["amitriptyline", "nortriptyline", "imipramine", "desipramine", "clomipramine", "doxepin", "trimipramine", "protriptyline", "amoxapine", "maprotiline"] {
            d[n] = tca
        }

        // ── MAOIs ──────────────────────────────────────────────────
        for n in ["phenelzine", "tranylcypromine", "isocarboxazid"] {
            d[n] = maoi
        }
        d["moclobemide"] = rima
        d["selegiline"] = maobSelective

        // ── Typical Antipsychotics ─────────────────────────────────
        for n in ["haloperidol", "chlorpromazine", "fluphenazine", "perphenazine", "thioridazine", "trifluoperazine", "loxapine", "pimozide", "thiothixene", "droperidol"] {
            d[n] = typicalAP
        }

        // ── Atypical Antipsychotics ────────────────────────────────
        for n in ["risperidone", "olanzapine", "quetiapine", "ziprasidone", "paliperidone", "lurasidone", "iloperidone", "asenapine"] {
            d[n] = atypicalAP
        }

        // ── Benzodiazepines ────────────────────────────────────────
        for n in ["diazepam", "alprazolam", "clonazepam", "lorazepam", "midazolam", "triazolam", "temazepam", "chlordiazepoxide", "oxazepam", "flurazepam", "nitrazepam", "estazolam", "quazepam", "clorazepate", "flunitrazepam", "phenazepam", "bromazepam", "etizolam", "flualprazolam", "clonazolam", "flubromazolam", "bromazolam"] {
            d[n] = benzo
        }

        // ── Z-Drugs ───────────────────────────────────────────────
        for n in ["zolpidem", "zopiclone", "zaleplon", "eszopiclone"] {
            d[n] = zDrug
        }

        // ── Barbiturates ──────────────────────────────────────────
        for n in ["phenobarbital", "pentobarbital", "secobarbital", "amobarbital", "thiopental"] {
            d[n] = barb
        }

        // ── Opioid Agonists ───────────────────────────────────────
        for n in ["morphine", "heroin"] {
            d[n] = opioidFull
        }
        for n in ["diacetylmorphine", "diamorphine"] {
            d[n] = opioidFull
        }
        for n in ["oxycodone", "hydrocodone"] {
            d[n] = opioidFull
        }
        for n in ["oxymorphone", "hydromorphone"] {
            d[n] = opioidFull
        }
        for n in ["fentanyl", "sufentanil"] {
            d[n] = opioidFull
        }
        for n in ["meperidine", "pethidine"] {
            d[n] = opioidFull
        }

        // ── Stimulants ────────────────────────────────────────────
        for n in ["amphetamine", "dextroamphetamine"] {
            d[n] = amphetamine
        }
        d["methamphetamine"] = methamphetamine

        // ── Substituted Cathinones ────────────────────────────────
        // Releasers (substrate-type: DA/NE/5-HT release via transporter reversal)
        for n in [
            "mephedrone",
            "4-mmc",
            "3-mmc",
            "2-mmc",
            "methcathinone",
            "cathinone",
            "methylone",
            "ethylone",
            "butylone",
            "eutylone",
            "mexedrone",
            "4-mec",
            "4-cmc",
            "3-cmc",
            "3-chloromethcathinone",
            "4-cec",
            "n-ethylpentylone",
        ] {
            d[n] = cathinoneReleaser
        }
        // Pyrovalerones (DAT/NET reuptake inhibitors, no monoamine release)
        for n in [
            "mdpv",
            "α-pvp",
            "a-pvp",
            "α-php",
            "a-php",
            "alpha-pyrrolidinohexiophenone",
            "mdphp",
            "md-php",
            "naphyrone",
            "pyrovalerone",
        ] {
            d[n] = cathinonePyrovalerone
        }

        // ── Classical Psychedelics ─────────────────────────────────
        for n in ["lsd", "lsd-25"] {
            d[n] = classicalPsychedelic
        }
        for n in ["1p-lsd", "1cp-lsd"] {
            d[n] = classicalPsychedelic
        }
        for n in ["ald-52", "eth-lad"] {
            d[n] = classicalPsychedelic
        }
        d["al-lad"] = classicalPsychedelic
        d["psilocin"] = classicalPsychedelic
        for n in ["4-aco-dmt", "4-ho-met"] {
            d[n] = classicalPsychedelic
        }
        d["4-ho-mipt"] = classicalPsychedelic
        for n in ["mescaline", "dpt"] {
            d[n] = classicalPsychedelic
        }
        for n in ["2c-b", "2c-e"] {
            d[n] = classicalPsychedelic
        }
        for n in ["2c-i", "2c-c"] {
            d[n] = classicalPsychedelic
        }
        d["2c-t-7"] = classicalPsychedelic
        for n in ["dob", "doc"] {
            d[n] = classicalPsychedelic
        }
        for n in ["doi", "dom"] {
            d[n] = classicalPsychedelic
        }

        // ── Dissociatives ──────────────────────────────────────────
        for n in ["ketamine", "esketamine"] {
            d[n] = ketamineMOA
        }
        for n in ["3-meo-pcp", "3-ho-pcp"] {
            d[n] = nmdaDissociative
        }
        for n in ["mxe", "methoxetamine"] {
            d[n] = nmdaDissociative
        }
        for n in ["diphenidine", "methoxphenidine"] {
            d[n] = nmdaDissociative
        }

        // ── Cannabinoids ──────────────────────────────────────────
        for n in ["nabilone", "dronabinol"] {
            d[n] = cannabinoidAgonist
        }
        d["jwh-018"] = cannabinoidAgonist

        // ── Gabapentinoids ─────────────────────────────────────────
        for n in ["gabapentin", "pregabalin"] {
            d[n] = gabapentinoid
        }

        // ── Analgesics / NSAIDs ───────────────────────────────────
        for n in ["ibuprofen", "naproxen", "diclofenac"] {
            d[n] = nsaid
        }
        for n in ["indomethacin", "piroxicam", "meloxicam"] {
            d[n] = nsaid
        }
        d["ketorolac"] = nsaid

        // ── Antihistamines ────────────────────────────────────────
        for n in ["diphenhydramine", "hydroxyzine"] {
            d[n] = antihistamine1
        }
        for n in ["doxylamine", "chlorpheniramine"] {
            d[n] = antihistamine1
        }
        for n in ["promethazine", "cyproheptadine"] {
            d[n] = antihistamine1
        }
        for n in ["brompheniramine", "clemastine"] {
            d[n] = antihistamine1
        }
        for n in ["meclizine", "dimenhydrinate"] {
            d[n] = antihistamine1
        }
        for n in ["cetirizine", "loratadine"] {
            d[n] = antihistamine2
        }
        for n in ["fexofenadine", "levocetirizine"] {
            d[n] = antihistamine2
        }
        d["desloratadine"] = antihistamine2

        // ── Beta-Blockers ─────────────────────────────────────────
        for n in ["propranolol", "metoprolol"] {
            d[n] = betaBlocker
        }
        for n in ["atenolol", "bisoprolol"] {
            d[n] = betaBlocker
        }
        d["nadolol"] = betaBlocker
        for n in ["nebivolol", "labetalol"] {
            d[n] = betaBlocker
        }

        // ── ACE Inhibitors ────────────────────────────────────────
        for n in ["lisinopril", "enalapril"] {
            d[n] = aceInhibitor
        }
        d["ramipril"] = aceInhibitor
        d["benazepril"] = aceInhibitor
        d["quinapril"] = aceInhibitor

        // ── ARBs ──────────────────────────────────────────────────
        for n in ["losartan", "valsartan", "irbesartan"] {
            d[n] = arb
        }
        d["olmesartan"] = arb

        // ── Calcium Channel Blockers ──────────────────────────────
        for n in ["amlodipine", "nifedipine", "felodipine"] {
            d[n] = ccb
        }

        // ── PPIs ──────────────────────────────────────────────────
        for n in ["omeprazole", "esomeprazole", "lansoprazole"] {
            d[n] = ppi
        }
        for n in ["pantoprazole", "dexlansoprazole"] {
            d[n] = ppi
        }

        // ── Statins ───────────────────────────────────────────────
        for n in ["atorvastatin", "rosuvastatin"] {
            d[n] = statin
        }
        for n in ["simvastatin", "pravastatin"] {
            d[n] = statin
        }
        for n in ["lovastatin", "fluvastatin"] {
            d[n] = statin
        }

        // ── Triptans ──────────────────────────────────────────────
        for n in ["sumatriptan", "rizatriptan"] {
            d[n] = triptan
        }
        for n in ["zolmitriptan", "eletriptan"] {
            d[n] = triptan
        }
        for n in ["naratriptan", "almotriptan"] {
            d[n] = triptan
        }

        // ── Corticosteroids ───────────────────────────────────────
        for n in ["prednisone", "prednisolone"] {
            d[n] = corticosteroid
        }
        for n in ["dexamethasone", "hydrocortisone"] {
            d[n] = corticosteroid
        }
        for n in ["methylprednisolone", "budesonide"] {
            d[n] = corticosteroid
        }

        // ── Antibiotics ───────────────────────────────────────────
        for n in ["ciprofloxacin", "levofloxacin"] {
            d[n] = fluoroquinolone
        }

        // ── Supplements & Nootropics ──────────────────────────────
        for n in ["piracetam", "aniracetam"] {
            d[n] = racetam
        }
        for n in ["oxiracetam", "pramiracetam"] {
            d[n] = racetam
        }
        for n in ["phenylpiracetam", "carphedon", "coluracetam"] {
            d[n] = racetam
        }
        d["fasoracetam"] = racetam

        return d
    }()
    // swiftlint:enable function_body_length
}
