import Foundation

/// The sentence Piru shows for a class-pair interaction rule, in the reader's
/// language.
///
/// The rule itself — which two ``DrugClass`` values interact, and how badly — is
/// data and lives in the bundled database's `interaction_rules`. The sentence is
/// copy: written in the app's voice, and shipped in every language the app ships
/// in, which a database row cannot be. Keeping it here is what stops a data
/// rebuild from putting an untranslated sentence in front of a reader.
///
/// A pair with no entry renders the row's own English note instead. That is not
/// a gap to fill mechanically — it is how TripSit's rules have always been
/// shown, and it is the honest default for a verdict Piru has not adjudicated
/// itself.
///
/// Every sentence is written the same way: the effect, an em dash, then the
/// elaboration. Compact surfaces show only the part before the dash
/// (``InteractionResult/leadClause``), so that half has to stand alone.
enum InteractionRuleCopy {
    /// The class pair this copy is written against, order-independent — the same
    /// key ``InteractionChecker`` resolves a rule under.
    static func key(_ classA: DrugClass, _ classB: DrugClass) -> String {
        [classA.rawValue, classB.rawValue].sorted().joined(separator: "|")
    }

    /// Piru's own sentence for a pair, or `nil` when it has none.
    static func note(_ classA: DrugClass, _ classB: DrugClass) -> LocalizedStringResource? {
        table[key(classA, classB)]
    }

    /// Keyed by ``key(_:_:)``. Built from ``entries`` so each pair is written as
    /// enum cases the compiler checks rather than as a hand-assembled string.
    static let table: [String: LocalizedStringResource] = Dictionary(
        entries.map { (key($0.0, $0.1), $0.2) },
        uniquingKeysWith: { first, _ in first },
    )

    private static let entries: [(DrugClass, DrugClass, LocalizedStringResource)] = [
        (.opioid, .benzodiazepine, "Combined respiratory depression — the leading cause of overdose death."),
        (.opioid, .ghb, "Severe respiratory depression — both substances suppress breathing."),
        (.opioid, .alcohol, "Respiratory depression and CNS shutdown — potentially fatal combination."),
        (.maoi, .empathogen, "Risk of fatal serotonin syndrome — do not combine."),
        (.maoi, .ssri, "Serotonin syndrome — potentially fatal. Allow 2+ week washout."),
        (.maoi, .snri, "Serotonin syndrome — potentially fatal. Allow 2+ week washout."),
        (.maoi, .tca, "Risk of serotonin syndrome and hypertensive crisis."),
        (.maoi, .stimulant, "Hypertensive crisis — potentially fatal spike in blood pressure."),
        (.maoi, .opioid, "Risk of serotonin syndrome, especially with meperidine/pethidine, tramadol, and tapentadol."),
        (.lithium, .psychedelic, "Of 62 reports of this combination, 47% described a seizure and 39% involved medical attention — against none of 34 reports for lamotrigine. Self-reported, so the rate is not a measured one, but no other pairing shows a signal like it."),
        (.ghb, .alcohol, "Respiratory depression and loss of consciousness — very narrow safety margin."),
        (.ghb, .benzodiazepine, "Severe respiratory depression — both are GABAergic depressants."),
        (.benzodiazepine, .alcohol, "Life-threatening respiratory depression — this combination is a leading cause of overdose death."),
        (.opioid, .gabapentinoid, "Enhanced respiratory depression — gabapentinoids increase opioid overdose risk."),
        (.opioid, .opioid, "Stacking opioids is unpredictable — respiratory depression risk compounds."),
        (.opioid, .antihistamine, "Additive CNS and respiratory depression — antihistamines potentiate opioid sedation."),
        (.opioid, .stimulant, "Stimulants mask overdose signs — when they wear off, respiratory depression can emerge."),
        (.benzodiazepine, .gabapentinoid, "Excessive sedation and respiratory depression risk."),
        (.benzodiazepine, .antihistamine, "Compounded CNS depression — excessive sedation and impaired breathing."),
        (.ssri, .empathogen, "SSRIs usually blunt MDMA — it may feel much weaker, so people often redose into trouble (overheating, heart strain). On their own they don't cause serotonin syndrome."),
        (.snri, .empathogen, "SNRIs usually blunt MDMA — it may feel weaker, so people often redose into trouble (overheating, heart strain). On their own they don't cause serotonin syndrome."),
        (.tca, .empathogen, "TCAs usually blunt MDMA rather than boosting it, so people may redose; the bigger concern is added strain on heart rate and blood pressure."),
        (.dissociative, .alcohol, "Risk of respiratory depression, aspiration, and loss of consciousness."),
        (.dissociative, .benzodiazepine, "Severe respiratory depression and loss of consciousness."),
        (.benzodiazepine, .benzodiazepine, "Stacking benzodiazepines dramatically increases sedation and respiratory depression risk."),
        (.ssri, .snri, "Overlapping serotonin reuptake inhibition — increased serotonin syndrome risk."),
        (.ssri, .tca, "SSRIs inhibit TCA metabolism — risk of TCA toxicity and serotonin syndrome."),
        (.gabapentinoid, .alcohol, "Enhanced CNS depression — risk of respiratory depression and death."),
        (.serotonergic, .empathogen, "Serotonin syndrome risk — these drugs add serotonin on top of an empathogen's surge. Some (tramadol, meperidine) can also trigger seizures."),
        (.serotonergic, .maoi, "Serotonin syndrome — potentially fatal. Do not combine."),
        (.serotonergic, .serotonergic, "Serotonin syndrome risk — two serotonin-raising drugs stacked together."),
        (.serotonergic, .ssri, "Serotonin syndrome risk — a serotonin-raising drug stacked with an SSRI."),
        (.serotonergic, .snri, "Serotonin syndrome risk — a serotonin-raising drug stacked with an SNRI."),
        (.serotonergic, .tca, "Serotonin syndrome risk — a serotonin-raising drug stacked with a tricyclic antidepressant."),
        (.serotonergic, .lithium, "A large serotonin load on top of lithium's own. The lithium label names tramadol and fentanyl in this group; serotonin syndrome can start within hours."),
        (.alpha2Agonist, .opioid, "Heavy sedation with a dangerously slow heart rate and breathing. Naloxone reverses the opioid but NOT the alpha-2 part — give rescue breaths and call for help even after naloxone."),
        (.alpha2Agonist, .alcohol, "Adds up sedation and lowers blood pressure further — expect stronger drowsiness and dizziness. Use less and don't drive."),
        (.alpha2Agonist, .benzodiazepine, "Compounded sedation and low blood pressure — stronger drowsiness and dizziness."),
        (.alpha2Agonist, .gabapentinoid, "Additive sedation and low blood pressure — increased drowsiness and dizziness."),
        (.alpha2Agonist, .tca, "Tricyclics can cancel out clonidine-type blood-pressure lowering, so blood pressure may rise — a medical issue more than an overdose risk."),
        (.betaBlocker, .alpha2Agonist, "Don't stop the clonidine-type drug suddenly while on a beta-blocker — it can spike blood pressure to dangerous levels. Taper it slowly."),
        (.betaBlocker, .stimulant, "The old \u{201C}never mix\u{201D} warning is largely a medical myth — large reviews found no real harm. Both still strain the heart, so it isn't a green light to combine them."),
        (.betaBlocker, .alcohol, "Both can lower blood pressure and add to dizziness — you may feel faint, especially standing up."),
        (.orexinAntagonist, .opioid, "Added drowsiness and next-day grogginess, with more fall and coordination risk. Unlike a benzo, an orexin antagonist doesn't suppress breathing, so this isn't the deadly opioid+benzo combination — but still use less, and don't drive."),
        (.orexinAntagonist, .alcohol, "Alcohol stacks psychomotor and memory impairment on top of the sleep med (and raises lemborexant's blood levels) — expect worse next-day grogginess and unsteadiness. The labels advise against drinking with these."),
        (.orexinAntagonist, .benzodiazepine, "Two sleep-promoting drugs stacked — additive next-day sedation and fall risk, and largely redundant. Not the respiratory danger of benzo+opioid, but heavier grogginess and impaired coordination."),
        (.orexinAntagonist, .gabapentinoid, "Additive sedation and next-day grogginess — more drowsiness, dizziness, and fall risk. Use less and avoid driving."),
        (.orexinAntagonist, .ghb, "Compounded sedation — stronger, deeper drowsiness. The orexin antagonist doesn't add respiratory depression itself, but GHB can, so keep doses low and don't combine when alone."),
        (.orexinAntagonist, .antihistamine, "Both cause drowsiness — expect additive next-day sedation and grogginess. Use less and don't drive."),
        (.dissociative, .opioid, "Respiratory depression risk — dissociatives can mask overdose signs."),
        (.opioid, .antipsychotic, "Additive CNS and respiratory depression."),
        (.lithium, .ssri, "Both raise serotonin, so serotonin syndrome is possible — agitation, tremor, sweating, a racing heart — and most likely in the first weeks. This pairing is prescribed and monitored on purpose; SSRIs do not raise lithium levels."),
        (.lithium, .snri, "Both raise serotonin, so serotonin syndrome is possible — agitation, tremor, sweating, a racing heart — and most likely in the first weeks. This pairing is prescribed and monitored on purpose; SNRIs do not raise lithium levels."),
        (.maoi, .dissociative, "Serotonin syndrome risk — especially with DXM and other serotonergic dissociatives."),
        (.barbiturate, .opioid, "Combined respiratory depression with no ceiling — barbiturates deepen an opioid's suppression of breathing until it stops."),
        (.barbiturate, .benzodiazepine, "Life-threatening respiratory depression. A barbiturate opens the GABA-A channel directly rather than modulating it, so this stacks past the point where benzodiazepines alone level off."),
        (.barbiturate, .alcohol, "Life-threatening respiratory depression and loss of consciousness — the classic fatal combination."),
        (.barbiturate, .ghb, "Severe respiratory depression — two direct-acting depressants with no shared ceiling."),
        (.barbiturate, .barbiturate, "Doses add with no plateau, and the gap between a sedating dose and a fatal one is narrow to begin with."),
        (.barbiturate, .gabapentinoid, "Additive sedation and respiratory depression."),
        (.barbiturate, .antihistamine, "Heavy additive sedation — deep drowsiness and impaired breathing."),
        (.barbiturate, .dissociative, "Additive CNS and respiratory depression, with a raised risk of vomiting while unresponsive."),
        (.barbiturate, .alpha2Agonist, "Additive sedation, low blood pressure, and slow heart rate."),
        (.barbiturate, .orexinAntagonist, "Additive sedation and next-day impairment."),
        (.barbiturate, .cannabinoid, "Additive sedation, dizziness, and slowed reaction time."),
        (.barbiturate, .antipsychotic, "Additive CNS depression — increased sedation and impairment."),
        (.stimulant, .stimulant, "Cardiovascular strain — combined stimulants increase heart rate and blood pressure."),
        (.stimulant, .psychedelic, "Increased anxiety and vasoconstriction — stimulants can intensify difficult trips."),
        (.cannabinoid, .psychedelic, "Unpredictable intensification — cannabis can trigger anxiety or thought loops."),
        (.ssri, .psychedelic, "SSRIs typically reduce psychedelic effects but may increase risk with some compounds."),
        (.ssri, .ssri, "Serotonin accumulation risk — combining serotonergic agents increases toxicity chance."),
        (.stimulant, .dissociative, "Increased heart rate and blood pressure — cardiovascular strain."),
        (.alcohol, .stimulant, "Stimulants mask alcohol impairment — risk of overconsumption."),
        (.alcohol, .antihistamine, "Compounded drowsiness and impaired coordination."),
        (.alcohol, .antipsychotic, "Additive CNS depression — increased sedation and impairment."),
        (.gabapentinoid, .gabapentinoid, "Stacking gabapentinoids compounds sedation and respiratory depression risk."),
        (.dissociative, .dissociative, "Compounded dissociation — disorientation and loss of motor control."),
        (.empathogen, .empathogen, "Serotonin depletion and neurotoxicity risk — allow adequate recovery between uses."),
        (.lithium, .empathogen, "MDMA releases serotonin in bulk and lithium adds to it, so serotonin syndrome is the main risk. Seizures are reported for lithium with classic psychedelics; MDMA has not been looked at the same way."),
        (.lithium, .maoi, "MAOIs block the enzyme that clears serotonin, so the load builds instead of levelling off. Serotonin syndrome is the risk; MAOIs do not raise lithium levels."),
        (.stimulant, .ssri, "Some combinations increase serotonin or seizure risk — monitor for symptoms."),
        (.stimulant, .snri, "Cardiovascular strain and serotonin risk — watch your heart rate and blood pressure."),
        (.antipsychotic, .antipsychotic, "Combined QTc prolongation risk — monitor cardiac rhythm."),
        (.gabapentinoid, .antihistamine, "Additive CNS depression — increased sedation and impaired coordination."),
        (.cannabinoid, .benzodiazepine, "Additive sedation — may increase drowsiness and impaired coordination."),
        (.cannabinoid, .opioid, "Additive CNS depression — may increase sedation and respiratory depression risk."),
        (.cannabinoid, .alcohol, "Additive impairment — increased dizziness, drowsiness, and slowed reaction time."),
    ]
}
