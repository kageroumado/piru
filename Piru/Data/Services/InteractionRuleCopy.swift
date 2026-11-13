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
/// A pair with no entry renders the row's own English note instead, which is
/// how an unadjudicated TripSit row would reach the reader. Every row in the
/// bundled database has an entry, and `InteractionCheckerTests` fails on one
/// that does not: a new TripSit pair needs a verdict and a sentence written for
/// it, never its note copied in.
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
        (.opioid, .benzodiazepine, "Combined respiratory depression. The leading cause of overdose death."),
        (.opioid, .ghb, "Severe respiratory depression. Both substances suppress breathing."),
        (.opioid, .alcohol, "Respiratory depression and CNS shutdown. A potentially fatal combination."),
        (.maoi, .empathogen, "Risk of fatal serotonin syndrome. MAOIs block the enzyme that clears the serotonin an empathogen releases."),
        (.maoi, .ssri, "Serotonin syndrome, potentially fatal. The labels require a washout of weeks between them."),
        (.maoi, .snri, "Serotonin syndrome, potentially fatal. The labels require a washout of weeks between them."),
        (.maoi, .tca, "Risk of serotonin syndrome and hypertensive crisis."),
        (.maoi, .stimulant, "Hypertensive crisis. A potentially fatal spike in blood pressure."),
        (.maoi, .opioid, "Risk of serotonin syndrome, especially with meperidine/pethidine, tramadol, and tapentadol."),
        (.lithium, .psychedelic, "Of 62 reports of this combination, 47% described a seizure and 39% involved medical attention, against none of 34 reports for lamotrigine. Self-reported, so the rate is not a measured one, but no other pairing shows a signal like it."),
        (.ghb, .alcohol, "Respiratory depression and loss of consciousness. Very narrow safety margin."),
        (.ghb, .benzodiazepine, "Severe respiratory depression. Both are GABAergic depressants."),
        (.benzodiazepine, .alcohol, "Life-threatening respiratory depression. This combination is a leading cause of overdose death."),
        (.opioid, .gabapentinoid, "Enhanced respiratory depression. Gabapentinoids increase opioid overdose risk."),
        (.opioid, .opioid, "Stacking opioids is unpredictable. Respiratory depression risk compounds."),
        (.opioid, .antihistamine, "Additive CNS and respiratory depression. Antihistamines potentiate opioid sedation."),
        (.opioid, .stimulant, "Stimulants mask overdose signs. When they wear off, respiratory depression can emerge."),
        (.benzodiazepine, .gabapentinoid, "Excessive sedation and respiratory depression risk."),
        (.benzodiazepine, .antihistamine, "Compounded CNS depression. Excessive sedation and impaired breathing."),
        (.ssri, .empathogen, "SSRIs usually blunt MDMA. It may feel much weaker, and the documented harm is taking more to compensate (overheating, heart strain). Case reports don't show serotonin syndrome from this pair alone; MAOIs are the documented danger."),
        (.snri, .empathogen, "SNRIs usually blunt MDMA. It may feel weaker, and the documented harm is taking more to compensate (overheating, heart strain). Case reports don't show serotonin syndrome from this pair alone; MAOIs are the documented danger."),
        (.tca, .empathogen, "TCAs usually blunt MDMA rather than boosting it, which leads people to take more; the bigger concern is added strain on heart rate and blood pressure."),
        (.dissociative, .alcohol, "Risk of respiratory depression, aspiration, and loss of consciousness."),
        (.dissociative, .benzodiazepine, "Severe respiratory depression and loss of consciousness."),
        (.benzodiazepine, .benzodiazepine, "Stacking benzodiazepines dramatically increases sedation and respiratory depression risk."),
        (.ssri, .snri, "Overlapping serotonin reuptake inhibition. Increased serotonin syndrome risk."),
        (.ssri, .tca, "SSRIs inhibit TCA metabolism. Risk of TCA toxicity and serotonin syndrome."),
        (.gabapentinoid, .alcohol, "Enhanced CNS depression. Risk of respiratory depression and death."),
        (.serotonergic, .empathogen, "Serotonin syndrome risk. These drugs add serotonin on top of an empathogen's surge. Some (tramadol, meperidine) can also trigger seizures."),
        (.serotonergic, .maoi, "Serotonin syndrome, potentially fatal. MAOIs block the enzyme that clears serotonin."),
        (.serotonergic, .serotonergic, "Serotonin syndrome risk. Two serotonin-raising drugs stacked together."),
        (.serotonergic, .ssri, "Serotonin syndrome risk. A serotonin-raising drug stacked with an SSRI."),
        (.serotonergic, .snri, "Serotonin syndrome risk. A serotonin-raising drug stacked with an SNRI."),
        (.serotonergic, .tca, "Serotonin syndrome risk. A serotonin-raising drug stacked with a tricyclic antidepressant."),
        (.serotonergic, .lithium, "A large serotonin load on top of lithium's own. The lithium label names tramadol and fentanyl in this group; serotonin syndrome can start within hours."),
        (.alpha2Agonist, .opioid, "Heavy sedation with a dangerously slow heart rate and breathing. Naloxone reverses the opioid but NOT the alpha-2 part. Give rescue breaths and call for help even after naloxone."),
        (.alpha2Agonist, .alcohol, "Adds up sedation and lowers blood pressure further. Stronger drowsiness and dizziness."),
        (.alpha2Agonist, .benzodiazepine, "Compounded sedation and low blood pressure. Stronger drowsiness and dizziness."),
        (.alpha2Agonist, .gabapentinoid, "Additive sedation and low blood pressure. More drowsiness and dizziness."),
        (.alpha2Agonist, .tca, "Tricyclics can cancel out clonidine-type blood-pressure lowering, so blood pressure may rise. That is a medical issue more than an overdose risk."),
        (.betaBlocker, .alpha2Agonist, "Stopping the clonidine-type drug suddenly while on a beta-blocker can spike blood pressure to dangerous levels."),
        (.betaBlocker, .stimulant, "The old \u{201C}never mix\u{201D} warning rests on little: large reviews did not find the harm it predicts. Both still strain the heart."),
        (.betaBlocker, .alcohol, "Both can lower blood pressure and add to dizziness. You may feel faint, especially standing up."),
        (.orexinAntagonist, .opioid, "Added drowsiness and next-day grogginess, with more fall and coordination risk. The labels warn about combining with other CNS depressants, opioids included."),
        (.orexinAntagonist, .alcohol, "Alcohol stacks psychomotor and memory impairment on top of the sleep med (and raises lemborexant's blood levels). Expect worse next-day grogginess and unsteadiness. The labels advise against drinking with these."),
        (.orexinAntagonist, .benzodiazepine, "Stacking two sleep-promoting drugs adds next-day sedation, fall risk and impaired coordination. The labels warn about combining with other CNS depressants."),
        (.orexinAntagonist, .gabapentinoid, "Additive sedation and next-day grogginess. More drowsiness, dizziness, and fall risk."),
        (.orexinAntagonist, .ghb, "Compounded sedation and deeper drowsiness. GHB suppresses breathing on its own, and added sedation makes that harder to notice."),
        (.orexinAntagonist, .antihistamine, "Both cause drowsiness, so next-day sedation and grogginess add up."),
        (.dissociative, .opioid, "Respiratory depression risk. Dissociatives can mask overdose signs."),
        (.opioid, .antipsychotic, "Additive CNS and respiratory depression."),
        (.lithium, .ssri, "Both raise serotonin, so serotonin syndrome is possible (agitation, tremor, sweating, a racing heart), most likely in the first weeks. This pairing is prescribed and monitored on purpose; SSRIs do not raise lithium levels."),
        (.lithium, .snri, "Both raise serotonin, so serotonin syndrome is possible (agitation, tremor, sweating, a racing heart), most likely in the first weeks. This pairing is prescribed and monitored on purpose; SNRIs do not raise lithium levels."),
        (.maoi, .dissociative, "Serotonin syndrome risk. Especially with DXM and other serotonergic dissociatives."),
        (.barbiturate, .opioid, "Combined respiratory depression with no ceiling. Barbiturates deepen an opioid's suppression of breathing until it stops."),
        (.barbiturate, .benzodiazepine, "Life-threatening respiratory depression. A barbiturate opens the GABA-A channel directly rather than modulating it, so this stacks past the point where benzodiazepines alone level off."),
        (.barbiturate, .alcohol, "Life-threatening respiratory depression and loss of consciousness. The classic fatal combination."),
        (.barbiturate, .ghb, "Severe respiratory depression. Two direct-acting depressants with no shared ceiling."),
        (.barbiturate, .barbiturate, "Doses add with no plateau, and the gap between a sedating dose and a fatal one is narrow to begin with."),
        (.barbiturate, .gabapentinoid, "Additive sedation and respiratory depression."),
        (.barbiturate, .antihistamine, "Heavy additive sedation. Deep drowsiness and impaired breathing."),
        (.barbiturate, .dissociative, "Additive CNS and respiratory depression, with a raised risk of vomiting while unresponsive."),
        (.barbiturate, .alpha2Agonist, "Additive sedation, low blood pressure, and slow heart rate."),
        (.barbiturate, .orexinAntagonist, "Additive sedation and next-day impairment."),
        (.barbiturate, .cannabinoid, "Additive sedation, dizziness, and slowed reaction time."),
        (.barbiturate, .antipsychotic, "Additive CNS depression. More sedation and impairment."),
        (.stimulant, .stimulant, "Cardiovascular strain. Combined stimulants raise heart rate and blood pressure."),
        (.stimulant, .psychedelic, "Increased anxiety and vasoconstriction. Stimulants can intensify difficult trips."),
        (.cannabinoid, .psychedelic, "Unpredictable intensification. Cannabis can trigger anxiety or thought loops."),
        (.ssri, .psychedelic, "SSRIs typically reduce psychedelic effects but may increase risk with some compounds."),
        (.ssri, .ssri, "Serotonin accumulation risk. Combining serotonergic agents increases toxicity chance."),
        (.stimulant, .dissociative, "Increased heart rate and blood pressure: cardiovascular strain."),
        (.alcohol, .stimulant, "Stimulants mask alcohol impairment, so it is easy to drink too much."),
        (.alcohol, .antihistamine, "Compounded drowsiness and impaired coordination."),
        (.alcohol, .antipsychotic, "Additive CNS depression. More sedation and impairment."),
        (.gabapentinoid, .gabapentinoid, "Stacking gabapentinoids compounds sedation and respiratory depression risk."),
        (.dissociative, .dissociative, "Compounded dissociation. Disorientation and loss of motor control."),
        (.empathogen, .empathogen, "Serotonin depletion and neurotoxicity risk. Allow adequate recovery between uses."),
        (.lithium, .empathogen, "MDMA releases serotonin in bulk and lithium adds to it, so serotonin syndrome is the main risk. Seizures are reported for lithium with classic psychedelics; MDMA has not been looked at the same way."),
        (.lithium, .maoi, "MAOIs block the enzyme that clears serotonin, so the load builds instead of levelling off. Serotonin syndrome is the risk; MAOIs do not raise lithium levels."),
        (.stimulant, .ssri, "Some combinations increase serotonin or seizure risk. Monitor for symptoms."),
        (.stimulant, .snri, "Cardiovascular strain and serotonin risk. Watch your heart rate and blood pressure."),
        (.antipsychotic, .antipsychotic, "Combined QTc prolongation risk. Monitor cardiac rhythm."),
        (.gabapentinoid, .antihistamine, "Additive CNS depression. More sedation and impaired coordination."),
        (.cannabinoid, .benzodiazepine, "Additive sedation. Drowsiness and impaired coordination may increase."),
        (.cannabinoid, .opioid, "Additive CNS depression. Sedation and respiratory depression risk may rise."),
        (.cannabinoid, .alcohol, "Additive impairment. More dizziness, drowsiness, and slower reactions."),
        (.alcohol, .maoi, "Tap beer can spike blood pressure. In 98 beer samples, every bottled or canned one was low in tyramine; the four high enough to matter on an irreversible MAOI (phenelzine, tranylcypromine) were all on tap."),
        (.alcohol, .ssri, "Sertraline and escitalopram showed no added impairment in trials. They did not deepen alcohol's effects on thinking or coordination, though the escitalopram label still advises against drinking."),
        (.cannabinoid, .gabapentinoid, "Added dizziness and drowsiness. Gabapentinoids cause both on their own, and the dronabinol (THC) label warns that drugs causing them add to its effect."),
        (.cannabinoid, .stimulant, "Heart rate and blood pressure add up. THC raises heart rate on its own, and the dronabinol (THC) label advises against combining it with amphetamines and similar stimulants."),
        (.gabapentinoid, .ghb, "Severe respiratory depression. The sodium oxybate (GHB) label lists sedating anti-epileptic drugs among the depressants that raise its risk of respiratory depression and death, and the pregabalin label warns of the same."),
        (.gabapentinoid, .stimulant, "Seizure risk at heavy doses. Pregabalin overdoses have caused seizures, and the amphetamine label warns that stimulants can lower the seizure threshold."),
        (.serotonergic, .stimulant, "Serotonin syndrome risk. A serotonin-raising drug stacked with a stimulant; the amphetamine label warns about this pairing."),
        (.dissociative, .ghb, "Sudden unconsciousness and slowed breathing. The sodium oxybate (GHB) label warns that general anesthetics and other depressants raise its risk of respiratory depression and death."),
    ]
}
