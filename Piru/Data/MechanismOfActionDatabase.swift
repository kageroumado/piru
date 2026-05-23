import Foundation

enum MechanismOfActionDatabase {

    // MARK: - Lookup

    static func mechanism(for name: String) -> MechanismOfAction? {
        substanceData[name.lowercased()]
    }

    static func categoryFallback(for category: SubstanceCategory) -> MechanismOfAction? {
        categoryData[category]
    }

    // MARK: - Helpers

    private static func moa(
        _ summary: LocalizedStringResource, _ desc: LocalizedStringResource, _ bindings: [ReceptorBinding], _ refs: [String]
    ) -> MechanismOfAction {
        MechanismOfAction(
            summary: String(localized: summary),
            description: String(localized: desc),
            bindings: bindings,
            references: refs
        )
    }

    private static func b(_ target: String, _ action: BindingAction, _ affinity: BindingAffinity) -> ReceptorBinding {
        ReceptorBinding(target: target, action: action, affinity: affinity)
    }

    private static let gg = "Goodman & Gilman's"
    private static let stahl = "Stahl's Essential Psychopharmacology"
    private static let katzung = "Katzung Basic & Clinical Pharmacology"
    private static let db = "DrugBank"
    private static let pw = "PsychonautWiki"

    // MARK: - Shared Class Mechanisms

    private static let ssri = moa(
        "Selective Serotonin Reuptake Inhibitor (SSRI)",
        "Selectively inhibits the serotonin transporter (SERT), blocking the reuptake of serotonin (5-HT) from the synaptic cleft into the presynaptic neuron. This increases serotonin availability at postsynaptic receptors. Therapeutic effects typically require 2–4 weeks as presynaptic 5-HT1A autoreceptors desensitize, allowing sustained serotonergic neurotransmission.",
        [b("SERT", .reuptakeInhibitor, .primary)],
        [stahl, gg])

    private static let snri = moa(
        "Serotonin-Norepinephrine Reuptake Inhibitor (SNRI)",
        "Inhibits both the serotonin transporter (SERT) and the norepinephrine transporter (NET), blocking reuptake of both monoamines from the synaptic cleft. At lower doses, serotonin reuptake inhibition predominates; norepinephrine reuptake inhibition becomes more significant at higher doses. This dual mechanism provides antidepressant and analgesic effects.",
        [b("SERT", .reuptakeInhibitor, .primary), b("NET", .reuptakeInhibitor, .primary)],
        [stahl, gg])

    private static let tca = moa(
        "Tricyclic Antidepressant (TCA)",
        "Inhibits the reuptake of serotonin and norepinephrine by blocking SERT and NET. Unlike SSRIs and SNRIs, TCAs also significantly antagonize histamine H1, muscarinic M1, and α1-adrenergic receptors, which accounts for their sedative, anticholinergic, and orthostatic hypotension side effects. The ratio of serotonin to norepinephrine reuptake inhibition varies between individual TCAs.",
        [b("SERT", .reuptakeInhibitor, .primary), b("NET", .reuptakeInhibitor, .primary),
         b("H1", .antagonist, .significant), b("M1", .antagonist, .significant), b("α1", .antagonist, .significant)],
        [stahl, gg])

    private static let maoi = moa(
        "Irreversible Monoamine Oxidase Inhibitor (MAOI)",
        "Irreversibly inhibits monoamine oxidase enzymes (MAO-A and MAO-B), which are responsible for the oxidative deamination of monoamine neurotransmitters. MAO-A primarily metabolizes serotonin, norepinephrine, and dopamine; MAO-B primarily metabolizes phenylethylamine and dopamine. Inhibition increases synaptic levels of all monoamines. Requires dietary tyramine restriction due to risk of hypertensive crisis.",
        [b("MAO-A", .enzymeInhibitor, .primary), b("MAO-B", .enzymeInhibitor, .primary)],
        [stahl, gg])

    private static let rima = moa(
        "Reversible Inhibitor of Monoamine Oxidase A (RIMA)",
        "Selectively and reversibly inhibits MAO-A, increasing synaptic serotonin and norepinephrine. Unlike irreversible MAOIs, the reversible binding allows dietary tyramine to compete for the enzyme, significantly reducing the risk of hypertensive crisis and eliminating the need for strict dietary restrictions.",
        [b("MAO-A", .enzymeInhibitor, .primary)],
        [stahl, gg])

    private static let maobSelective = moa(
        "Selective MAO-B Inhibitor",
        "Selectively inhibits monoamine oxidase B (MAO-B), which preferentially metabolizes dopamine and phenylethylamine in the brain. At selective doses, increases dopamine availability without significantly affecting serotonin or norepinephrine metabolism, and without requiring dietary tyramine restriction. At higher doses, selectivity is lost and MAO-A is also inhibited.",
        [b("MAO-B", .enzymeInhibitor, .primary)],
        [stahl, gg])

    private static let typicalAP = moa(
        "Dopamine D2 Receptor Antagonist (First-Generation Antipsychotic)",
        "Blocks dopamine D2 receptors in the mesolimbic pathway, reducing dopaminergic neurotransmission associated with positive psychotic symptoms. Also blocks D2 receptors in the nigrostriatal pathway (causing extrapyramidal symptoms), tuberoinfundibular pathway (causing hyperprolactinemia), and mesocortical pathway. Most also antagonize histamine H1, muscarinic, and α1-adrenergic receptors to varying degrees.",
        [b("D2", .antagonist, .primary), b("H1", .antagonist, .significant), b("α1", .antagonist, .significant)],
        [stahl, gg])

    private static let atypicalAP = moa(
        "Serotonin-Dopamine Antagonist (Second-Generation Antipsychotic)",
        "Antagonizes both dopamine D2 and serotonin 5-HT2A receptors. The 5-HT2A antagonism modulates dopamine release in the nigrostriatal pathway, reducing extrapyramidal side effects compared to first-generation agents. May improve negative symptoms and cognitive function. Individual agents differ in their affinity for additional receptors including H1, α1, and muscarinic receptors.",
        [b("D2", .antagonist, .primary), b("5-HT2A", .antagonist, .primary)],
        [stahl, gg])

    private static let benzo = moa(
        "GABA-A Positive Allosteric Modulator (Benzodiazepine)",
        "Binds to the benzodiazepine site at the interface of α and γ subunits on GABA-A receptors, acting as a positive allosteric modulator. Enhances the effect of GABA by increasing the frequency of chloride channel opening, leading to neuronal hyperpolarization and reduced excitability. Produces anxiolytic, sedative, hypnotic, anticonvulsant, and muscle relaxant effects.",
        [b("GABA-A", .positiveAllostericModulator, .primary)],
        [gg, stahl])

    private static let zDrug = moa(
        "GABA-A Receptor Agonist (α1-Selective)",
        "Binds to the benzodiazepine site on GABA-A receptors with preferential selectivity for the α1 subunit, which is predominantly associated with sedation and hypnosis. This selectivity produces hypnotic effects with less anxiolytic, anticonvulsant, and muscle relaxant activity compared to benzodiazepines, though selectivity diminishes at higher doses.",
        [b("GABA-A (α1)", .agonist, .primary)],
        [gg, stahl])

    private static let barb = moa(
        "GABA-A Positive Allosteric Modulator (Barbiturate)",
        "Binds to a distinct site on the GABA-A receptor, acting as a positive allosteric modulator that increases the duration of chloride channel opening (unlike benzodiazepines which increase frequency). At higher concentrations, can directly activate GABA-A receptors even without GABA, accounting for their greater overdose lethality. Also inhibits AMPA/kainate glutamate receptors.",
        [b("GABA-A", .positiveAllostericModulator, .primary), b("AMPA/kainate", .antagonist, .significant)],
        [gg, katzung])

    private static let opioidFull = moa(
        "μ-Opioid Receptor (MOR) Full Agonist",
        "Acts as a full agonist at μ-opioid receptors (MOR), G-protein coupled receptors distributed throughout the central and peripheral nervous system. MOR activation inhibits adenylyl cyclase, opens inwardly rectifying potassium channels, and closes voltage-gated calcium channels, reducing neuronal excitability and neurotransmitter release. Produces analgesia, euphoria, respiratory depression, and decreased gastrointestinal motility.",
        [b("μ-opioid (MOR)", .agonist, .primary)],
        [gg, katzung])

    private static let opioidAntag = moa(
        "Opioid Receptor Antagonist",
        "Acts as a competitive antagonist at μ, κ, and δ-opioid receptors, with highest affinity for μ-opioid receptors. Displaces opioid agonists from receptors, reversing opioid-induced respiratory depression, sedation, and analgesia. Used for opioid overdose reversal and maintenance treatment of opioid and alcohol use disorders.",
        [b("μ-opioid", .antagonist, .primary), b("κ-opioid", .antagonist, .significant)],
        [gg, katzung])

    private static let amphetamine = moa(
        "Monoamine Releasing Agent",
        "Enters monoaminergic nerve terminals via dopamine (DAT), norepinephrine (NET), and serotonin (SERT) transporters, then reverses their function to release stored neurotransmitters into the synaptic cleft. Also activates trace amine-associated receptor 1 (TAAR1), inhibits vesicular monoamine transporter 2 (VMAT2), and weakly inhibits monoamine oxidase. The net effect is a substantial increase in synaptic dopamine, norepinephrine, and to a lesser extent serotonin.",
        [b("DAT", .releasingAgent, .primary), b("NET", .releasingAgent, .primary),
         b("TAAR1", .agonist, .significant), b("VMAT2", .modulator, .significant)],
        [gg, stahl])

    private static let cathinone = moa(
        "Substituted Cathinone (Synthetic Monoamine Modulator)",
        "Structurally related to amphetamine, acts on monoamine transporters as either a releasing agent, reuptake inhibitor, or both, depending on the specific compound. Generally increases synaptic dopamine, norepinephrine, and/or serotonin. The ratio of dopamine to serotonin activity varies significantly between compounds and determines whether effects are more stimulant-like or empathogenic.",
        [b("DAT", .modulator, .primary), b("NET", .modulator, .primary), b("SERT", .modulator, .significant)],
        [pw, gg])

    private static let classicalPsychedelic = moa(
        "Serotonin 5-HT2A Receptor Agonist (Classical Psychedelic)",
        "Primarily acts as an agonist or partial agonist at serotonin 5-HT2A receptors, particularly on layer V pyramidal neurons in the prefrontal cortex. 5-HT2A activation increases glutamate release and enhances cortical excitability, leading to altered perception, cognition, and consciousness. Most classical psychedelics also interact with 5-HT2C, 5-HT1A, and other serotonin receptor subtypes.",
        [b("5-HT2A", .agonist, .primary), b("5-HT2C", .agonist, .significant), b("5-HT1A", .agonist, .weak)],
        [gg, pw])

    private static let nmdaDissociative = moa(
        "NMDA Receptor Antagonist (Dissociative)",
        "Blocks N-methyl-D-aspartate (NMDA) glutamate receptors, typically by binding within the ion channel pore as a non-competitive antagonist. NMDA receptor blockade reduces excitatory glutamatergic neurotransmission, producing dissociative anesthesia, analgesia, and altered states of consciousness characterized by feelings of detachment from body and environment.",
        [b("NMDA", .antagonist, .primary)],
        [gg, pw])

    private static let cannabinoidAgonist = moa(
        "Cannabinoid CB1/CB2 Receptor Agonist",
        "Acts as an agonist at cannabinoid CB1 receptors in the central nervous system and CB2 receptors in immune tissues. CB1 activation inhibits adenylyl cyclase and modulates ion channels via Gi/Go proteins, reducing neurotransmitter release (particularly GABA and glutamate) in brain regions involved in reward, memory, coordination, and pain perception.",
        [b("CB1", .agonist, .primary), b("CB2", .agonist, .significant)],
        [gg, katzung])

    private static let gabapentinoid = moa(
        "Voltage-Gated Calcium Channel α2δ Subunit Ligand",
        "Binds to the α2δ-1 subunit of voltage-gated calcium channels (VGCCs), reducing calcium influx at presynaptic nerve terminals. This decreases the release of excitatory neurotransmitters including glutamate, norepinephrine, substance P, and calcitonin gene-related peptide. Despite the name, gabapentinoids do not interact with GABA receptors or GABA metabolism.",
        [b("α2δ-1 VGCC", .channelBlocker, .primary)],
        [gg, stahl])

    private static let betaBlocker = moa(
        "β-Adrenergic Receptor Antagonist",
        "Competitively blocks β-adrenergic receptors, preventing the effects of catecholamines. β1-selective agents primarily reduce heart rate and cardiac contractility. Non-selective agents also block β2 receptors in bronchial smooth muscle and peripheral vasculature. Used for hypertension, arrhythmias, heart failure, and performance anxiety.",
        [b("β1-adrenergic", .antagonist, .primary), b("β2-adrenergic", .antagonist, .significant)],
        [gg, katzung])

    private static let aceInhibitor = moa(
        "Angiotensin-Converting Enzyme (ACE) Inhibitor",
        "Inhibits angiotensin-converting enzyme (ACE), preventing the conversion of angiotensin I to angiotensin II, a potent vasoconstrictor. Also reduces degradation of bradykinin, a vasodilator. The net effect is decreased peripheral vascular resistance, reduced aldosterone secretion, and lower blood pressure. ACE inhibitors also reduce cardiac remodeling after myocardial infarction.",
        [b("ACE", .enzymeInhibitor, .primary)],
        [gg, katzung])

    private static let arb = moa(
        "Angiotensin II Receptor Blocker (ARB)",
        "Selectively blocks angiotensin II type 1 (AT1) receptors, preventing the vasoconstrictive, aldosterone-secreting, and growth-promoting effects of angiotensin II. Unlike ACE inhibitors, ARBs do not affect bradykinin metabolism and therefore do not cause cough. Provides similar hemodynamic effects to ACE inhibitors through a different mechanism.",
        [b("AT1", .antagonist, .primary)],
        [gg, katzung])

    private static let nsaid = moa(
        "Cyclooxygenase (COX) Inhibitor (NSAID)",
        "Reversibly inhibits cyclooxygenase enzymes COX-1 and COX-2, reducing the synthesis of prostaglandins from arachidonic acid. COX-2 inhibition mediates anti-inflammatory and analgesic effects, while COX-1 inhibition reduces gastric mucosal protection. Central prostaglandin inhibition contributes to antipyretic effects.",
        [b("COX-1", .enzymeInhibitor, .primary), b("COX-2", .enzymeInhibitor, .primary)],
        [gg, katzung])

    private static let antihistamine1 = moa(
        "Histamine H1 Receptor Inverse Agonist (First-Generation)",
        "Acts as an inverse agonist at histamine H1 receptors, reducing constitutive receptor activity and blocking histamine-mediated signaling. Crosses the blood-brain barrier readily, producing sedation, anxiolysis, and antiemetic activity through central H1 blockade. Most also have significant anticholinergic (muscarinic antagonist) activity.",
        [b("H1", .inverseAgonist, .primary), b("Muscarinic", .antagonist, .significant)],
        [gg, katzung])

    private static let antihistamine2 = moa(
        "Histamine H1 Receptor Inverse Agonist (Second-Generation)",
        "Selectively acts as an inverse agonist at peripheral histamine H1 receptors with minimal blood-brain barrier penetration. Provides antiallergic and antipruritic effects without significant sedation or cognitive impairment. Reduced CNS penetration is due to P-glycoprotein efflux at the blood-brain barrier.",
        [b("H1 (peripheral)", .inverseAgonist, .primary)],
        [gg, katzung])

    private static let ppi = moa(
        "Proton Pump Inhibitor (PPI)",
        "Irreversibly inhibits the hydrogen-potassium ATPase (H⁺/K⁺ ATPase, the proton pump) on the luminal surface of gastric parietal cells. This blocks the final step of acid secretion regardless of the stimulus, producing a profound and long-lasting reduction in gastric acid production. Requires activation in the acidic environment of the parietal cell canaliculus.",
        [b("H⁺/K⁺ ATPase", .enzymeInhibitor, .primary)],
        [gg, katzung])

    private static let racetam = moa(
        "Racetam Nootropic (Glutamatergic/Cholinergic Modulator)",
        "Exact mechanism not fully established. Modulates AMPA-type glutamate receptors (positive allosteric modulation), enhancing glutamatergic neurotransmission and synaptic plasticity. May also increase acetylcholine turnover and improve cerebral blood flow. Individual racetams vary in their receptor selectivity and additional mechanisms.",
        [b("AMPA", .positiveAllostericModulator, .primary), b("Acetylcholine", .modulator, .significant)],
        [db, pw])

    private static let statin = moa(
        "HMG-CoA Reductase Inhibitor (Statin)",
        "Competitively inhibits 3-hydroxy-3-methylglutaryl-coenzyme A (HMG-CoA) reductase, the rate-limiting enzyme in hepatic cholesterol synthesis. Reduced intracellular cholesterol upregulates LDL receptor expression on hepatocytes, increasing LDL clearance from the blood. Also produces pleiotropic effects including improved endothelial function and anti-inflammatory activity.",
        [b("HMG-CoA reductase", .enzymeInhibitor, .primary)],
        [gg, katzung])

    private static let triptan = moa(
        "Serotonin 5-HT1B/1D Receptor Agonist (Triptan)",
        "Selectively activates serotonin 5-HT1B receptors on cranial blood vessels (causing vasoconstriction of dilated meningeal arteries) and 5-HT1D receptors on trigeminal nerve terminals (inhibiting release of vasoactive neuropeptides including CGRP and substance P). This dual action reverses the pathophysiology of migraine: vasodilation and neurogenic inflammation.",
        [b("5-HT1B", .agonist, .primary), b("5-HT1D", .agonist, .primary)],
        [gg, katzung])

    private static let corticosteroid = moa(
        "Glucocorticoid Receptor Agonist",
        "Binds to intracellular glucocorticoid receptors, which translocate to the nucleus and modulate gene transcription. Upregulates anti-inflammatory proteins (lipocortins, IL-10) and downregulates pro-inflammatory mediators (cytokines, prostaglandins, leukotrienes). Also suppresses immune cell activation and migration. Metabolic effects include increased gluconeogenesis and altered fat distribution.",
        [b("Glucocorticoid receptor", .agonist, .primary)],
        [gg, katzung])

    private static let fluoroquinolone = moa(
        "Bacterial DNA Gyrase and Topoisomerase IV Inhibitor",
        "Inhibits bacterial DNA gyrase (topoisomerase II) and topoisomerase IV, enzymes essential for DNA replication, transcription, repair, and recombination. DNA gyrase inhibition prevents supercoil relaxation; topoisomerase IV inhibition prevents daughter chromosome separation. These actions are bactericidal. Human topoisomerases are structurally different, providing selectivity.",
        [b("DNA gyrase", .enzymeInhibitor, .primary), b("Topoisomerase IV", .enzymeInhibitor, .primary)],
        [gg, katzung])

    private static let ccb = moa(
        "Calcium Channel Blocker (Dihydropyridine)",
        "Blocks L-type voltage-gated calcium channels in vascular smooth muscle, reducing calcium influx and causing vasodilation. Primarily acts on arterial smooth muscle with minimal cardiac effects at therapeutic doses. Reduces peripheral vascular resistance and blood pressure.",
        [b("L-type Ca²⁺ channels", .channelBlocker, .primary)],
        [gg, katzung])

    // MARK: - Shared Unique Mechanisms

    private static let ketamineMOA = moa(
        "Non-Competitive NMDA Receptor Antagonist with Rapid Antidepressant Properties",
        "Acts as a non-competitive antagonist at the NMDA glutamate receptor by binding within the ion channel pore (use-dependent blockade). Produces dissociative anesthesia at higher doses and rapid antidepressant effects at sub-anesthetic doses. The antidepressant mechanism involves enhanced AMPA receptor signaling, increased brain-derived neurotrophic factor (BDNF) release, and activation of the mTOR signaling pathway, promoting rapid synaptic plasticity.",
        [b("NMDA", .antagonist, .primary), b("AMPA", .modulator, .significant), b("mTOR", .modulator, .significant)],
        [gg, stahl])

    // MARK: - Category Fallbacks

    private static let categoryData: [SubstanceCategory: MechanismOfAction] = [
        .stimulant: moa(
            "Central Nervous System Stimulant",
            "Increases central nervous system activity by enhancing monoamine neurotransmission, typically through increased release or reduced reuptake of dopamine and/or norepinephrine. The specific mechanism varies by substance class (releasing agents, reuptake inhibitors, or receptor agonists). Effects include increased alertness, attention, and energy.",
            [b("Dopamine", .modulator, .primary), b("Norepinephrine", .modulator, .primary)],
            [gg]),
        .psychedelic: classicalPsychedelic,
        .dissociative: nmdaDissociative,
        .opioid: opioidFull,
        .benzodiazepine: benzo,
        .gabapentinoid: gabapentinoid,
        .empathogen: moa(
            "Monoamine Releasing Agent (Serotonin-Predominant)",
            "Increases synaptic serotonin, dopamine, and norepinephrine, with a predominant serotonergic component that distinguishes empathogens from classical stimulants. Many also stimulate the release of oxytocin from the hypothalamus, contributing to prosocial effects, emotional openness, and feelings of empathy and connectedness.",
            [b("SERT", .releasingAgent, .primary), b("DAT", .releasingAgent, .significant),
             b("NET", .releasingAgent, .significant), b("Oxytocin", .modulator, .significant)],
            [gg, pw]),
        .cannabinoid: cannabinoidAgonist,
        .nootropic: moa(
            "Cognitive-Enhancing Agent (Nootropic)",
            "Nootropic agents enhance cognitive function through diverse mechanisms which may include modulation of acetylcholine, glutamate, or monoamine neurotransmitter systems; improvement of cerebral blood flow; neuroprotection through antioxidant activity; or modulation of neuroplasticity signaling cascades. Mechanisms vary widely and are substance-specific.",
            [b("Various", .modulator, .primary)],
            [db]),
        .depressant: moa(
            "Central Nervous System Depressant",
            "Reduces central nervous system excitability, typically through enhancement of inhibitory GABAergic neurotransmission and/or reduction of excitatory glutamatergic neurotransmission. Produces sedation, anxiolysis, and muscle relaxation in a dose-dependent manner.",
            [b("GABA system", .modulator, .primary), b("Glutamate system", .antagonist, .primary)],
            [gg]),
        .antidepressant: moa(
            "Antidepressant (Monoamine Modulator)",
            "Modulates monoamine neurotransmitter systems (serotonin, norepinephrine, and/or dopamine) through various mechanisms including reuptake inhibition, enzyme inhibition, or receptor modulation. The specific mechanism depends on the drug class. Therapeutic effects typically develop over 2–6 weeks.",
            [b("Serotonin", .modulator, .primary), b("Norepinephrine", .modulator, .significant), b("Dopamine", .modulator, .weak)],
            [stahl, gg]),
        .antipsychotic: atypicalAP,
        .analgesic: moa(
            "Analgesic Agent",
            "Reduces pain perception through mechanisms that may include inhibition of prostaglandin synthesis, activation of endogenous opioid pathways, modulation of descending pain inhibitory circuits, or blockade of peripheral nociceptor sensitization. The specific mechanism depends on the drug class.",
            [b("Pain pathways", .modulator, .primary)],
            [gg, katzung]),
        .antihistamine: antihistamine1,
        .cardiovascular: moa(
            "Cardiovascular Agent",
            "Modulates cardiovascular function through mechanisms including adrenergic receptor blockade, calcium channel inhibition, renin-angiotensin system modulation, or direct vasodilation. The specific mechanism depends on the drug class.",
            [b("Cardiovascular system", .modulator, .primary)],
            [gg, katzung]),
        .antimicrobial: moa(
            "Antimicrobial Agent",
            "Eliminates or inhibits the growth of microorganisms by targeting microbial-specific processes such as cell wall synthesis, protein synthesis, nucleic acid replication, metabolic pathways, or cell membrane integrity.",
            [b("Microbial targets", .modulator, .primary)],
            [gg, katzung]),
        .gastrointestinal: moa(
            "Gastrointestinal Agent",
            "Modulates digestive function through mechanisms such as acid secretion inhibition, motility modulation, mucosal protection, or neurotransmitter receptor interactions in the enteric nervous system.",
            [b("GI system", .modulator, .primary)],
            [gg, katzung]),
        .respiratory: moa(
            "Respiratory Agent",
            "Modulates airway function through mechanisms including bronchodilation via β2-adrenergic agonism or anticholinergic blockade, anti-inflammatory effects from corticosteroids, mast cell stabilization, or leukotriene receptor antagonism.",
            [b("Airway smooth muscle", .modulator, .primary), b("Inflammatory mediators", .modulator, .significant)],
            [gg, katzung]),
        .endocrine: moa(
            "Endocrine Agent",
            "Modulates hormonal signaling through receptor agonism or antagonism, enzyme inhibition affecting hormone synthesis or metabolism, or direct hormone replacement. Interacts with the hypothalamic-pituitary-endocrine axes.",
            [b("Hormonal receptors", .modulator, .primary)],
            [gg, katzung]),
        .immunological: moa(
            "Immunomodulatory Agent",
            "Modulates immune system function through mechanisms such as inhibition of inflammatory cytokine production, suppression of T-cell or B-cell activation, complement system modulation, or targeted inhibition of specific immune pathways.",
            [b("Immune system", .modulator, .primary)],
            [gg, katzung]),
        .supplement: moa(
            "Dietary Supplement",
            "Supports physiological functions through various mechanisms including enzyme cofactor activity, antioxidant effects, neurotransmitter precursor supply, hormonal modulation, or direct receptor interactions. Mechanisms vary widely and are substance-specific.",
            [b("Various", .modulator, .primary)],
            [db]),
        .other: moa(
            "Pharmacological Agent",
            "This substance's mechanism of action may involve multiple pharmacological targets or may not be fully characterized. Consult specific pharmacological references for detailed mechanistic information.",
            [b("Various", .modulator, .primary)],
            [db]),
    ]

    // MARK: - Substance Data

    // Built programmatically to avoid slow large-dictionary-literal initialization in debug builds.
    // swiftlint:disable function_body_length
    private static let substanceData: [String: MechanismOfAction] = {
        var d = [String: MechanismOfAction](minimumCapacity: 300)

        // ── SSRIs ──────────────────────────────────────────────────
        for n in ["fluoxetine", "sertraline", "paroxetine", "citalopram", "escitalopram", "fluvoxamine"] { d[n] = ssri }

        // ── SNRIs ──────────────────────────────────────────────────
        for n in ["venlafaxine", "desvenlafaxine", "duloxetine", "milnacipran", "levomilnacipran"] { d[n] = snri }

        // ── TCAs ───────────────────────────────────────────────────
        for n in ["amitriptyline", "nortriptyline", "imipramine", "desipramine", "clomipramine", "doxepin", "trimipramine", "protriptyline", "amoxapine", "maprotiline"] { d[n] = tca }

        // ── MAOIs ──────────────────────────────────────────────────
        for n in ["phenelzine", "tranylcypromine", "isocarboxazid"] { d[n] = maoi }
        d["moclobemide"] = rima
        d["selegiline"] = maobSelective; d["rasagiline"] = maobSelective

        // ── Unique Antidepressants ─────────────────────────────────
        d["bupropion"] = moa(
            "Norepinephrine-Dopamine Reuptake Inhibitor (NDRI)",
            "Inhibits the reuptake of norepinephrine (NET) and dopamine (DAT), increasing their synaptic availability. Unlike most antidepressants, has minimal effect on serotonin and does not cause sexual dysfunction or weight gain. Also acts as a non-competitive antagonist at nicotinic acetylcholine receptors, contributing to its efficacy in smoking cessation. Its active metabolite hydroxybupropion has a longer half-life and contributes significantly to clinical effects.",
            [b("NET", .reuptakeInhibitor, .primary), b("DAT", .reuptakeInhibitor, .primary), b("nAChR", .antagonist, .significant)],
            [stahl, gg])
        d["mirtazapine"] = moa(
            "Noradrenergic and Specific Serotonergic Antidepressant (NaSSA)",
            "Blocks presynaptic α2-adrenergic autoreceptors and heteroreceptors, increasing norepinephrine and serotonin release. Simultaneously blocks 5-HT2A, 5-HT2C, and 5-HT3 receptors, directing serotonergic activity through 5-HT1A receptors. Potent histamine H1 antagonism produces marked sedation and appetite stimulation, particularly at lower doses where antihistaminic effects predominate.",
            [b("α2-adrenergic", .antagonist, .primary), b("5-HT2A", .antagonist, .primary),
             b("5-HT2C", .antagonist, .primary), b("5-HT3", .antagonist, .significant), b("H1", .antagonist, .significant)],
            [stahl, gg])
        d["trazodone"] = moa(
            "Serotonin Antagonist and Reuptake Inhibitor (SARI)",
            "Combines serotonin 5-HT2A receptor antagonism with serotonin reuptake inhibition (SERT blockade). The 5-HT2A antagonism occurs at lower doses, producing anxiolytic and sleep-promoting effects. At higher antidepressant doses, SERT inhibition enhances serotonergic neurotransmission. Also blocks α1-adrenergic receptors and histamine H1 receptors, contributing to sedation.",
            [b("5-HT2A", .antagonist, .primary), b("SERT", .reuptakeInhibitor, .primary),
             b("α1", .antagonist, .significant), b("H1", .antagonist, .significant)],
            [stahl, gg])
        d["vortioxetine"] = moa(
            "Multimodal Serotonergic Antidepressant",
            "Combines SERT inhibition with direct modulation of multiple serotonin receptors: agonist at 5-HT1A, partial agonist at 5-HT1B, antagonist at 5-HT1D, 5-HT3, and 5-HT7 receptors. This multimodal mechanism enhances downstream release of serotonin, norepinephrine, dopamine, histamine, and acetylcholine. The 5-HT3 and 5-HT7 antagonism may contribute to procognitive effects.",
            [b("SERT", .reuptakeInhibitor, .primary), b("5-HT1A", .agonist, .significant),
             b("5-HT3", .antagonist, .significant), b("5-HT7", .antagonist, .significant)],
            [stahl, gg])
        d["vilazodone"] = moa(
            "SSRI and 5-HT1A Partial Agonist",
            "Combines serotonin reuptake inhibition (SERT blockade) with partial agonism at serotonin 5-HT1A receptors. The 5-HT1A partial agonism may accelerate the onset of antidepressant action by partially bypassing the delayed desensitization of presynaptic autoreceptors required by pure SSRIs. May produce fewer sexual side effects than SSRIs due to 5-HT1A activity.",
            [b("SERT", .reuptakeInhibitor, .primary), b("5-HT1A", .partialAgonist, .significant)],
            [stahl, gg])
        d["agomelatine"] = moa(
            "Melatonin Receptor Agonist and 5-HT2C Antagonist",
            "Agonizes melatonin MT1 and MT2 receptors, resynchronizing circadian rhythms and improving sleep architecture. Simultaneously antagonizes serotonin 5-HT2C receptors, which disinhibits norepinephrine and dopamine release in the prefrontal cortex. This unique dual mechanism provides antidepressant effects without the sexual dysfunction, weight gain, or discontinuation syndrome associated with serotonin reuptake inhibitors.",
            [b("MT1", .agonist, .primary), b("MT2", .agonist, .primary), b("5-HT2C", .antagonist, .primary)],
            [stahl])
        d["atomoxetine"] = moa(
            "Selective Norepinephrine Reuptake Inhibitor (NRI)",
            "Selectively inhibits the norepinephrine transporter (NET), increasing norepinephrine in the synaptic cleft. In the prefrontal cortex, where dopamine is also cleared by NET due to low DAT density, atomoxetine indirectly increases both norepinephrine and dopamine. This dual prefrontal effect enhances attention and executive function without dopamine release in the nucleus accumbens, resulting in minimal abuse potential.",
            [b("NET", .reuptakeInhibitor, .primary)],
            [stahl, gg])
        d["tianeptine"] = moa(
            "μ-Opioid Receptor Agonist (Atypical Antidepressant)",
            "Initially classified as a serotonin reuptake enhancer, but now understood to primarily act as a full agonist at μ-opioid receptors (MOR) and δ-opioid receptors. MOR activation in the mesolimbic system produces antidepressant, anxiolytic, and analgesic effects. Also modulates glutamatergic neurotransmission and neuroplasticity in the hippocampus and amygdala.",
            [b("μ-opioid", .agonist, .primary), b("δ-opioid", .agonist, .significant)],
            [stahl, db])

        // ── Typical Antipsychotics ─────────────────────────────────
        for n in ["haloperidol", "chlorpromazine", "fluphenazine", "perphenazine", "thioridazine", "trifluoperazine", "loxapine", "pimozide", "thiothixene", "droperidol"] { d[n] = typicalAP }

        // ── Atypical Antipsychotics ────────────────────────────────
        for n in ["risperidone", "olanzapine", "quetiapine", "ziprasidone", "paliperidone", "lurasidone", "iloperidone", "asenapine"] { d[n] = atypicalAP }
        d["aripiprazole"] = moa(
            "Dopamine D2 Partial Agonist and Serotonin Modulator",
            "Unique among antipsychotics as a partial agonist at dopamine D2 receptors — acting as a functional antagonist in hyperdopaminergic states (mesolimbic pathway) and a functional agonist in hypodopaminergic states (mesocortical pathway). This 'dopamine stabilizer' mechanism reduces positive symptoms while potentially improving negative symptoms and cognition. Also acts as a partial agonist at 5-HT1A and an antagonist at 5-HT2A receptors.",
            [b("D2", .partialAgonist, .primary), b("5-HT1A", .partialAgonist, .significant), b("5-HT2A", .antagonist, .significant)],
            [stahl, gg])
        d["brexpiprazole"] = moa(
            "Serotonin-Dopamine Activity Modulator (D2 Partial Agonist)",
            "Similar to aripiprazole, acts as a partial agonist at dopamine D2 and serotonin 5-HT1A receptors, and an antagonist at 5-HT2A receptors. Compared to aripiprazole, has lower intrinsic activity at D2 receptors (more antagonist-like) and stronger 5-HT1A partial agonism, which may reduce akathisia and improve tolerability.",
            [b("D2", .partialAgonist, .primary), b("5-HT1A", .partialAgonist, .significant), b("5-HT2A", .antagonist, .significant)],
            [stahl])
        d["cariprazine"] = moa(
            "D3-Preferring Dopamine Partial Agonist",
            "Partial agonist at dopamine D3 and D2 receptors with preferential affinity for D3 receptors. D3 receptor occupancy in the mesolimbic pathway may particularly benefit negative symptoms, cognitive deficits, and anhedonia. Also acts as a partial agonist at 5-HT1A and an antagonist at 5-HT2A/2B receptors. Has an active metabolite with a very long half-life.",
            [b("D3", .partialAgonist, .primary), b("D2", .partialAgonist, .primary), b("5-HT1A", .partialAgonist, .significant)],
            [stahl])
        d["clozapine"] = moa(
            "Multi-Receptor Antagonist (Atypical Antipsychotic with Unique Efficacy)",
            "Distinguished by high 5-HT2A affinity relative to D2, with uniquely rapid D2 dissociation ('fast-off' theory). Has significant affinity for D1, D3, D4, muscarinic M1/M4, histamine H1, and α1/α2-adrenergic receptors. This broad receptor profile underlies its unique efficacy in treatment-resistant schizophrenia. M1/M4 muscarinic activity may contribute to cognitive benefits. Risk of agranulocytosis necessitates blood monitoring.",
            [b("5-HT2A", .antagonist, .primary), b("D2", .antagonist, .primary),
             b("D1", .antagonist, .significant), b("D4", .antagonist, .significant),
             b("M1", .antagonist, .significant), b("H1", .antagonist, .significant), b("α1", .antagonist, .significant)],
            [stahl, gg])

        // ── Benzodiazepines ────────────────────────────────────────
        for n in ["diazepam", "alprazolam", "clonazepam", "lorazepam", "midazolam", "triazolam", "temazepam", "chlordiazepoxide", "oxazepam", "flurazepam", "nitrazepam", "estazolam", "quazepam", "clorazepate", "flunitrazepam", "phenazepam", "bromazepam", "etizolam", "flualprazolam", "clonazolam", "flubromazolam", "bromazolam"] { d[n] = benzo }

        // ── Z-Drugs ───────────────────────────────────────────────
        for n in ["zolpidem", "zopiclone", "zaleplon", "eszopiclone"] { d[n] = zDrug }

        // ── Barbiturates ──────────────────────────────────────────
        for n in ["phenobarbital", "pentobarbital", "secobarbital", "amobarbital", "butalbital", "thiopental", "methohexital"] { d[n] = barb }

        // ── Opioid Agonists ───────────────────────────────────────
        for n in ["morphine", "heroin"] { d[n] = opioidFull }
        for n in ["diacetylmorphine", "diamorphine"] { d[n] = opioidFull }
        for n in ["oxycodone", "hydrocodone"] { d[n] = opioidFull }
        for n in ["oxymorphone", "hydromorphone"] { d[n] = opioidFull }
        for n in ["fentanyl", "sufentanil"] { d[n] = opioidFull }
        for n in ["meperidine", "pethidine"] { d[n] = opioidFull }
        d["levorphanol"] = opioidFull
        d["codeine"] = moa(
            "Prodrug → Morphine (CYP2D6-Dependent Opioid)",
            "A prodrug that is metabolized to morphine by the cytochrome P450 enzyme CYP2D6. Codeine itself has very weak affinity for μ-opioid receptors; its analgesic and antitussive effects depend on conversion to morphine. Genetic polymorphisms in CYP2D6 significantly affect efficacy — poor metabolizers get little benefit, while ultra-rapid metabolizers may experience dangerous opioid levels.",
            [b("μ-opioid (via morphine)", .agonist, .primary)],
            [gg, katzung])
        d["tapentadol"] = moa(
            "μ-Opioid Receptor Agonist and Norepinephrine Reuptake Inhibitor",
            "Combines μ-opioid receptor (MOR) agonism with norepinephrine reuptake inhibition (NET blockade) in a single molecule. Unlike tramadol, tapentadol does not require metabolic activation and does not significantly affect serotonin. The dual mechanism provides synergistic analgesia with a lower opioid burden and reduced gastrointestinal side effects compared to equianalgesic doses of classical opioids.",
            [b("μ-opioid", .agonist, .primary), b("NET", .reuptakeInhibitor, .primary)],
            [gg, katzung])
        d["buprenorphine"] = moa(
            "Partial μ-Opioid Agonist and κ-Opioid Antagonist",
            "Acts as a high-affinity partial agonist at μ-opioid receptors (MOR), producing submaximal receptor activation even at full occupancy. This creates a ceiling effect for respiratory depression while providing effective analgesia and opioid withdrawal relief. Simultaneously antagonizes κ-opioid receptors (KOR), which may contribute to antidepressant and anti-dysphoric effects. Slow receptor dissociation contributes to its long duration of action.",
            [b("μ-opioid", .partialAgonist, .primary), b("κ-opioid", .antagonist, .significant)],
            [gg, katzung])
        d["tramadol"] = moa(
            "Weak μ-Opioid Agonist and Serotonin-Norepinephrine Reuptake Inhibitor",
            "Produces analgesia through a dual mechanism. The parent compound weakly agonizes μ-opioid receptors and inhibits serotonin and norepinephrine reuptake. Its active metabolite O-desmethyltramadol (M1), formed by CYP2D6, has approximately 200-fold greater μ-opioid affinity. The combination of opioid and monoaminergic mechanisms provides synergistic analgesia but increases seizure risk and serotonin syndrome potential.",
            [b("μ-opioid", .agonist, .weak), b("SERT", .reuptakeInhibitor, .significant), b("NET", .reuptakeInhibitor, .significant)],
            [gg, katzung])
        d["methadone"] = moa(
            "Full μ-Opioid Agonist and NMDA Receptor Antagonist",
            "Acts as a full agonist at μ-opioid receptors with additional NMDA receptor antagonist activity. The NMDA antagonism may reduce opioid tolerance development and contribute to analgesic efficacy in neuropathic pain. Has a very long and variable half-life (15–60 hours), providing sustained opioid receptor occupancy that suppresses withdrawal and craving. Also weakly inhibits serotonin and norepinephrine reuptake.",
            [b("μ-opioid", .agonist, .primary), b("NMDA", .antagonist, .significant)],
            [gg, katzung])
        d["kratom"] = moa(
            "Partial μ-Opioid Agonist and Adrenergic/Serotonergic Modulator",
            "The primary alkaloid mitragynine acts as a partial agonist at μ-opioid receptors (MOR), producing dose-dependent analgesic and euphoric effects. At lower doses, stimulant-like effects are attributed to α2-adrenergic agonism and 5-HT2A antagonism. The metabolite 7-hydroxymitragynine has significantly higher MOR potency. Unlike classical opioids, mitragynine also acts as a κ-opioid receptor antagonist.",
            [b("μ-opioid", .partialAgonist, .primary), b("κ-opioid", .antagonist, .significant),
             b("α2-adrenergic", .agonist, .significant), b("5-HT2A", .antagonist, .weak)],
            [db, pw])
        d["mitragynine"] = moa(
            "Partial μ-Opioid Agonist and Adrenergic/Serotonergic Modulator",
            "The primary alkaloid in kratom. Acts as a partial agonist at μ-opioid receptors (MOR), producing dose-dependent analgesic and euphoric effects. At lower doses, stimulant-like effects are attributed to α2-adrenergic agonism and 5-HT2A antagonism. The metabolite 7-hydroxymitragynine has significantly higher MOR potency. Also acts as a κ-opioid receptor antagonist.",
            [b("μ-opioid", .partialAgonist, .primary), b("κ-opioid", .antagonist, .significant),
             b("α2-adrenergic", .agonist, .significant), b("5-HT2A", .antagonist, .weak)],
            [db, pw])
        d["loperamide"] = moa(
            "Peripheral μ-Opioid Receptor Agonist",
            "Acts as a μ-opioid receptor agonist on myenteric plexus neurons in the gastrointestinal tract, reducing peristalsis and intestinal secretion. Does not cross the blood-brain barrier at therapeutic doses due to P-glycoprotein efflux, so it produces antidiarrheal effects without central opioid effects. At very high (supratherapeutic) doses, may overwhelm the efflux mechanism.",
            [b("μ-opioid (peripheral)", .agonist, .primary)],
            [gg, katzung])
        d["naloxone"] = moa(
            "Competitive μ-Opioid Receptor Antagonist (Short-Acting)",
            "Acts as a competitive antagonist at μ-opioid receptors (MOR), with lower affinity for κ and δ receptors. Rapidly displaces opioid agonists from MOR, reversing respiratory depression, sedation, and analgesia. Has poor oral bioavailability due to extensive first-pass metabolism, necessitating parenteral or intranasal administration. Short duration of action (30–90 minutes) may require repeat dosing for long-acting opioids.",
            [b("μ-opioid", .antagonist, .primary), b("κ-opioid", .antagonist, .significant), b("δ-opioid", .antagonist, .significant)],
            [gg, katzung])
        d["naltrexone"] = moa(
            "Long-Acting Opioid Receptor Antagonist",
            "Acts as a competitive antagonist at μ, κ, and δ-opioid receptors with good oral bioavailability and long duration of action (24–72 hours). At standard doses (50 mg), blocks the euphoric effects of exogenous opioids. Also used for alcohol use disorder, where it reduces alcohol-induced dopamine release and craving through opioid system modulation.",
            [b("μ-opioid", .antagonist, .primary), b("κ-opioid", .antagonist, .significant), b("δ-opioid", .antagonist, .significant)],
            [gg, katzung])

        // ── Stimulants ────────────────────────────────────────────
        for n in ["amphetamine", "dextroamphetamine"] { d[n] = amphetamine }
        d["methamphetamine"] = amphetamine
        d["lisdexamfetamine"] = moa(
            "Prodrug of Dextroamphetamine (Monoamine Releasing Agent)",
            "A pharmacologically inactive prodrug cleaved in red blood cells to release dextroamphetamine and L-lysine. The dextroamphetamine then acts as a monoamine releasing agent via DAT, NET, SERT reversal and TAAR1 activation. The prodrug formulation provides controlled, gradual release of active drug, reducing abuse potential and producing smoother pharmacokinetics compared to immediate-release amphetamine.",
            [b("DAT", .releasingAgent, .primary), b("NET", .releasingAgent, .primary),
             b("TAAR1", .agonist, .significant), b("VMAT2", .modulator, .significant)],
            [gg, stahl])
        d["cocaine"] = moa(
            "Triple Monoamine Reuptake Inhibitor",
            "Blocks the dopamine (DAT), norepinephrine (NET), and serotonin (SERT) transporters, preventing reuptake and increasing synaptic monoamine levels. Unlike amphetamines, cocaine inhibits reuptake without reversing transporter function or releasing stored neurotransmitters. The rapid onset and short duration of DAT blockade contribute to its high addiction potential. Also blocks voltage-gated sodium channels, producing local anesthetic effects.",
            [b("DAT", .reuptakeInhibitor, .primary), b("NET", .reuptakeInhibitor, .primary),
             b("SERT", .reuptakeInhibitor, .significant), b("Na⁺ channels", .channelBlocker, .weak)],
            [gg, stahl])
        d["methylphenidate"] = moa(
            "Dopamine-Norepinephrine Reuptake Inhibitor",
            "Blocks the dopamine transporter (DAT) and norepinephrine transporter (NET), increasing synaptic dopamine and norepinephrine. Unlike amphetamines, methylphenidate is a pure reuptake inhibitor — it does not reverse transporter function or release stored monoamines. Preferentially increases catecholamines in the prefrontal cortex and striatum, enhancing attention, working memory, and executive function.",
            [b("DAT", .reuptakeInhibitor, .primary), b("NET", .reuptakeInhibitor, .primary)],
            [gg, stahl])
        d["caffeine"] = moa(
            "Non-Selective Adenosine Receptor Antagonist",
            "Competitively antagonizes adenosine A1 and A2A receptors. Adenosine normally promotes sleep and suppresses arousal; blocking its receptors increases wakefulness and alertness. A2A antagonism in the striatum indirectly enhances dopaminergic signaling. At supratherapeutic doses, also inhibits phosphodiesterases (increasing intracellular cAMP), but this effect is less significant at normal dietary doses.",
            [b("Adenosine A1", .antagonist, .primary), b("Adenosine A2A", .antagonist, .primary)],
            [gg, katzung])
        d["nicotine"] = moa(
            "Nicotinic Acetylcholine Receptor (nAChR) Agonist",
            "Acts as an agonist at nicotinic acetylcholine receptors (nAChRs), ligand-gated ion channels that open in response to acetylcholine. Primary targets include α4β2 nAChRs (high affinity, involved in reward and cognition) and α7 nAChRs (involved in cognitive enhancement). Activation of nAChRs in the ventral tegmental area stimulates dopamine release in the nucleus accumbens, mediating reinforcing effects and addiction.",
            [b("α4β2 nAChR", .agonist, .primary), b("α7 nAChR", .agonist, .significant)],
            [gg, stahl])
        d["modafinil"] = moa(
            "Wakefulness-Promoting Agent (Atypical Stimulant)",
            "Mechanism not fully established. Weakly inhibits the dopamine transporter (DAT), increasing extracellular dopamine. Also activates hypothalamic orexin/hypocretin neurons and increases histamine release in the tuberomammillary nucleus, both promoting wakefulness. Modulates norepinephrine, serotonin, and glutamate/GABA balance. Unlike amphetamines, does not significantly release catecholamines.",
            [b("DAT", .reuptakeInhibitor, .weak), b("Orexin", .modulator, .significant), b("Histamine", .modulator, .significant)],
            [gg, stahl])
        d["armodafinil"] = moa(
            "Wakefulness-Promoting Agent (R-Enantiomer of Modafinil)",
            "The R-enantiomer of modafinil with the same mechanism: weak DAT inhibition, orexin/hypocretin neuron activation, and histamine release promotion. Has a longer effective half-life than racemic modafinil, providing more sustained wakefulness-promoting effects throughout the day.",
            [b("DAT", .reuptakeInhibitor, .weak), b("Orexin", .modulator, .significant), b("Histamine", .modulator, .significant)],
            [gg, stahl])

        // ── Substituted Cathinones ────────────────────────────────
        for n in ["mephedrone", "methylone"] { d[n] = cathinone }
        for n in ["mdpv", "α-pvp", "a-pvp"] { d[n] = cathinone }
        for n in ["cathinone", "methcathinone"] { d[n] = cathinone }
        for n in ["4-mmc", "3-mmc"] { d[n] = cathinone }

        // ── Empathogens ───────────────────────────────────────────
        d["mdma"] = moa(
            "Serotonin-Predominant Monoamine Releasing Agent and Empathogen",
            "Enters serotonergic, dopaminergic, and noradrenergic nerve terminals via their respective transporters and reverses transporter function to release stored monoamines. Has strongest affinity for SERT, producing pronounced serotonin release that distinguishes it from amphetamine. Also stimulates oxytocin release from the hypothalamus, contributing to prosocial and empathogenic effects. Additionally directly inhibits SERT, DAT, and NET reuptake.",
            [b("SERT", .releasingAgent, .primary), b("DAT", .releasingAgent, .significant),
             b("NET", .releasingAgent, .significant), b("Oxytocin", .modulator, .significant)],
            [gg, pw])
        d["mda"] = moa(
            "Serotonin-Predominant Monoamine Releasing Agent",
            "Structurally related to MDMA, acts as a monoamine releasing agent with strong serotonergic predominance. Releases serotonin, dopamine, and norepinephrine via transporter reversal. Compared to MDMA, has more pronounced psychedelic effects attributed to greater 5-HT2A receptor agonism from a metabolite, alongside empathogenic effects from serotonin release.",
            [b("SERT", .releasingAgent, .primary), b("DAT", .releasingAgent, .significant),
             b("NET", .releasingAgent, .significant), b("5-HT2A", .agonist, .significant)],
            [pw, gg])
        d["6-apb"] = moa(
            "Benzofuran Empathogen (Monoamine Releasing Agent)",
            "A benzofuran analogue of MDA that acts as a serotonin-predominant monoamine releasing agent. Releases serotonin, dopamine, and norepinephrine with strong SERT selectivity. Also acts as a 5-HT2B agonist, which raises cardiovascular safety concerns with repeated use. Produces empathogenic effects similar to MDMA with a longer duration of action.",
            [b("SERT", .releasingAgent, .primary), b("DAT", .releasingAgent, .significant),
             b("NET", .releasingAgent, .significant), b("5-HT2B", .agonist, .weak)],
            [pw, db])
        d["5-apb"] = moa(
            "Benzofuran Empathogen (Monoamine Releasing Agent)",
            "A benzofuran analogue that releases serotonin, dopamine, and norepinephrine via transporter reversal. Acts as an agonist at 5-HT2B receptors. Produces empathogenic and mildly psychedelic effects with a profile between MDMA and MDA.",
            [b("SERT", .releasingAgent, .primary), b("DAT", .releasingAgent, .significant), b("NET", .releasingAgent, .significant)],
            [pw, db])

        // ── Classical Psychedelics ─────────────────────────────────
        for n in ["lsd", "lsd-25"] { d[n] = classicalPsychedelic }
        for n in ["1p-lsd", "1cp-lsd"] { d[n] = classicalPsychedelic }
        for n in ["ald-52", "eth-lad"] { d[n] = classicalPsychedelic }
        d["al-lad"] = classicalPsychedelic
        d["psilocybin"] = moa(
            "Prodrug → Psilocin (5-HT2A Agonist)",
            "A prodrug rapidly dephosphorylated to psilocin by alkaline phosphatase. Psilocin acts as an agonist at serotonin 5-HT2A receptors (primary psychedelic target), with additional activity at 5-HT2C, 5-HT1A, and other serotonin subtypes. 5-HT2A activation on cortical pyramidal neurons increases glutamate release and enhances connectivity between brain networks that are normally segregated, producing altered perception and consciousness.",
            [b("5-HT2A", .agonist, .primary), b("5-HT2C", .agonist, .significant), b("5-HT1A", .agonist, .weak)],
            [gg, pw])
        d["psilocin"] = classicalPsychedelic
        for n in ["4-aco-dmt", "4-ho-met"] { d[n] = classicalPsychedelic }
        d["4-ho-mipt"] = classicalPsychedelic
        d["dmt"] = moa(
            "Serotonin 5-HT2A Agonist and Sigma-1 Receptor Agonist",
            "Acts as an agonist at serotonin 5-HT2A receptors (primary psychedelic mechanism) and also activates sigma-1 receptors, which may modulate ion channels, ER stress responses, and neuroplasticity. Additionally interacts with trace amine-associated receptors. DMT is rapidly metabolized by monoamine oxidase (MAO), requiring an MAO inhibitor (as in ayahuasca) for oral activity.",
            [b("5-HT2A", .agonist, .primary), b("Sigma-1", .agonist, .significant), b("TAAR", .agonist, .weak)],
            [gg, pw])
        d["5-meo-dmt"] = moa(
            "Potent 5-HT1A and 5-HT2A Receptor Agonist",
            "Acts as a potent agonist at both serotonin 5-HT1A and 5-HT2A receptors. The strong 5-HT1A activation distinguishes it from most classical psychedelics and contributes to its characteristic intense, ego-dissolving effects with less visual distortion. Like DMT, rapidly metabolized by MAO. The 5-HT1A component may produce cardiovascular effects including hypotension.",
            [b("5-HT1A", .agonist, .primary), b("5-HT2A", .agonist, .primary)],
            [pw, db])
        for n in ["mescaline", "dpt"] { d[n] = classicalPsychedelic }
        for n in ["2c-b", "2c-e"] { d[n] = classicalPsychedelic }
        for n in ["2c-i", "2c-c"] { d[n] = classicalPsychedelic }
        d["2c-t-7"] = classicalPsychedelic
        for n in ["dob", "doc"] { d[n] = classicalPsychedelic }
        for n in ["doi", "dom"] { d[n] = classicalPsychedelic }
        d["25i-nbome"] = moa(
            "Full 5-HT2A Receptor Agonist (High Potency)",
            "An N-benzylmethoxy derivative that acts as a highly potent full agonist at serotonin 5-HT2A receptors with much greater efficacy than partial agonists like LSD. The full agonism and high potency at 5-HT2A receptors are associated with a steeper dose-response curve, greater risk of seizures, vasoconstriction, and a narrower margin of safety compared to classical partial agonist psychedelics.",
            [b("5-HT2A", .agonist, .primary)],
            [pw, db])
        d["25c-nbome"] = moa(
            "Full 5-HT2A Receptor Agonist (High Potency)",
            "An N-benzylmethoxy phenethylamine that acts as a full agonist at 5-HT2A receptors with very high potency. Like other NBOMe compounds, the full agonism contributes to a steeper dose-response curve and greater toxicity risk compared to classical psychedelics. Active at microgram doses.",
            [b("5-HT2A", .agonist, .primary)],
            [pw, db])

        // ── Dissociatives ──────────────────────────────────────────
        for n in ["ketamine", "esketamine"] { d[n] = ketamineMOA }
        d["pcp"] = moa(
            "Non-Competitive NMDA Antagonist and Dopamine Reuptake Inhibitor",
            "Blocks NMDA glutamate receptors as a non-competitive antagonist. Also inhibits the dopamine transporter (DAT), increasing synaptic dopamine — this dopaminergic activity distinguishes PCP from other dissociatives and contributes to its stimulant properties and higher psychosis risk. Additionally interacts with sigma receptors, nicotinic receptors, and voltage-gated sodium channels.",
            [b("NMDA", .antagonist, .primary), b("DAT", .reuptakeInhibitor, .significant), b("Sigma", .agonist, .weak)],
            [gg, pw])
        for n in ["3-meo-pcp", "3-ho-pcp"] { d[n] = nmdaDissociative }
        for n in ["mxe", "methoxetamine"] { d[n] = nmdaDissociative }
        for n in ["diphenidine", "methoxphenidine"] { d[n] = nmdaDissociative }
        d["dxm"] = moa(
            "NMDA Antagonist, Sigma-1 Agonist, and Serotonin Reuptake Inhibitor",
            "Produces dose-dependent effects through multiple targets. At therapeutic antitussive doses, acts primarily as a sigma-1 receptor agonist in brainstem cough centers. At higher doses, its metabolite dextrorphan acts as an NMDA antagonist producing dissociative effects. The parent compound also inhibits serotonin reuptake (SERT) and weakly activates μ-opioid receptors. CYP2D6 polymorphisms significantly affect metabolism and experience.",
            [b("NMDA", .antagonist, .primary), b("Sigma-1", .agonist, .significant),
             b("SERT", .reuptakeInhibitor, .significant), b("μ-opioid", .agonist, .weak)],
            [gg, pw])
        d["dextromethorphan"] = moa(
            "NMDA Antagonist, Sigma-1 Agonist, and Serotonin Reuptake Inhibitor",
            "Produces dose-dependent effects through multiple targets. At therapeutic antitussive doses, acts primarily as a sigma-1 receptor agonist in brainstem cough centers. At higher doses, its metabolite dextrorphan acts as an NMDA antagonist producing dissociative effects. The parent compound also inhibits serotonin reuptake (SERT) and weakly activates μ-opioid receptors. CYP2D6 polymorphisms significantly affect metabolism and experience.",
            [b("NMDA", .antagonist, .primary), b("Sigma-1", .agonist, .significant),
             b("SERT", .reuptakeInhibitor, .significant), b("μ-opioid", .agonist, .weak)],
            [gg, pw])
        d["nitrous oxide"] = moa(
            "NMDA Antagonist, Endogenous Opioid Releaser, and GABA Modulator",
            "Produces analgesia and dissociative effects through multiple mechanisms: NMDA receptor antagonism, stimulation of endogenous opioid peptide release, positive modulation of GABA-A receptors, and inhibition of certain potassium channels. Inactivates vitamin B12 (cobalamin) by oxidizing its cobalt atom, which can cause functional B12 deficiency and neurological damage with repeated heavy use.",
            [b("NMDA", .antagonist, .primary), b("Endogenous opioids", .modulator, .significant),
             b("GABA-A", .positiveAllostericModulator, .significant), b("Vitamin B12", .modulator, .weak)],
            [gg, katzung])
        d["salvia divinorum"] = moa(
            "Selective κ-Opioid Receptor Agonist (Salvinorin A)",
            "The active compound salvinorin A is a structurally unique non-nitrogenous terpenoid that acts as a highly potent and selective agonist at κ-opioid receptors (KOR). Unlike virtually all other known psychoactive compounds, it has no significant activity at serotonin 5-HT2A receptors. KOR activation in the claustrum and prefrontal cortex produces intensely dissociative and hallucinatory effects.",
            [b("κ-opioid (KOR)", .agonist, .primary)],
            [pw, db])
        d["salvinorin a"] = moa(
            "Selective κ-Opioid Receptor Agonist",
            "A structurally unique non-nitrogenous terpenoid that acts as a highly potent and selective agonist at κ-opioid receptors (KOR). Unlike virtually all other psychoactive compounds, has no significant activity at serotonin 5-HT2A receptors. KOR activation in the claustrum and prefrontal cortex produces intensely dissociative and hallucinatory effects. The most potent naturally occurring psychoactive compound by weight.",
            [b("κ-opioid (KOR)", .agonist, .primary)],
            [pw, db])
        d["memantine"] = moa(
            "Low-Affinity NMDA Receptor Antagonist (Neuroprotective)",
            "Acts as a low-affinity, uncompetitive NMDA receptor antagonist with rapid on/off kinetics. At therapeutic concentrations, preferentially blocks pathologically activated (tonically open) NMDA receptors while preserving normal phasic (synaptic) NMDA signaling. This selectivity reduces excitotoxic neuronal damage in Alzheimer's disease without producing the dissociative effects seen with higher-affinity NMDA antagonists like ketamine.",
            [b("NMDA", .antagonist, .primary)],
            [gg, stahl])
        d["ibogaine"] = moa(
            "Multimodal Psychoactive Alkaloid",
            "Acts on multiple neurotransmitter systems simultaneously: NMDA receptor antagonist, κ-opioid receptor agonist, σ-receptor agonist, and serotonin transporter inhibitor. Also interacts with nicotinic acetylcholine receptors. Its active metabolite noribogaine has prolonged μ-opioid receptor activity. The complex pharmacological profile may reduce opioid withdrawal and craving, but carries significant cardiac risk via hERG potassium channel inhibition.",
            [b("NMDA", .antagonist, .primary), b("κ-opioid", .agonist, .significant),
             b("Sigma", .agonist, .significant), b("SERT", .reuptakeInhibitor, .significant),
             b("nAChR", .antagonist, .weak), b("hERG", .channelBlocker, .weak)],
            [pw, db])

        // ── Depressants ───────────────────────────────────────────
        d["ethanol"] = moa(
            "Non-Selective CNS Depressant (GABAergic/Anti-Glutamatergic)",
            "Produces CNS depression through multiple mechanisms: positive allosteric modulation of GABA-A receptors, inhibition of NMDA glutamate receptors, enhancement of glycine receptor function, inhibition of voltage-gated calcium channels, and potentiation of 5-HT3 receptors. Acute exposure increases dopamine release in the mesolimbic pathway. Chronic use leads to GABA-A downregulation and NMDA receptor upregulation, causing excitotoxic withdrawal.",
            [b("GABA-A", .positiveAllostericModulator, .primary), b("NMDA", .antagonist, .primary),
             b("Glycine", .modulator, .significant), b("5-HT3", .modulator, .significant)],
            [gg, katzung])
        d["alcohol"] = moa(
            "Non-Selective CNS Depressant (GABAergic/Anti-Glutamatergic)",
            "Produces CNS depression through multiple mechanisms: positive allosteric modulation of GABA-A receptors, inhibition of NMDA glutamate receptors, enhancement of glycine receptor function, inhibition of voltage-gated calcium channels, and potentiation of 5-HT3 receptors. Acute exposure increases dopamine release in the mesolimbic pathway. Chronic use leads to GABA-A downregulation and NMDA receptor upregulation, causing excitotoxic withdrawal.",
            [b("GABA-A", .positiveAllostericModulator, .primary), b("NMDA", .antagonist, .primary),
             b("Glycine", .modulator, .significant), b("5-HT3", .modulator, .significant)],
            [gg, katzung])
        d["ghb"] = moa(
            "GHB Receptor and GABA-B Receptor Agonist",
            "Acts as an agonist at the GHB receptor (Gi/Go-coupled) and at GABA-B receptors. At lower concentrations, GHB receptor activation modulates dopamine and glutamate release. At higher concentrations, GABA-B agonism predominates, producing sedation and anesthesia. GHB is an endogenous substance in the human brain, synthesized from GABA. Its steep dose-response curve makes it particularly dangerous.",
            [b("GHB receptor", .agonist, .primary), b("GABA-B", .agonist, .primary)],
            [gg, pw])
        d["gbl"] = moa(
            "Prodrug → GHB (GABA-B Agonist)",
            "A prodrug that is rapidly converted to GHB (gamma-hydroxybutyrate) by peripheral lactonases. Once converted, acts as an agonist at GHB receptors and GABA-B receptors. Has faster onset than GHB due to rapid absorption and conversion. Carries the same steep dose-response curve and overdose risks as GHB.",
            [b("GHB receptor", .agonist, .primary), b("GABA-B", .agonist, .primary)],
            [gg, pw])
        d["1,4-butanediol"] = moa(
            "Prodrug → GHB (GABA-B Agonist)",
            "A prodrug converted to GHB via alcohol dehydrogenase and aldehyde dehydrogenase. Once converted, acts on GHB and GABA-B receptors. Onset and duration depend on hepatic enzyme activity. Co-administration with ethanol competitively inhibits conversion, unpredictably altering pharmacokinetics.",
            [b("GHB receptor", .agonist, .primary), b("GABA-B", .agonist, .primary)],
            [gg, pw])
        d["phenibut"] = moa(
            "GABA-B Receptor Agonist and α2δ Calcium Channel Ligand",
            "A synthetic phenyl derivative of GABA that crosses the blood-brain barrier, unlike GABA itself. Primarily acts as a GABA-B receptor agonist, producing anxiolytic and sedative effects. Also binds the α2δ subunit of voltage-gated calcium channels, similar to gabapentin, reducing excitatory neurotransmitter release. At high doses, may weakly activate GABA-A receptors.",
            [b("GABA-B", .agonist, .primary), b("α2δ VGCC", .channelBlocker, .significant)],
            [db, pw])
        d["baclofen"] = moa(
            "Selective GABA-B Receptor Agonist",
            "Selectively activates GABA-B receptors, which are G-protein coupled receptors that inhibit neuronal excitability by activating potassium channels and inhibiting calcium channels. Produces muscle relaxation by reducing excitatory neurotransmitter release at spinal motor neurons. Unlike benzodiazepines and barbiturates, does not act on GABA-A receptors.",
            [b("GABA-B", .agonist, .primary)],
            [gg, katzung])

        // ── Cannabinoids ──────────────────────────────────────────
        d["thc"] = moa(
            "Cannabinoid CB1 Partial Agonist",
            "Acts as a partial agonist at cannabinoid CB1 receptors in the central nervous system, mimicking the endogenous cannabinoid anandamide. CB1 receptors are presynaptic on GABAergic and glutamatergic neurons; their activation reduces neurotransmitter release via retrograde signaling. This modulates synaptic plasticity, pain perception, appetite, memory consolidation, and motor coordination. Also weakly activates CB2 receptors.",
            [b("CB1", .partialAgonist, .primary), b("CB2", .agonist, .weak)],
            [gg, katzung])
        d["delta-9-thc"] = moa(
            "Cannabinoid CB1 Partial Agonist",
            "Acts as a partial agonist at cannabinoid CB1 receptors in the central nervous system, mimicking the endogenous cannabinoid anandamide. Reduces neurotransmitter release via retrograde signaling at presynaptic CB1 receptors on GABAergic and glutamatergic neurons.",
            [b("CB1", .partialAgonist, .primary), b("CB2", .agonist, .weak)],
            [gg, katzung])
        d["delta-8-thc"] = moa(
            "Cannabinoid CB1 Partial Agonist (Lower Potency)",
            "A positional isomer of Δ9-THC with the double bond at the 8th carbon position. Acts as a partial agonist at CB1 receptors with approximately 50-75% the potency of Δ9-THC. Produces similar but milder psychoactive effects including euphoria, relaxation, and altered perception.",
            [b("CB1", .partialAgonist, .primary), b("CB2", .agonist, .weak)],
            [db, pw])
        d["cbd"] = moa(
            "Multimodal Modulator (Non-Intoxicating Cannabinoid)",
            "Does not directly activate CB1 or CB2 receptors at physiological concentrations. Acts as a negative allosteric modulator of CB1, reducing the efficacy of agonists like THC. Activates 5-HT1A receptors (anxiolytic), TRPV1 vanilloid receptors (analgesic), and PPARγ nuclear receptors (anti-inflammatory). Inhibits fatty acid amide hydrolase (FAAH), increasing endogenous anandamide levels. Also antagonizes GPR55.",
            [b("CB1", .negativeAllostericModulator, .significant), b("5-HT1A", .agonist, .significant),
             b("TRPV1", .agonist, .significant), b("PPARγ", .agonist, .significant), b("FAAH", .enzymeInhibitor, .significant)],
            [gg, katzung])
        d["cannabidiol"] = moa(
            "Multimodal Modulator (Non-Intoxicating Cannabinoid)",
            "Does not directly activate CB1 or CB2 receptors at physiological concentrations. Acts as a negative allosteric modulator of CB1, reducing the efficacy of agonists like THC. Activates 5-HT1A receptors (anxiolytic), TRPV1 vanilloid receptors (analgesic), and PPARγ nuclear receptors (anti-inflammatory). Inhibits fatty acid amide hydrolase (FAAH), increasing endogenous anandamide levels.",
            [b("CB1", .negativeAllostericModulator, .significant), b("5-HT1A", .agonist, .significant),
             b("TRPV1", .agonist, .significant), b("PPARγ", .agonist, .significant), b("FAAH", .enzymeInhibitor, .significant)],
            [gg, katzung])
        for n in ["nabilone", "dronabinol"] { d[n] = cannabinoidAgonist }
        d["jwh-018"] = cannabinoidAgonist

        // ── Gabapentinoids ─────────────────────────────────────────
        for n in ["gabapentin", "pregabalin"] { d[n] = gabapentinoid }

        // ── Mood Stabilizers ──────────────────────────────────────
        d["lithium"] = moa(
            "Mood Stabilizer with Multiple Intracellular Mechanisms",
            "Exact mechanism incompletely understood. Inhibits inositol monophosphatase (IMPase), depleting inositol and modulating phosphoinositide signaling. Inhibits glycogen synthase kinase-3β (GSK-3β), regulating neuroplasticity, circadian rhythm, and neuroprotection. Modulates glutamate neurotransmission by reducing NMDA receptor activity. Also affects protein kinase C, cAMP, and arachidonic acid metabolism.",
            [b("IMPase", .enzymeInhibitor, .primary), b("GSK-3β", .enzymeInhibitor, .primary), b("NMDA", .modulator, .significant)],
            [stahl, gg])
        d["valproic acid"] = moa(
            "Multimodal Anticonvulsant and Mood Stabilizer",
            "Acts through multiple mechanisms: increases GABA levels by inhibiting GABA transaminase and enhancing GABA synthesis. Blocks voltage-gated sodium channels, reducing repetitive neuronal firing. Inhibits T-type calcium channels in thalamic neurons. Also inhibits histone deacetylases (HDACs), modifying gene expression, which may contribute to neuroprotective and mood-stabilizing effects.",
            [b("GABA transaminase", .enzymeInhibitor, .primary), b("Na⁺ channels", .channelBlocker, .primary),
             b("T-type Ca²⁺ channels", .channelBlocker, .significant), b("HDACs", .enzymeInhibitor, .significant)],
            [gg, stahl])
        d["valproate"] = moa(
            "Multimodal Anticonvulsant and Mood Stabilizer",
            "Acts through multiple mechanisms: increases GABA levels by inhibiting GABA transaminase and enhancing GABA synthesis. Blocks voltage-gated sodium channels, reducing repetitive neuronal firing. Inhibits T-type calcium channels in thalamic neurons. Also inhibits histone deacetylases (HDACs).",
            [b("GABA transaminase", .enzymeInhibitor, .primary), b("Na⁺ channels", .channelBlocker, .primary),
             b("T-type Ca²⁺ channels", .channelBlocker, .significant), b("HDACs", .enzymeInhibitor, .significant)],
            [gg, stahl])
        d["lamotrigine"] = moa(
            "Voltage-Gated Sodium Channel Blocker and Glutamate Release Inhibitor",
            "Stabilizes neuronal membranes by blocking voltage-gated sodium channels in their inactivated state, reducing sustained repetitive firing. Preferentially reduces glutamate release rather than GABA release, distinguishing it from other sodium channel blockers and potentially accounting for its mood-stabilizing properties, particularly in preventing depressive episodes in bipolar disorder.",
            [b("Na⁺ channels", .channelBlocker, .primary), b("Glutamate release", .modulator, .significant)],
            [gg, stahl])
        d["carbamazepine"] = moa(
            "Voltage-Gated Sodium Channel Blocker",
            "Primarily blocks voltage-gated sodium channels by binding to the inactivated state, reducing sustained repetitive neuronal firing and limiting seizure spread. Also reduces glutamate release secondary to sodium channel blockade. Has additional effects on adenosine receptors and voltage-gated calcium channels. Its active metabolite carbamazepine-10,11-epoxide contributes to both therapeutic and adverse effects.",
            [b("Na⁺ channels", .channelBlocker, .primary)],
            [gg, katzung])
        d["oxcarbazepine"] = moa(
            "Voltage-Gated Sodium Channel Blocker",
            "A structural derivative of carbamazepine that blocks voltage-gated sodium channels in their inactivated state. Rapidly converted to its active metabolite licarbazepine (MHD). Compared to carbamazepine, has a more favorable side effect profile and fewer drug interactions due to reduced hepatic enzyme induction.",
            [b("Na⁺ channels", .channelBlocker, .primary)],
            [gg, katzung])
        d["topiramate"] = moa(
            "Multimodal Anticonvulsant",
            "Acts through multiple mechanisms: blocks voltage-gated sodium channels, enhances GABA activity at GABA-A receptors, antagonizes AMPA/kainate glutamate receptors, and inhibits carbonic anhydrase (isoenzymes II and IV). This combination of GABAergic enhancement and glutamatergic reduction provides broad-spectrum anticonvulsant activity. The carbonic anhydrase inhibition contributes to appetite suppression and metabolic acidosis.",
            [b("Na⁺ channels", .channelBlocker, .primary), b("GABA-A", .positiveAllostericModulator, .significant),
             b("AMPA/kainate", .antagonist, .significant), b("Carbonic anhydrase", .enzymeInhibitor, .significant)],
            [gg, katzung])

        // ── Analgesics / NSAIDs ───────────────────────────────────
        for n in ["ibuprofen", "naproxen", "diclofenac"] { d[n] = nsaid }
        for n in ["indomethacin", "piroxicam", "meloxicam"] { d[n] = nsaid }
        for n in ["ketorolac", "mefenamic acid"] { d[n] = nsaid }
        d["celecoxib"] = moa(
            "Selective COX-2 Inhibitor",
            "Selectively inhibits cyclooxygenase-2 (COX-2), the inducible isoform upregulated during inflammation, while relatively sparing constitutive COX-1 in the gastric mucosa and platelets. This selectivity reduces gastrointestinal bleeding risk compared to non-selective NSAIDs but does not provide antiplatelet effects. COX-2 selectivity may increase cardiovascular thromboembolic risk.",
            [b("COX-2", .enzymeInhibitor, .primary)],
            [gg, katzung])
        d["acetaminophen"] = moa(
            "Centrally-Acting Analgesic and Antipyretic",
            "Mechanism incompletely understood despite widespread use. Weakly inhibits COX peripherally but primarily acts centrally. Its active metabolite AM404 inhibits endocannabinoid reuptake, increasing anandamide levels and activating CB1 and TRPV1 receptors. Also inhibits prostaglandin synthesis in the CNS, producing antipyretic effects via the hypothalamus. Lacks significant anti-inflammatory activity.",
            [b("Endocannabinoid (AM404)", .modulator, .primary), b("COX (central)", .enzymeInhibitor, .weak), b("TRPV1", .agonist, .significant)],
            [gg, katzung])
        d["paracetamol"] = moa(
            "Centrally-Acting Analgesic and Antipyretic",
            "Mechanism incompletely understood. Weakly inhibits COX peripherally but primarily acts centrally. Its active metabolite AM404 inhibits endocannabinoid reuptake, increasing anandamide levels and activating CB1 and TRPV1 receptors. Also inhibits prostaglandin synthesis in the CNS. Lacks significant anti-inflammatory activity.",
            [b("Endocannabinoid (AM404)", .modulator, .primary), b("COX (central)", .enzymeInhibitor, .weak), b("TRPV1", .agonist, .significant)],
            [gg, katzung])
        d["aspirin"] = moa(
            "Irreversible Cyclooxygenase (COX) Inhibitor",
            "Irreversibly inhibits cyclooxygenase enzymes by acetylating a serine residue in the active site. COX-1 inhibition in platelets prevents thromboxane A2 synthesis, irreversibly blocking platelet aggregation for the platelet's lifetime (7–10 days). COX-2 inhibition reduces prostaglandin synthesis, providing anti-inflammatory, analgesic, and antipyretic effects. The irreversible nature of inhibition is pharmacologically unique among NSAIDs.",
            [b("COX-1", .enzymeInhibitor, .primary), b("COX-2", .enzymeInhibitor, .primary)],
            [gg, katzung])

        // ── Antihistamines ────────────────────────────────────────
        for n in ["diphenhydramine", "hydroxyzine"] { d[n] = antihistamine1 }
        for n in ["doxylamine", "chlorpheniramine"] { d[n] = antihistamine1 }
        for n in ["promethazine", "cyproheptadine"] { d[n] = antihistamine1 }
        for n in ["brompheniramine", "clemastine"] { d[n] = antihistamine1 }
        for n in ["meclizine", "dimenhydrinate"] { d[n] = antihistamine1 }
        for n in ["cetirizine", "loratadine"] { d[n] = antihistamine2 }
        for n in ["fexofenadine", "levocetirizine"] { d[n] = antihistamine2 }
        d["desloratadine"] = antihistamine2

        // ── Beta-Blockers ─────────────────────────────────────────
        for n in ["propranolol", "metoprolol"] { d[n] = betaBlocker }
        for n in ["atenolol", "bisoprolol"] { d[n] = betaBlocker }
        for n in ["nadolol", "timolol"] { d[n] = betaBlocker }
        for n in ["nebivolol", "labetalol"] { d[n] = betaBlocker }
        d["carvedilol"] = moa(
            "Non-Selective β-Blocker with α1 Antagonism and Antioxidant Properties",
            "Blocks β1, β2, and α1-adrenergic receptors, providing combined vasodilation and cardiac output reduction. The α1 blockade produces direct arterial vasodilation, distinguishing it from pure β-blockers. Also has antioxidant and anti-proliferative properties that may provide additional cardiovascular protection beyond blood pressure lowering.",
            [b("β1", .antagonist, .primary), b("β2", .antagonist, .primary), b("α1", .antagonist, .significant)],
            [gg, katzung])

        // ── ACE Inhibitors ────────────────────────────────────────
        for n in ["lisinopril", "enalapril"] { d[n] = aceInhibitor }
        for n in ["ramipril", "captopril"] { d[n] = aceInhibitor }
        for n in ["benazepril", "fosinopril"] { d[n] = aceInhibitor }
        for n in ["quinapril", "perindopril"] { d[n] = aceInhibitor }

        // ── ARBs ──────────────────────────────────────────────────
        for n in ["losartan", "valsartan", "irbesartan"] { d[n] = arb }
        for n in ["candesartan", "olmesartan", "telmisartan"] { d[n] = arb }

        // ── Calcium Channel Blockers ──────────────────────────────
        for n in ["amlodipine", "nifedipine", "felodipine"] { d[n] = ccb }

        // ── Other Cardiovascular ──────────────────────────────────
        d["clonidine"] = moa(
            "α2-Adrenergic Receptor Agonist",
            "Activates presynaptic α2-adrenergic receptors in the locus coeruleus and brainstem, reducing norepinephrine release and sympathetic outflow. Decreases heart rate, blood pressure, and peripheral vascular resistance. In opioid and alcohol withdrawal, reduces the noradrenergic hyperactivity responsible for anxiety, tachycardia, and diaphoresis. Also has activity at imidazoline I1 receptors.",
            [b("α2-adrenergic", .agonist, .primary)],
            [gg, katzung])
        d["sildenafil"] = moa(
            "Phosphodiesterase Type 5 (PDE5) Inhibitor",
            "Selectively inhibits phosphodiesterase type 5 (PDE5), preventing degradation of cyclic GMP (cGMP) in smooth muscle cells. In the corpus cavernosum, sexual stimulation releases nitric oxide, which increases cGMP, causing smooth muscle relaxation and increased blood flow. By preventing cGMP breakdown, sildenafil enhances and prolongs the erectile response. Also used for pulmonary arterial hypertension via the same mechanism.",
            [b("PDE5", .enzymeInhibitor, .primary)],
            [gg, katzung])
        d["tadalafil"] = moa(
            "Phosphodiesterase Type 5 (PDE5) Inhibitor",
            "Selectively inhibits PDE5, preventing degradation of cGMP in smooth muscle. Has a significantly longer half-life than sildenafil (17.5 hours vs. 4 hours), allowing for daily dosing and a wider window of efficacy. Also slightly inhibits PDE11, though the clinical significance is unclear.",
            [b("PDE5", .enzymeInhibitor, .primary)],
            [gg, katzung])
        d["warfarin"] = moa(
            "Vitamin K Epoxide Reductase Inhibitor (Anticoagulant)",
            "Inhibits vitamin K epoxide reductase (VKORC1), preventing the recycling of vitamin K to its active reduced form. Vitamin K is essential for the post-translational carboxylation of clotting factors II, VII, IX, and X, as well as proteins C and S. Onset of anticoagulant effect is delayed (3–5 days) until existing clotting factors are cleared.",
            [b("VKORC1", .enzymeInhibitor, .primary)],
            [gg, katzung])

        // ── NSAIDs done above ─────────────────────────────────────

        // ── PPIs ──────────────────────────────────────────────────
        for n in ["omeprazole", "esomeprazole", "lansoprazole"] { d[n] = ppi }
        for n in ["pantoprazole", "rabeprazole", "dexlansoprazole"] { d[n] = ppi }

        // ── GI Agents ─────────────────────────────────────────────
        d["ondansetron"] = moa(
            "Serotonin 5-HT3 Receptor Antagonist (Antiemetic)",
            "Selectively antagonizes serotonin 5-HT3 receptors, which are ligand-gated ion channels located on vagal afferents in the GI tract and in the chemoreceptor trigger zone (area postrema). Blocking 5-HT3 activation by serotonin released from enterochromaffin cells prevents the initiation of the vomiting reflex. Does not affect dopamine, histamine, or muscarinic receptors.",
            [b("5-HT3", .antagonist, .primary)],
            [gg, katzung])

        // ── Statins ───────────────────────────────────────────────
        for n in ["atorvastatin", "rosuvastatin"] { d[n] = statin }
        for n in ["simvastatin", "pravastatin"] { d[n] = statin }
        for n in ["lovastatin", "fluvastatin"] { d[n] = statin }

        // ── Triptans ──────────────────────────────────────────────
        for n in ["sumatriptan", "rizatriptan"] { d[n] = triptan }
        for n in ["zolmitriptan", "eletriptan"] { d[n] = triptan }
        for n in ["naratriptan", "almotriptan"] { d[n] = triptan }

        // ── Corticosteroids ───────────────────────────────────────
        for n in ["prednisone", "prednisolone"] { d[n] = corticosteroid }
        for n in ["dexamethasone", "hydrocortisone"] { d[n] = corticosteroid }
        for n in ["methylprednisolone", "budesonide"] { d[n] = corticosteroid }

        // ── Antibiotics ───────────────────────────────────────────
        for n in ["ciprofloxacin", "levofloxacin"] { d[n] = fluoroquinolone }
        d["moxifloxacin"] = fluoroquinolone
        d["amoxicillin"] = moa(
            "β-Lactam Antibiotic (Cell Wall Synthesis Inhibitor)",
            "Binds to penicillin-binding proteins (PBPs) on the bacterial cell membrane, inhibiting transpeptidation — the final step in bacterial cell wall (peptidoglycan) synthesis. This weakens the cell wall, leading to osmotic lysis and bacterial death. Bactericidal against susceptible organisms. Inactivated by bacterial β-lactamase enzymes (overcome by combining with clavulanate).",
            [b("PBPs", .enzymeInhibitor, .primary)],
            [gg, katzung])
        d["azithromycin"] = moa(
            "Macrolide Antibiotic (Protein Synthesis Inhibitor)",
            "Binds to the 50S ribosomal subunit of bacterial ribosomes, inhibiting translocation of peptidyl-tRNA and blocking protein synthesis. Bacteriostatic at typical concentrations. Has a very long tissue half-life and accumulates in phagocytes, which transport it to sites of infection. Also has anti-inflammatory and immunomodulatory properties.",
            [b("50S ribosome", .modulator, .primary)],
            [gg, katzung])

        // ── Endocrine ─────────────────────────────────────────────
        d["levothyroxine"] = moa(
            "Thyroid Hormone Replacement (T4)",
            "Synthetic thyroxine (T4) that is converted to the active triiodothyronine (T3) by deiodinase enzymes in peripheral tissues. T3 binds to nuclear thyroid hormone receptors, modulating gene transcription to increase basal metabolic rate, cardiac output, oxygen consumption, and protein synthesis. Replaces deficient endogenous thyroid hormone in hypothyroidism.",
            [b("Thyroid hormone receptors", .agonist, .primary)],
            [gg, katzung])
        d["metformin"] = moa(
            "AMP-Activated Protein Kinase (AMPK) Activator",
            "Exact mechanism not fully established. Activates AMP-activated protein kinase (AMPK), which inhibits hepatic gluconeogenesis and increases insulin sensitivity in peripheral tissues. Also inhibits mitochondrial complex I, altering the cellular energy state. Does not stimulate insulin secretion and does not cause hypoglycemia when used alone. May also modulate the gut microbiome and increase GLP-1 levels.",
            [b("AMPK", .modulator, .primary), b("Mitochondrial complex I", .enzymeInhibitor, .significant)],
            [gg, katzung])

        // ── Supplements & Nootropics ──────────────────────────────
        d["melatonin"] = moa(
            "Melatonin MT1/MT2 Receptor Agonist",
            "Activates melatonin MT1 and MT2 receptors in the suprachiasmatic nucleus (SCN), the master circadian clock. MT1 activation suppresses SCN neuronal firing, promoting sleep onset. MT2 activation shifts the circadian phase, entraining the sleep-wake cycle. Endogenous melatonin is produced by the pineal gland in response to darkness; exogenous melatonin mimics this signal.",
            [b("MT1", .agonist, .primary), b("MT2", .agonist, .primary)],
            [gg, katzung])
        d["l-theanine"] = moa(
            "Glutamate Analogue with GABAergic and Serotonergic Effects",
            "An amino acid analogue of glutamate found in tea leaves. Crosses the blood-brain barrier and increases brain levels of GABA, serotonin, and dopamine. May antagonize glutamate at AMPA receptors and modulate α-wave brain activity. Promotes relaxation without sedation, and may attenuate the anxiogenic effects of caffeine when co-administered.",
            [b("GABA", .modulator, .significant), b("AMPA", .antagonist, .significant),
             b("Serotonin", .modulator, .weak), b("Dopamine", .modulator, .weak)],
            [db])
        d["5-htp"] = moa(
            "Serotonin Precursor",
            "The immediate biosynthetic precursor to serotonin (5-HT). Crosses the blood-brain barrier and is converted to serotonin by aromatic L-amino acid decarboxylase (AADC). Unlike tryptophan, bypasses the rate-limiting tryptophan hydroxylase step. Increases central serotonin synthesis. Should not be combined with serotonergic medications due to serotonin syndrome risk.",
            [b("Serotonin synthesis", .modulator, .primary)],
            [db])
        for n in ["piracetam", "aniracetam"] { d[n] = racetam }
        for n in ["oxiracetam", "pramiracetam"] { d[n] = racetam }
        for n in ["phenylpiracetam", "coluracetam"] { d[n] = racetam }
        d["fasoracetam"] = racetam
        d["noopept"] = moa(
            "Neuropeptide-Derived Cognitive Enhancer",
            "A dipeptide nootropic structurally related to racetams but with distinct pharmacology. Modulates AMPA and NMDA glutamate receptors, enhancing long-term potentiation (LTP) and synaptic plasticity. Increases expression of brain-derived neurotrophic factor (BDNF) and nerve growth factor (NGF). Active at much lower doses than piracetam, suggesting additional mechanisms beyond glutamatergic modulation.",
            [b("AMPA", .modulator, .primary), b("NMDA", .modulator, .primary),
             b("BDNF", .modulator, .significant), b("NGF", .modulator, .significant)],
            [db, pw])
        d["alpha-gpc"] = moa(
            "Cholinergic Precursor",
            "A phospholipid that serves as a precursor to acetylcholine. Crosses the blood-brain barrier and increases acetylcholine synthesis and release in the brain. Also provides glycerophosphate for membrane phospholipid synthesis. Enhances cholinergic neurotransmission, which is involved in memory formation, attention, and learning.",
            [b("ACh synthesis", .modulator, .primary)],
            [db])
        d["cdp-choline"] = moa(
            "Cholinergic Precursor and Membrane Phospholipid Source",
            "An endogenous intermediate in phosphatidylcholine synthesis. Provides both choline (for acetylcholine synthesis) and cytidine (converted to uridine, which supports synaptic membrane formation). Enhances dopamine receptor density and dopamine release in addition to cholinergic effects. Supports neuronal membrane integrity and repair.",
            [b("ACh synthesis", .modulator, .primary), b("Dopamine", .modulator, .weak)],
            [db])
        d["st. john's wort"] = moa(
            "Multimodal Monoamine Modulator",
            "Contains multiple active constituents including hypericin and hyperforin. Hyperforin inhibits the reuptake of serotonin, norepinephrine, dopamine, GABA, and glutamate by activating TRPC6 ion channels, which increase intracellular sodium and reduce transporter function. Also weakly inhibits MAO-A. Potent inducer of CYP3A4, causing clinically significant drug interactions with many medications.",
            [b("SERT", .reuptakeInhibitor, .primary), b("NET", .reuptakeInhibitor, .primary),
             b("DAT", .reuptakeInhibitor, .significant), b("TRPC6", .agonist, .significant)],
            [stahl, gg])

        // ── Racetams done above ───────────────────────────────────

        // ── Respiratory ───────────────────────────────────────────
        d["albuterol"] = moa(
            "β2-Adrenergic Receptor Agonist (Short-Acting Bronchodilator)",
            "Selectively activates β2-adrenergic receptors on airway smooth muscle cells, stimulating adenylyl cyclase and increasing intracellular cAMP. This activates protein kinase A, which phosphorylates and inactivates myosin light chain kinase, causing smooth muscle relaxation and bronchodilation. Provides rapid relief of acute bronchospasm (onset 5–15 minutes).",
            [b("β2-adrenergic", .agonist, .primary)],
            [gg, katzung])
        d["salbutamol"] = moa(
            "β2-Adrenergic Receptor Agonist (Short-Acting Bronchodilator)",
            "Selectively activates β2-adrenergic receptors on airway smooth muscle, stimulating adenylyl cyclase and increasing cAMP. This relaxes bronchial smooth muscle and provides rapid bronchodilation. Also inhibits mast cell degranulation and stimulates mucociliary clearance.",
            [b("β2-adrenergic", .agonist, .primary)],
            [gg, katzung])
        d["montelukast"] = moa(
            "Leukotriene Receptor Antagonist",
            "Selectively antagonizes the cysteinyl leukotriene receptor CysLT1, blocking the bronchoconstrictive and pro-inflammatory effects of leukotrienes C4, D4, and E4. Leukotrienes are potent inflammatory mediators released by mast cells, eosinophils, and other immune cells. Reduces bronchospasm, mucus secretion, and eosinophilic inflammation in asthma.",
            [b("CysLT1", .antagonist, .primary)],
            [gg, katzung])

        // ── Fluoroquinolones done above ───────────────────────────

        // ── Other ─────────────────────────────────────────────────
        d["dextroamphetamine"] = amphetamine
        d["methaqualone"] = moa(
            "GABA-A Positive Allosteric Modulator (Quinazolinone)",
            "Acts as a positive allosteric modulator of GABA-A receptors at a binding site distinct from both benzodiazepines and barbiturates. Enhances GABAergic inhibition, producing sedative, hypnotic, anxiolytic, and muscle relaxant effects. Also has weak inhibitory effects on voltage-gated sodium channels.",
            [b("GABA-A", .positiveAllostericModulator, .primary)],
            [gg, pw])
        d["carisoprodol"] = moa(
            "GABA-A Modulator (via Meprobamate Metabolite)",
            "A prodrug that is partially metabolized to meprobamate, which acts as a positive allosteric modulator at GABA-A receptors. The parent compound may also directly modulate GABA-A receptors and other targets. Produces muscle relaxation, sedation, and anxiolysis. The meprobamate metabolite has a long half-life and contributes to dependence potential.",
            [b("GABA-A", .positiveAllostericModulator, .primary)],
            [gg, katzung])
        return d
    }()
    // swiftlint:enable function_body_length
}
