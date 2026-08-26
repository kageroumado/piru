import Foundation
import Testing
@testable import Piru

/// Gates on the interaction data itself, now that the rules, the name overrides
/// and the category fallbacks are all rows in the bundled database.
///
/// These do not restate severities — those are gated with their reasoning in
/// `pipeline/build/tests/test_sqlite.py`, beside the curated file that carries
/// them. What is gated here is the part a Swift test can see and the pipeline
/// cannot: that every row survives the trip through `DrugClass`, that it reaches
/// the reader with the severity the row states, and that the sentence shown is
/// the one the row was written with.
@Suite("Interaction data gating")
struct InteractionDataGatingTests {
    init() async {
        await SubstanceStore.shared.ensureAllLoaded()
    }

    /// A logged name resolving to each class, so a rule can be exercised
    /// end-to-end. `.serotonergic` has no single-class member by design — it
    /// marks a serotonin-*adding* action a substance carries alongside its own
    /// class (tramadol is an opioid too), which is why the agreement check below
    /// only demands equality where both representatives are single-class.
    private static let representative: [DrugClass: String] = [
        .opioid: "Morphine",
        .benzodiazepine: "Alprazolam",
        .barbiturate: "Phenobarbital",
        .stimulant: "Caffeine",
        .psychedelic: "LSD",
        .dissociative: "Ketamine",
        .empathogen: "MDMA",
        .cannabinoid: "THC",
        .gabapentinoid: "Pregabalin",
        .alcohol: "Alcohol",
        .ghb: "GHB",
        .orexinAntagonist: "Suvorexant",
        .antihistamine: "Diphenhydramine",
        .maoi: "Phenelzine",
        .ssri: "Sertraline",
        .snri: "Venlafaxine",
        .tca: "Amitriptyline",
        .serotonergic: "Tramadol",
        .lithium: "Lithium",
        .antipsychotic: "Risperidone",
        .alpha2Agonist: "Clonidine",
        .betaBlocker: "Propranolol",
        .supplement: "Vitamin C",
        .other: "Agomelatine",
    ]

    /// A second name for each class that has a rule against *itself* — the
    /// checker skips a pairing of one substance with the same substance, so
    /// stacking rules need two members to be exercised at all.
    private static let secondRepresentative: [DrugClass: String] = [
        .opioid: "Oxycodone",
        .benzodiazepine: "Diazepam",
        .barbiturate: "Pentobarbital",
        .stimulant: "Cocaine",
        .dissociative: "Nitrous",
        .empathogen: "MDA",
        .gabapentinoid: "Gabapentin",
        .ssri: "Fluoxetine",
        .serotonergic: "Meperidine",
        .antipsychotic: "Olanzapine",
    ]

    /// The pair of names used to exercise a rule: two different substances when
    /// the rule is a class stacking with itself.
    private static func names(for classA: DrugClass, _ classB: DrugClass) -> (String, String)? {
        guard let first = representative[classA] else { return nil }
        guard classA != classB else {
            return secondRepresentative[classA].map { (first, $0) }
        }
        return representative[classB].map { (first, $0) }
    }

    private func entry(_ substance: String) -> DoseEntry {
        DoseEntry(substance: substance, amount: 100, route: .oral, timestamp: .now)
    }

    // MARK: - The rows survive the trip into Swift

    @Test
    func `The rule table is not empty`() {
        #expect(SubstanceStore.shared.classInteractionRules().count > 50)
    }

    @Test
    func `Every rule row decodes into a class pair and a severity`() {
        // A row whose class or severity the app cannot decode is skipped in
        // silence, so a typo in curated JSON removes a warning with nothing on
        // screen and nothing in the build to say so.
        var undecodable: [String] = []
        for rule in SubstanceStore.shared.classInteractionRules() {
            if DrugClass(rawValue: rule.classA) == nil { undecodable.append(rule.classA) }
            if DrugClass(rawValue: rule.classB) == nil { undecodable.append(rule.classB) }
            if InteractionSeverity(bundledName: rule.severity) == nil { undecodable.append(rule.severity) }
        }
        #expect(undecodable.isEmpty, "rule rows the app drops: \(Set(undecodable).sorted())")
    }

    @Test
    func `No class pair is declared twice`() {
        // `UNIQUE (class_a, class_b)` is on the ordered tuple, so the same pair
        // written back-to-front by two ingesters satisfies it and then decides by
        // row order.
        #expect(InteractionChecker.duplicateRuleKeys.isEmpty)
    }

    @Test
    func `Every rule note carries a mechanism`() {
        let thin = SubstanceStore.shared.classInteractionRules()
            .filter { $0.note.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 }
            .map { "\($0.classA)|\($0.classB)" }
        #expect(thin.isEmpty, "rules warning with no explanation: \(thin)")
    }

    // MARK: - Copy and rows agree

    @Test
    func `Every adjudicated pair has a row to attach to`() {
        // Copy with no row is a sentence nothing can show. Copy is keyed by the
        // same sorted pair, so the two go out of step silently.
        let rows = Set(SubstanceStore.shared.classInteractionRules().compactMap { rule -> String? in
            guard let a = DrugClass(rawValue: rule.classA),
                  let b = DrugClass(rawValue: rule.classB) else { return nil }
            return InteractionRuleCopy.key(a, b)
        })
        let orphaned = Set(InteractionRuleCopy.table.keys).subtracting(rows)
        #expect(orphaned.isEmpty, "copy with no rule row: \(orphaned.sorted())")
    }

    @Test
    func `The English copy is the sentence its row was written with`() {
        // The row's note and the localized copy are the same sentence in two
        // places — one readable from the database, one translatable. This is the
        // only thing that keeps them saying the same thing.
        var drifted: [String] = []
        for rule in SubstanceStore.shared.classInteractionRules() {
            guard let a = DrugClass(rawValue: rule.classA),
                  let b = DrugClass(rawValue: rule.classB),
                  var copy = InteractionRuleCopy.note(a, b) else { continue }
            copy.locale = Locale(identifier: "en")
            let english = String(localized: copy)
            if english != rule.note {
                drifted.append("\(InteractionRuleCopy.key(a, b)):\n  row:  \(rule.note)\n  copy: \(english)")
            }
        }
        #expect(drifted.isEmpty, "copy and row disagree:\n\(drifted.joined(separator: "\n"))")
    }

    // MARK: - The rows reach the reader

    @Test
    func `Every representative resolves to the class it stands for`() {
        for (drugClass, name) in Self.representative {
            #expect(
                InteractionChecker.drugClasses(for: name).contains(drugClass),
                "\(name) no longer resolves to .\(drugClass.rawValue)",
            )
        }
    }

    @Test
    func `Every class has a representative, and every stacking rule has two`() {
        // A new `DrugClass` with no representative would join the table untested;
        // enumerating the cases is what makes that a failure.
        let missing = DrugClass.allCases.filter { Self.representative[$0] == nil }
        #expect(missing.isEmpty, "classes with no representative: \(missing.map(\.rawValue))")

        let stacking = SubstanceStore.shared.classInteractionRules()
            .filter { $0.classA == $0.classB }
            .compactMap { DrugClass(rawValue: $0.classA) }
        let unpaired = stacking.filter { Self.secondRepresentative[$0] == nil }
        #expect(unpaired.isEmpty, "stacking rules with only one member: \(unpaired.map(\.rawValue))")
    }

    @Test
    func `The checker returns the severity the row states`() {
        // Agreement between the two read paths: the raw rows a display surface
        // reads, and the verdict the checker hands a reader. A rule that decodes
        // but never reaches a pairing fails here and nowhere else.
        var disagreements: [String] = []
        for rule in SubstanceStore.shared.classInteractionRules() {
            guard let a = DrugClass(rawValue: rule.classA),
                  let b = DrugClass(rawValue: rule.classB),
                  let expected = InteractionSeverity(bundledName: rule.severity),
                  let (nameA, nameB) = Self.names(for: a, b) else { continue }
            let results = InteractionChecker.check(nameA, against: [entry(nameB)], policy: .explore)
            guard let worst = results.map(\.severity).max() else {
                disagreements.append("\(rule.classA)|\(rule.classB): no result for \(nameA) + \(nameB)")
                continue
            }
            // The checker takes the worst rule across every class combination of
            // the two substances, so a multi-class representative may legitimately
            // land higher — never lower.
            let singleClass = InteractionChecker.drugClasses(for: nameA) == [a]
                && InteractionChecker.drugClasses(for: nameB) == [b]
                && a != b
            if singleClass ? worst != expected : worst < expected {
                disagreements.append("\(rule.classA)|\(rule.classB): row \(expected) but checker \(worst)")
            }
        }
        #expect(disagreements.isEmpty, "\(disagreements.joined(separator: "\n"))")
    }

    @Test
    func `A rule fires the same way round either way`() {
        for rule in SubstanceStore.shared.classInteractionRules() {
            guard let a = DrugClass(rawValue: rule.classA),
                  let b = DrugClass(rawValue: rule.classB),
                  let (nameA, nameB) = Self.names(for: a, b), nameA != nameB else { continue }
            let forward = InteractionChecker.check(nameA, against: [entry(nameB)], policy: .explore)
            let backward = InteractionChecker.check(nameB, against: [entry(nameA)], policy: .explore)
            #expect(
                forward.map(\.severity).max() == backward.map(\.severity).max(),
                "\(nameA) + \(nameB) is asymmetric",
            )
        }
    }

    @Test
    func `The set of classes no rule mentions is exactly the documented one`() {
        let ruled = Set(DrugClass.allCases.filter(InteractionChecker.hasAnyRule))
        #expect(Set(DrugClass.allCases).subtracting(ruled) == DrugClass.unruled)
    }

    // MARK: - Name overrides

    @Test
    func `Overrides resolve, and every class they name decodes`() {
        let overrides = SubstanceStore.shared.interactionClasses()
        #expect(overrides.count > 200, "the override snapshot looks truncated: \(overrides.count)")
        #expect(overrides.values.allSatisfy { !$0.isEmpty })
    }

    @Test
    func `An override reaches every alias of its substance`() {
        // The override is written under one spelling and the catalog carries the
        // rest. Checking a couple of examples would pass while most of the table
        // silently stopped expanding, so this walks all of them.
        let overrides = SubstanceStore.shared.interactionClasses()
        var lost: [String] = []
        for (name, classes) in overrides {
            guard let substance = SubstanceLibrary.lookup(name) else { continue }
            for alias in substance.aliases {
                let resolved = InteractionChecker.drugClasses(for: alias)
                // An alias shared with another overridden substance legitimately
                // answers for that one instead; only an alias that resolves to
                // nothing has lost the class.
                if resolved.isEmpty { lost.append("\(name) → \(alias)") }
            }
            #expect(!classes.isEmpty, "\(name) has no classes")
        }
        #expect(lost.isEmpty, "aliases that lost their class: \(lost.prefix(10))")
    }

    @Test
    func `A name the catalog does not carry still answers`() {
        // Fourteen overrides name a substance the catalog has no row for. They are
        // live: a person can log a name the library does not have, and these are
        // the ones a rule most needs to reach — xylazine is the "tranq" adulterant
        // whose alpha-2 sedation naloxone does not reverse.
        for name in ["Xylazine", "Medetomidine", "Butalbital", "Timolol", "Reboxetine"] {
            #expect(SubstanceLibrary.lookup(name) == nil, "\(name) now has a catalog row; drop it from this list")
            #expect(!InteractionChecker.drugClasses(for: name).isEmpty, "\(name) lost its class")
        }
    }

    // MARK: - Category fallbacks

    @Test
    func `Every substance category resolves to an interaction class`() {
        // A category with no row falls back to `.other`, which participates in no
        // rule — so a missing row makes every substance under it invisible to the
        // checker, with nothing on screen to say so.
        let mapped = SubstanceStore.shared.categoryInteractionClasses()
        let missing = SubstanceCategory.allCases.filter { mapped[$0.rawValue] == nil }
        #expect(missing.isEmpty, "categories with no interaction class: \(missing.map(\.rawValue))")
    }

    @Test
    func `A substance with no override takes its category's class`() {
        // The fallback path, which the override table would otherwise hide.
        #expect(InteractionChecker.drugClasses(for: "Alprazolam") == [.benzodiazepine])
        #expect(InteractionChecker.drugClasses(for: "Suvorexant") == [.orexinAntagonist])
    }

    // MARK: - Tolerance modulation

    @Test
    func `The tolerance modulation edges are loaded and attenuate`() {
        // Before the store installs them the graph is empty and tolerance develops
        // unmodulated — a silent loss, since nothing renders these.
        let edges = ToleranceModulation.edges(forModulatorClass: .nmdaAntagonist)
        #expect(!edges.isEmpty, "the NMDA edge did not load")
        for edge in edges {
            #expect(edge.muFactor > 0 && edge.muFactor != 1, "an edge that modulates by nothing")
        }
    }

    @Test
    func `A class with no curated edge modulates nothing`() {
        for modulator in [ReceptorClasses.ReceptorClass.gaba, .adenosine, .muOpioid] {
            #expect(ToleranceModulation.edges(forModulatorClass: modulator).isEmpty)
        }
    }
}
