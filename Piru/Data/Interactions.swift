import Foundation
import SwiftUI

// MARK: - Interaction Severity

enum InteractionSeverity: Int, Comparable {
    case caution = 0
    case unsafe = 1
    case dangerous = 2

    static func < (lhs: InteractionSeverity, rhs: InteractionSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
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

// MARK: - Drug Class (for interaction matching)

enum DrugClass: String {
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
}

// MARK: - Interaction Rule

private struct InteractionRule {
    let classA: DrugClass
    let classB: DrugClass
    let severity: InteractionSeverity
    let description: String
}

// MARK: - Interaction Checker

enum InteractionChecker {

    // MARK: - Public API

    /// Check a substance against a list of active dose entries
    static func check(_ substanceName: String, against activeEntries: [DoseEntry]) -> [InteractionResult] {
        let newClasses = drugClasses(for: substanceName)
        guard !newClasses.isEmpty else { return [] }

        var results: [InteractionResult] = []
        var seen = Set<String>() // Avoid duplicate warnings for same substance

        for entry in activeEntries {
            // Skip same substance
            guard entry.substance.lowercased() != substanceName.lowercased() else { continue }
            guard !seen.contains(entry.substance.lowercased()) else { continue }
            seen.insert(entry.substance.lowercased())

            let activeClasses = drugClasses(for: entry.substance)
            guard !activeClasses.isEmpty else { continue }

            // Check all class pair combinations
            for newClass in newClasses {
                for activeClass in activeClasses {
                    if let rule = findRule(newClass, activeClass) {
                        results.append(InteractionResult(
                            severity: rule.severity,
                            substanceA: substanceName,
                            substanceB: entry.substance,
                            description: rule.description
                        ))
                    }
                }
            }
        }

        // Sort by severity (dangerous first), deduplicate by substance pair
        var uniqueResults: [InteractionResult] = []
        var pairSeen = Set<String>()
        for result in results.sorted(by: { $0.severity > $1.severity }) {
            let key = [result.substanceA, result.substanceB].sorted().joined(separator: "|")
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

        // Check each substance against active entries
        for substance in substances {
            allResults.append(contentsOf: check(substance, against: activeEntries))
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
                                description: rule.description
                            ))
                        }
                    }
                }
            }
        }

        // Deduplicate keeping highest severity per pair
        var best: [String: InteractionResult] = [:]
        for result in allResults {
            let key = [result.substanceA, result.substanceB].sorted().joined(separator: "|")
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
        map["caffeine"] = [.stimulant]
        map["nicotine"] = [.stimulant]
        map["methamphetamine"] = [.stimulant]
        map["cocaine"] = [.stimulant]

        // Opioids (common names/variants)
        map["kratom"] = [.opioid]
        map["heroin"] = [.opioid]
        map["fentanyl"] = [.opioid]

        // Antihistamines
        for name in ["Diphenhydramine", "DPH", "Hydroxyzine", "Promethazine",
                     "Doxylamine", "Chlorpheniramine", "Cetirizine",
                     "Meclizine", "Dimenhydrinate"] {
            map[name.lowercased()] = [.antihistamine]
        }

        return map
    }()

    /// Precomputed cache mapping lowercased substance names to their drug classes
    private static let drugClassCache: [String: [DrugClass]] = {
        var cache: [String: [DrugClass]] = [:]
        for substance in SubstanceLibrary.all {
            let key = substance.name.lowercased()
            if cache[key] == nil {
                cache[key] = [categoryToDrugClass(substance.category)]
            }
            for alias in substance.aliases {
                let aliasKey = alias.lowercased()
                if cache[aliasKey] == nil {
                    cache[aliasKey] = [categoryToDrugClass(substance.category)]
                }
            }
        }
        return cache
    }()

    /// Get drug classes for a substance name
    static func drugClasses(for substanceName: String) -> [DrugClass] {
        let lower = substanceName.lowercased()

        // Check overrides first
        if let override = substanceClassOverrides[lower] {
            return override
        }

        // Check precomputed cache
        if let cached = drugClassCache[lower] {
            return cached
        }

        return []
    }

    private static func categoryToDrugClass(_ category: SubstanceCategory) -> DrugClass {
        switch category {
        case .opioid: .opioid
        case .benzodiazepine: .benzodiazepine
        case .stimulant: .stimulant
        case .psychedelic: .psychedelic
        case .dissociative: .dissociative
        case .empathogen: .empathogen
        case .cannabinoid: .cannabinoid
        case .gabapentinoid: .gabapentinoid
        case .antidepressant: .ssri // Default antidepressants to SSRI class (overrides handle specific subtypes)
        case .antipsychotic: .antipsychotic
        case .supplement: .supplement
        case .nootropic: .other
        case .depressant: .other
        case .analgesic: .other
        case .antihistamine: .antihistamine
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
    ]

    private static func findRule(_ a: DrugClass, _ b: DrugClass) -> InteractionRule? {
        rules.first { rule in
            (rule.classA == a && rule.classB == b) ||
            (rule.classA == b && rule.classB == a)
        }
    }

    // MARK: - Active Entry Detection

    /// Filter entries to those still pharmacologically active
    static func activeEntries(from entries: [DoseEntry]) -> [DoseEntry] {
        let now = Date.now
        return entries.filter { entry in
            guard let substance = SubstanceLibrary.lookup(entry.substance),
                  let duration = substance.duration(for: entry.route) else {
                // No duration data — assume active for 24h as safety fallback
                return entry.timestamp.addingTimeInterval(86400) > now
            }
            return entry.timestamp.addingTimeInterval(duration.estimatedTotalMinutes * 60) > now
        }
    }
}
