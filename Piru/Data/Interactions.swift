import Foundation
import SwiftUI
import os

nonisolated private let logger = Logger(subsystem: "dev.yumeji.piru", category: "Interactions")

// MARK: - Interaction Severity

enum InteractionSeverity: Int, Comparable, Codable {
    case caution = 0
    case unsafe = 1
    case dangerous = 2

    static func < (lhs: InteractionSeverity, rhs: InteractionSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: LocalizedStringResource {
        switch self {
        case .dangerous: "Dangerous"
        case .unsafe: "Unsafe"
        case .caution: "Caution"
        }
    }

    var color: Color {
        switch self {
        case .dangerous: .red
        case .unsafe: .orange
        case .caution: .yellow
        }
    }
}

// MARK: - Interaction Source

/// Origin of an interaction warning. Currently only ``classRule`` is wired up
/// — TripSit combo data and FDA-label parsing were removed when their
/// runtime fetch paths went away with the SQLite migration. Kept as an enum
/// so the surface can expand again once those sources land in the bundled
/// DB's `interaction_rules` table.
enum InteractionSource {
    case classRule

    var label: LocalizedStringResource {
        switch self {
        case .classRule: "Pharmacological"
        }
    }
}

// MARK: - Drug Class (for interaction matching)

enum DrugClass: String, Codable {
    case opioid, benzodiazepine, stimulant, psychedelic, dissociative
    case empathogen, cannabinoid, gabapentinoid
    case alcohol, ghb, antihistamine
    case maoi, ssri, snri, tca, lithium
    case antipsychotic, supplement, other
}

// MARK: - Interaction Result

struct InteractionResult {
    let severity: InteractionSeverity
    let substanceA: String
    let substanceB: String
    let description: String
    let source: InteractionSource

    init(severity: InteractionSeverity, substanceA: String, substanceB: String, description: String, source: InteractionSource = .classRule) {
        self.severity = severity
        self.substanceA = substanceA
        self.substanceB = substanceB
        self.description = description
        self.source = source
    }
}

// MARK: - FDA Label-Sourced Interaction

/// A drug interaction extracted from an FDA Structured Product Label.
/// Supplements the class-based interaction rules with substance-specific data parsed from
/// the `drug_interactions` section of a drug's prescribing information.
struct SubstanceInteraction: Codable, Equatable {
    let sourceDrug: String           // Lowercased name of the drug whose label was parsed
    let targetClass: DrugClass       // Drug class it interacts with
    let targetKeyword: String        // Label keyword that triggered detection
    let severity: InteractionSeverity
    let snippet: String              // Excerpt from the FDA label describing the interaction
}

// MARK: - Interaction Rule

private struct InteractionRule {
    let classA: DrugClass
    let classB: DrugClass
    let severity: InteractionSeverity
    let description: String

    init(classA: DrugClass, classB: DrugClass, severity: InteractionSeverity, description: LocalizedStringResource) {
        self.classA = classA
        self.classB = classB
        self.severity = severity
        self.description = String(localized: description)
    }
}

// MARK: - Interaction Checker

/// The drug-interaction engine. Resolves substance pairs into severity-ranked
/// warnings using hand-curated pharmacological class rules and returns the
/// worst-case match per pair.
///
/// ## Source layers
///
/// **Class-pair rules** (``rules``) keyed by ``DrugClass`` pairs are the only
/// active source. The earlier design included TripSit combo data and parsed
/// FDA-label warnings as fallback layers; those were removed when the runtime
/// API fetches went away with the SQLite migration. Restoring them means
/// populating the bundled SQLite's `interaction_rules` table and adding a
/// SQL-backed source layer here — tracked separately.
///
/// ## Severity ordering
///
/// ``InteractionSeverity`` orders `dangerous > unsafe > caution`. Batch
/// deduplication keeps the highest-severity result for each substance pair so
/// users always see the worst-case warning.
///
/// ## Caveats
///
/// ``DrugClass/other`` participates in **zero** rules. Any substance that
/// `categoryToDrugClass` maps to `.other` (analgesics, cardiovascular,
/// antimicrobials, GI, respiratory, endocrine, immunological, depressants not
/// otherwise classified, etc.) is effectively interaction-invisible at the
/// class layer and will only surface warnings if its specific name appears in
/// a TripSit combo or FDA label record. Add an entry to
/// ``substanceClassOverrides`` to lift a substance into a real class when a
/// missing interaction is discovered.
enum InteractionChecker {

    // MARK: - Public API

    /// Check a substance against a list of active dose entries
    static func check(_ substanceName: String, against activeEntries: [DoseEntry]) -> [InteractionResult] {
        let newClasses = drugClasses(for: substanceName)

        var results: [InteractionResult] = []
        var seen = Set<String>() // Avoid duplicate warnings for same substance

        for entry in activeEntries {
            // Skip same substance
            guard entry.substance.lowercased() != substanceName.lowercased() else { continue }
            guard !seen.contains(entry.substance.lowercased()) else { continue }
            seen.insert(entry.substance.lowercased())

            let activeClasses = drugClasses(for: entry.substance)

            // Check all class pair combinations
            for newClass in newClasses {
                for activeClass in activeClasses {
                    if let rule = findRule(newClass, activeClass) {
                        results.append(InteractionResult(
                            severity: rule.severity,
                            substanceA: substanceName,
                            substanceB: entry.substance,
                            description: rule.description,
                            source: .classRule
                        ))
                    }
                }
            }
        }

        // Sort by severity (dangerous first), deduplicate by substance pair
        var uniqueResults: [InteractionResult] = []
        var pairSeen = Set<String>()
        for result in results.sorted(by: { $0.severity > $1.severity }) {
            let key = [result.substanceA.lowercased(), result.substanceB.lowercased()].sorted().joined(separator: "|")
            if !pairSeen.contains(key) {
                pairSeen.insert(key)
                uniqueResults.append(result)
            }
        }

        return uniqueResults
    }

    /// Check all substances in a batch against each other and against active entries
    static func checkBatch(
        _ substances: [String],
        against activeEntries: [DoseEntry]
    ) -> [InteractionResult] {
        var allResults: [InteractionResult] = []

        // Check each substance against active entries (skip if none)
        if !activeEntries.isEmpty {
            for substance in substances {
                allResults.append(contentsOf: check(substance, against: activeEntries))
            }
        }

        // Check substances within the batch against each other
        for i in 0..<substances.count {
            for j in (i + 1)..<substances.count {
                let classesA = drugClasses(for: substances[i])
                let classesB = drugClasses(for: substances[j])

                for classA in classesA {
                    for classB in classesB {
                        if let rule = findRule(classA, classB) {
                            allResults.append(InteractionResult(
                                severity: rule.severity,
                                substanceA: substances[i],
                                substanceB: substances[j],
                                description: rule.description,
                                source: .classRule
                            ))
                        }
                    }
                }
            }
        }

        // Deduplicate keeping highest severity per pair
        var best: [String: InteractionResult] = [:]
        for result in allResults {
            let key = [result.substanceA.lowercased(), result.substanceB.lowercased()].sorted().joined(separator: "|")
            if let existing = best[key] {
                if result.severity > existing.severity {
                    best[key] = result
                }
            } else {
                best[key] = result
            }
        }

        return Array(best.values).sorted { $0.severity > $1.severity }
    }

    // MARK: - Drug Class Mapping

    /// Specific substance name → drug class overrides
    private static let substanceClassOverrides: [String: [DrugClass]] = {
        var map: [String: [DrugClass]] = [:]

        // MAOIs
        for name in ["Phenelzine", "Tranylcypromine", "Isocarboxazid", "Selegiline",
                     "Moclobemide", "Syrian Rue"] {
            map[name.lowercased()] = [.maoi]
        }

        // SSRIs
        for name in ["Sertraline", "Fluoxetine", "Paroxetine", "Citalopram",
                     "Escitalopram", "Fluvoxamine"] {
            map[name.lowercased()] = [.ssri]
        }

        // SNRIs
        for name in ["Venlafaxine", "Duloxetine", "Desvenlafaxine",
                     "Levomilnacipran", "Milnacipran"] {
            map[name.lowercased()] = [.snri]
        }

        // TCAs
        for name in ["Amitriptyline", "Nortriptyline", "Imipramine", "Desipramine",
                     "Clomipramine", "Doxepin", "Trimipramine", "Protriptyline"] {
            map[name.lowercased()] = [.tca]
        }

        // Dual-class substances
        map["tramadol"] = [.opioid, .snri]
        map["tapentadol"] = [.opioid, .snri]
        map["meperidine"] = [.opioid, .ssri]
        map["pethidine"] = [.opioid, .ssri]
        map["dxm"] = [.dissociative, .ssri]
        map["dextromethorphan"] = [.dissociative, .ssri]
        map["mdma"] = [.empathogen, .stimulant]
        map["mda"] = [.empathogen, .stimulant]
        map["mdea"] = [.empathogen, .stimulant]

        // Lithium
        map["lithium"] = [.lithium]
        map["lithium carbonate"] = [.lithium]
        map["lithium orotate"] = [.lithium]

        // GHB/GBL
        map["ghb"] = [.ghb]
        map["gbl"] = [.ghb]
        map["ghb/gbl"] = [.ghb]
        map["1,4-butanediol"] = [.ghb]

        // Alcohol
        map["alcohol"] = [.alcohol]
        map["ethanol"] = [.alcohol]

        // Gabapentinoids
        map["phenibut"] = [.gabapentinoid]
        map["gabapentin"] = [.gabapentinoid]
        map["pregabalin"] = [.gabapentinoid]
        map["baclofen"] = [.ghb]

        // Stimulants (common names)
        for name in ["Caffeine", "Nicotine", "Methamphetamine", "Cocaine",
                     "Amphetamine", "Dextroamphetamine", "Lisdexamfetamine",
                     "Methylphenidate", "Modafinil", "Armodafinil", "DMAA"] {
            map[name.lowercased()] = [.stimulant]
        }

        // Opioids (common names/variants)
        map["kratom"] = [.opioid]
        map["heroin"] = [.opioid]
        map["fentanyl"] = [.opioid]

        // Atypical antidepressants
        map["bupropion"] = [.stimulant]   // NDRI — stimulant-like, lowers seizure threshold
        map["trazodone"] = [.ssri]        // SARI — serotonergic, reasonable SSRI proxy
        map["vortioxetine"] = [.ssri]     // Multimodal serotonergic
        map["vilazodone"] = [.ssri]       // SSRI + 5-HT1A partial agonist
        map["agomelatine"] = [.other]     // Melatonin agonist — minimal serotonin interactions
        map["reboxetine"] = [.snri]       // NRI — norepinephrine-selective

        // Antihistamines
        for name in ["Diphenhydramine", "DPH", "Hydroxyzine", "Promethazine",
                     "Doxylamine", "Chlorpheniramine", "Cetirizine",
                     "Meclizine", "Dimenhydrinate"] {
            map[name.lowercased()] = [.antihistamine]
        }

        // Z-drugs (GABA-A agonists — interact like benzos)
        for name in ["Zolpidem", "Zopiclone", "Eszopiclone", "Zaleplon"] {
            map[name.lowercased()] = [.benzodiazepine]
        }

        // Buspirone (5-HT1A partial agonist — serotonin syndrome risk)
        map["buspirone"] = [.ssri]  // Serotonergic proxy for interaction matching

        // Quetiapine (sedating antipsychotic — also acts as antihistamine at low doses)
        map["quetiapine"] = [.antipsychotic, .antihistamine]

        // Clonidine (alpha-2 agonist — additive with CNS depressants)
        map["clonidine"] = [.other]

        // Mirtazapine (NaSSA — both antihistamine AND serotonergic)
        map["mirtazapine"] = [.antihistamine, .ssri]

        return map
    }()

    /// Lazy cache mapping lowercased substance names (and aliases) to their
    /// resolved drug classes. Filled on first lookup via ``SubstanceLibrary``.
    private static var drugClassCache: [String: [DrugClass]] = [:]

    /// Get drug classes for a substance name. Falls back to a `SubstanceLibrary`
    /// lookup (canonical name or alias) when not in the overrides table; the
    /// result is memoised for subsequent calls.
    static func drugClasses(for substanceName: String) -> [DrugClass] {
        let lower = substanceName.lowercased()

        if let override = substanceClassOverrides[lower] {
            return override
        }

        if let cached = drugClassCache[lower] {
            return cached
        }

        guard let substance = SubstanceLibrary.lookupByNameOrAlias(substanceName) else {
            drugClassCache[lower] = []
            return []
        }
        let resolved = [categoryToDrugClass(substance.category)]
        drugClassCache[lower] = resolved
        return resolved
    }

    private static func categoryToDrugClass(_ category: SubstanceCategory) -> DrugClass {
        switch category {
        case .opioid: .opioid
        case .benzodiazepine: .benzodiazepine
        case .stimulant: .stimulant
        case .psychedelic: .psychedelic
        case .dissociative: .dissociative
        // KOR agonists are pharmacologically closer to dissociatives than to
        // classical psychedelics — they don't engage 5-HT2A, but the kappa
        // mechanism shares acute dissociation/derealisation phenomenology and
        // (more importantly for interaction modelling) compounds with
        // dissociatives or sedatives. Route to `.dissociative` until we add a
        // dedicated `.kappaAgonist` class with its own rule set.
        case .dysdelic: .dissociative
        case .empathogen: .empathogen
        case .cannabinoid: .cannabinoid
        case .gabapentinoid: .gabapentinoid
        case .ampakine: .other
        // Eugeroics block DAT/NET like stimulants and stack badly with serotonergics
        // and MAOIs — treat as `.stimulant` for interaction purposes.
        case .eugeroic: .stimulant
        // Default fallback for the `.antidepressant` category. SSRI is the
        // most common subtype, so this is the safest serotonergic proxy when
        // we have no better information. **Failure mode:** any imported MAOI,
        // SNRI, or TCA that lacks a name/alias hit in
        // `substanceClassOverrides` will silently land here and be matched
        // against SSRI rules — missing MAOI×stimulant or SNRI×empathogen
        // warnings, for instance. When such a gap is discovered, add the
        // substance to `substanceClassOverrides` with the correct subtype.
        case .antidepressant: .ssri
        case .antipsychotic: .antipsychotic
        case .supplement: .supplement
        case .nootropic: .other
        case .depressant: .other
        case .analgesic: .other
        case .antihistamine: .antihistamine
        // Deliriants are anticholinergic/antimuscarinic; their dominant interaction
        // concern is additive anticholinergic toxicity, the same profile as the
        // first-gen antihistamines they were split out of. Route to `.antihistamine`
        // so those rules (and the sedative/anticholinergic stacking warnings) apply.
        case .deliriant: .antihistamine
        case .cardiovascular: .other
        case .antimicrobial: .other
        case .gastrointestinal: .other
        case .respiratory: .other
        case .endocrine: .other
        case .immunological: .other
        case .peptide: .other
        // Anticonvulsants are pharmacologically heterogeneous (sodium-channel
        // blockers, SV2A ligands, gabapentinoids, GABAergics) — no single
        // safe class proxy. Route to `.other` and let
        // `substanceClassOverrides` map specific drugs (gabapentin,
        // pregabalin → `.gabapentinoid`; benzo-class anticonvulsants
        // → `.benzodiazepine`) where the subtype is known.
        case .anticonvulsant: .other
        case .other: .other
        }
    }

    // MARK: - Interaction Rules

    private static let rules: [InteractionRule] = [
        // === DANGEROUS ===

        InteractionRule(classA: .opioid, classB: .benzodiazepine, severity: .dangerous,
            description: "Combined respiratory depression — the leading cause of overdose death."),
        InteractionRule(classA: .opioid, classB: .ghb, severity: .dangerous,
            description: "Severe respiratory depression — both substances suppress breathing."),
        InteractionRule(classA: .opioid, classB: .alcohol, severity: .dangerous,
            description: "Respiratory depression and CNS shutdown — potentially fatal combination."),
        InteractionRule(classA: .maoi, classB: .empathogen, severity: .dangerous,
            description: "Risk of fatal serotonin syndrome — do not combine."),
        InteractionRule(classA: .maoi, classB: .ssri, severity: .dangerous,
            description: "Serotonin syndrome — potentially fatal. Allow 2+ week washout."),
        InteractionRule(classA: .maoi, classB: .snri, severity: .dangerous,
            description: "Serotonin syndrome — potentially fatal. Allow 2+ week washout."),
        InteractionRule(classA: .maoi, classB: .tca, severity: .dangerous,
            description: "Risk of serotonin syndrome and hypertensive crisis."),
        InteractionRule(classA: .maoi, classB: .stimulant, severity: .dangerous,
            description: "Hypertensive crisis — potentially fatal spike in blood pressure."),
        InteractionRule(classA: .maoi, classB: .opioid, severity: .dangerous,
            description: "Risk of serotonin syndrome, especially with meperidine/pethidine, tramadol, and tapentadol."),
        InteractionRule(classA: .lithium, classB: .psychedelic, severity: .dangerous,
            description: "Risk of seizures and serotonin toxicity — well-documented dangerous combination."),
        InteractionRule(classA: .ghb, classB: .alcohol, severity: .dangerous,
            description: "Respiratory depression and loss of consciousness — very narrow safety margin."),
        InteractionRule(classA: .ghb, classB: .benzodiazepine, severity: .dangerous,
            description: "Severe respiratory depression — both are GABAergic depressants."),
        InteractionRule(classA: .benzodiazepine, classB: .alcohol, severity: .dangerous,
            description: "Life-threatening respiratory depression — this combination is a leading cause of overdose death."),

        // === UNSAFE ===

        InteractionRule(classA: .opioid, classB: .gabapentinoid, severity: .unsafe,
            description: "Enhanced respiratory depression — gabapentinoids increase opioid overdose risk."),
        InteractionRule(classA: .opioid, classB: .opioid, severity: .unsafe,
            description: "Stacking opioids is unpredictable — respiratory depression risk compounds."),
        InteractionRule(classA: .opioid, classB: .antihistamine, severity: .unsafe,
            description: "Additive CNS and respiratory depression — antihistamines potentiate opioid sedation."),
        InteractionRule(classA: .opioid, classB: .stimulant, severity: .unsafe,
            description: "Stimulants mask overdose signs — when they wear off, respiratory depression can emerge."),
        InteractionRule(classA: .benzodiazepine, classB: .gabapentinoid, severity: .unsafe,
            description: "Excessive sedation and respiratory depression risk."),
        InteractionRule(classA: .benzodiazepine, classB: .antihistamine, severity: .unsafe,
            description: "Compounded CNS depression — excessive sedation and impaired breathing."),
        InteractionRule(classA: .ssri, classB: .empathogen, severity: .unsafe,
            description: "Reduced effects and risk of serotonin syndrome — SSRIs block MDMA's mechanism."),
        InteractionRule(classA: .snri, classB: .empathogen, severity: .unsafe,
            description: "Serotonin syndrome risk — SNRIs block reuptake while empathogens release serotonin."),
        InteractionRule(classA: .tca, classB: .empathogen, severity: .unsafe,
            description: "Serotonin toxicity risk from combined serotonergic activity."),
        InteractionRule(classA: .dissociative, classB: .opioid, severity: .unsafe,
            description: "Respiratory depression risk — dissociatives can mask overdose signs."),
        InteractionRule(classA: .opioid, classB: .antipsychotic, severity: .unsafe,
            description: "Additive CNS and respiratory depression."),
        InteractionRule(classA: .lithium, classB: .ssri, severity: .unsafe,
            description: "Increased risk of serotonin syndrome and lithium toxicity."),
        InteractionRule(classA: .lithium, classB: .snri, severity: .unsafe,
            description: "Increased risk of serotonin syndrome and lithium toxicity."),
        InteractionRule(classA: .maoi, classB: .dissociative, severity: .unsafe,
            description: "Serotonin syndrome risk — especially with DXM and other serotonergic dissociatives."),

        // === CAUTION ===

        InteractionRule(classA: .stimulant, classB: .stimulant, severity: .caution,
            description: "Cardiovascular strain — combined stimulants increase heart rate and blood pressure."),
        InteractionRule(classA: .stimulant, classB: .psychedelic, severity: .caution,
            description: "Increased anxiety and vasoconstriction — stimulants can intensify difficult trips."),
        InteractionRule(classA: .cannabinoid, classB: .psychedelic, severity: .caution,
            description: "Unpredictable intensification — cannabis can trigger anxiety or thought loops."),
        InteractionRule(classA: .dissociative, classB: .alcohol, severity: .unsafe,
            description: "Risk of respiratory depression, aspiration, and loss of consciousness."),
        InteractionRule(classA: .dissociative, classB: .benzodiazepine, severity: .unsafe,
            description: "Significant respiratory depression risk and profound loss of consciousness."),
        InteractionRule(classA: .benzodiazepine, classB: .benzodiazepine, severity: .unsafe,
            description: "Stacking benzodiazepines dramatically increases sedation and respiratory depression risk."),
        InteractionRule(classA: .ssri, classB: .psychedelic, severity: .caution,
            description: "SSRIs typically reduce psychedelic effects but may increase risk with some compounds."),
        InteractionRule(classA: .ssri, classB: .ssri, severity: .caution,
            description: "Serotonin accumulation risk — combining serotonergic agents increases toxicity chance."),
        InteractionRule(classA: .ssri, classB: .snri, severity: .unsafe,
            description: "Overlapping serotonin reuptake inhibition — increased serotonin syndrome risk."),
        InteractionRule(classA: .ssri, classB: .tca, severity: .unsafe,
            description: "SSRIs inhibit TCA metabolism — risk of TCA toxicity and serotonin syndrome."),
        InteractionRule(classA: .stimulant, classB: .dissociative, severity: .caution,
            description: "Increased heart rate and blood pressure — cardiovascular strain."),
        InteractionRule(classA: .alcohol, classB: .stimulant, severity: .caution,
            description: "Stimulants mask alcohol impairment — risk of overconsumption."),
        InteractionRule(classA: .alcohol, classB: .antihistamine, severity: .caution,
            description: "Compounded drowsiness and impaired coordination."),
        InteractionRule(classA: .alcohol, classB: .antipsychotic, severity: .caution,
            description: "Additive CNS depression — increased sedation and impairment."),
        InteractionRule(classA: .gabapentinoid, classB: .alcohol, severity: .unsafe,
            description: "Enhanced CNS depression — risk of respiratory depression and death."),
        InteractionRule(classA: .gabapentinoid, classB: .gabapentinoid, severity: .caution,
            description: "Stacking gabapentinoids compounds sedation and respiratory depression risk."),
        InteractionRule(classA: .dissociative, classB: .dissociative, severity: .caution,
            description: "Compounded dissociation — disorientation and loss of motor control."),
        InteractionRule(classA: .empathogen, classB: .empathogen, severity: .caution,
            description: "Serotonin depletion and neurotoxicity risk — allow adequate recovery between uses."),
        InteractionRule(classA: .lithium, classB: .empathogen, severity: .dangerous,
            description: "Risk of seizures and serotonin toxicity — potentially fatal combination."),
        InteractionRule(classA: .lithium, classB: .maoi, severity: .unsafe,
            description: "Risk of serotonin syndrome and lithium toxicity."),

        // Additional rules from audit
        InteractionRule(classA: .stimulant, classB: .ssri, severity: .caution,
            description: "Some combinations increase serotonin or seizure risk — monitor for symptoms."),
        InteractionRule(classA: .stimulant, classB: .snri, severity: .caution,
            description: "Cardiovascular strain and potential serotonin interaction — monitor heart rate and blood pressure."),
        InteractionRule(classA: .antipsychotic, classB: .antipsychotic, severity: .caution,
            description: "Combined QTc prolongation risk — monitor cardiac rhythm."),
        InteractionRule(classA: .gabapentinoid, classB: .antihistamine, severity: .caution,
            description: "Additive CNS depression — increased sedation and impaired coordination."),
        InteractionRule(classA: .cannabinoid, classB: .benzodiazepine, severity: .caution,
            description: "Additive sedation — may increase drowsiness and impaired coordination."),
        InteractionRule(classA: .cannabinoid, classB: .opioid, severity: .caution,
            description: "Additive CNS depression — may increase sedation and respiratory depression risk."),
        InteractionRule(classA: .opioid, classB: .ssri, severity: .caution,
            description: "Serotonin syndrome risk with some opioids (tramadol, meperidine, fentanyl) — monitor for symptoms."),
        InteractionRule(classA: .cannabinoid, classB: .alcohol, severity: .caution,
            description: "Additive impairment — increased dizziness, drowsiness, and slowed reaction time."),
        InteractionRule(classA: .antipsychotic, classB: .alcohol, severity: .caution,
            description: "Additive CNS depression — increased sedation and impairment."),
    ]

    /// Precomputed rule lookup keyed by sorted class pairs for O(1) access.
    private static let ruleLookup: [String: InteractionRule] = {
        var dict: [String: InteractionRule] = [:]
        for rule in rules {
            let key = [rule.classA.rawValue, rule.classB.rawValue].sorted().joined(separator: "|")
            dict[key] = rule
        }
        return dict
    }()

    private static func findRule(_ a: DrugClass, _ b: DrugClass) -> InteractionRule? {
        let key = [a.rawValue, b.rawValue].sorted().joined(separator: "|")
        return ruleLookup[key]
    }

    // MARK: - Active Entry Detection

    /// Filter entries to those still pharmacologically active
    static func activeEntries(from entries: [DoseEntry]) -> [DoseEntry] {
        let now = Date.now
        return entries.filter { entry in
            guard let substance = SubstanceLibrary.lookup(entry.substance) else {
                // Unknown substance — assume active for 24h as safety fallback
                return entry.timestamp.addingTimeInterval(86400) > now
            }
            if let duration = substance.duration(for: entry.route) {
                return entry.timestamp.addingTimeInterval(duration.estimatedTotalMinutes * 60) > now
            }
            if let halfLife = substance.halfLifeMinutes {
                // 5 half-lives ≈ 97% eliminated
                return entry.timestamp.addingTimeInterval(halfLife * 5 * 60) > now
            }
            // No duration or half-life data — assume active for 24h
            return entry.timestamp.addingTimeInterval(86400) > now
        }
    }
}
