import Foundation
import Testing
@testable import Piru

@Suite("Interaction Rules Extended")
struct InteractionRuleTests {
    init() async {
        await SubstanceStore.shared.ensureAllLoaded()
    }

    private func makeEntry(substance: String, amount: Double = 10, timestamp: Date = .now) -> DoseEntry {
        DoseEntry(substance: substance, amount: amount, route: .oral, timestamp: timestamp)
    }

    // MARK: - Drug Class Overrides

    @Test
    func `All MAOIs resolve to MAOI class`() {
        for name in ["Phenelzine", "Tranylcypromine", "Isocarboxazid", "Selegiline", "Moclobemide"] {
            let classes = InteractionChecker.drugClasses(for: name)
            #expect(classes == [.maoi], "\(name) should be MAOI")
        }
    }

    @Test
    func `All SSRIs resolve to SSRI class`() {
        for name in ["Sertraline", "Fluoxetine", "Paroxetine", "Citalopram", "Escitalopram", "Fluvoxamine"] {
            let classes = InteractionChecker.drugClasses(for: name)
            #expect(classes == [.ssri], "\(name) should be SSRI")
        }
    }

    @Test
    func `All SNRIs resolve to SNRI class`() {
        for name in ["Venlafaxine", "Duloxetine", "Desvenlafaxine"] {
            let classes = InteractionChecker.drugClasses(for: name)
            #expect(classes == [.snri], "\(name) should be SNRI")
        }
    }

    @Test
    func `All TCAs resolve to TCA class`() {
        for name in ["Amitriptyline", "Nortriptyline", "Imipramine", "Clomipramine"] {
            let classes = InteractionChecker.drugClasses(for: name)
            #expect(classes == [.tca], "\(name) should be TCA")
        }
    }

    @Test
    func `DXM is dissociative + serotonergic adder`() {
        // DXM raises serotonin (reuptake inhibition) — a genuine SS-toxicity adder, not an
        // antidepressant SERT blocker, so it must NOT ride the .ssri "blunting" bucket.
        let classes = InteractionChecker.drugClasses(for: "DXM")
        #expect(classes.contains(.dissociative))
        #expect(classes.contains(.serotonergic))
        #expect(!classes.contains(.ssri))
    }

    @Test
    func `Alcohol maps to alcohol class`() {
        let classes = InteractionChecker.drugClasses(for: "Alcohol")
        #expect(classes == [.alcohol])
    }

    @Test
    func `Lithium variants all map to lithium class`() {
        for name in ["Lithium", "Lithium Carbonate", "Lithium Orotate"] {
            let classes = InteractionChecker.drugClasses(for: name)
            #expect(classes == [.lithium], "\(name) should be lithium")
        }
    }

    @Test
    func `GHB variants map to GHB class`() {
        for name in ["GHB", "GBL", "GHB/GBL"] {
            let classes = InteractionChecker.drugClasses(for: name)
            #expect(classes == [.ghb], "\(name) should be GHB")
        }
    }

    @Test
    func `Antihistamines mapped correctly`() {
        for name in ["Diphenhydramine", "DPH", "Hydroxyzine", "Promethazine"] {
            let classes = InteractionChecker.drugClasses(for: name)
            #expect(classes == [.antihistamine], "\(name) should be antihistamine")
        }
    }

    // MARK: - SSRI + opioid is per-substance, not a blanket opioid rule

    @Test
    func `A non-serotonergic opioid does not trigger an SSRI serotonin rule`() {
        // The old blanket `.opioid + .ssri` rule fired "serotonin syndrome risk" on every opioid, which is
        // noise: oxycodone/morphine/kratom/heroin aren't serotonergic. The genuinely-serotonergic opioids
        // ride `.serotonergic` and are covered below — so a plain opioid + SSRI must surface no SS rule.
        for opioid in ["Oxycodone", "Morphine", "Kratom", "Heroin"] {
            let results = InteractionChecker.check(opioid, against: [makeEntry(substance: "Sertraline")])
            #expect(
                !results.contains { $0.description.localizedCaseInsensitiveContains("serotonin") },
                "\(opioid) + SSRI should not raise a serotonin-syndrome rule",
            )
        }
    }

    @Test
    func `A serotonergic opioid still raises a serotonin rule with an SSRI`() {
        // Tramadol/meperidine are `.serotonergic` — their real SSRI interaction survives the blanket-rule
        // removal via the `.serotonergic + .ssri` rule.
        for opioid in ["Tramadol", "Meperidine"] {
            let results = InteractionChecker.check(opioid, against: [makeEntry(substance: "Sertraline")])
            #expect(
                results.contains { $0.description.localizedCaseInsensitiveContains("serotonin") },
                "\(opioid) + SSRI should still raise a serotonin rule",
            )
        }
    }

    // MARK: - Adjudications that contradict the folk ordering

    //
    // Each of these is a *ranking* claim, not a severity: the absolute tiers are
    // rows now and are gated with their reasoning in
    // `pipeline/build/tests/test_sqlite.py`. What must survive a rebuild is the
    // order, which is the part that was actually adjudicated.

    @Test
    func `An antidepressant SERT blocker ranks below an MAOI with an empathogen`() throws {
        // SSRIs blunt MDMA rather than endangering it — the replicated human
        // finding is 30–80% effect reduction, and no serotonin-syndrome case has
        // MDMA as sole agent. The lethal serotonergic edge is the MAOI. Folk
        // ordering has these the other way round.
        let blunting = InteractionChecker.check("MDMA", against: [makeEntry(substance: "Sertraline")])
            .first { $0.substanceB.lowercased() == "sertraline" }
        let lethal = InteractionChecker.check("MDMA", against: [makeEntry(substance: "Phenelzine")])
            .first { $0.substanceB.lowercased() == "phenelzine" }
        #expect(blunting != nil && lethal != nil)
        #expect(try #require(blunting?.severity) < lethal!.severity, "MDMA + SSRI must rank below MDMA + MAOI")
        #expect(try #require(blunting?.prominence) < .blocking, "blunting must not stop the reader")
    }

    @Test
    func `A serotonin adder outranks a SERT blocker with an empathogen`() throws {
        // Tramadol and DXM *raise* serotonin rather than competing it away, so
        // they stack where an antidepressant blunts. Routing either into the
        // `.ssri` bucket would invert this.
        let blocker = InteractionChecker.check("MDMA", against: [makeEntry(substance: "Sertraline")])
            .first { $0.substanceB.lowercased() == "sertraline" }
        for adder in ["Tramadol", "DXM"] {
            let result = InteractionChecker.check("MDMA", against: [makeEntry(substance: adder, amount: 200)])
                .first { $0.substanceB.lowercased() == adder.lowercased() }
            #expect(result != nil, "MDMA + \(adder) returned nothing")
            #expect(try #require(result?.severity) > blocker!.severity, "MDMA + \(adder) must outrank MDMA + SSRI")
        }
    }

    @Test
    func `A beta-blocker with a stimulant never stops the reader`() throws {
        // The blanket "never mix" contraindication failed verification — large
        // reviews found no real harm. Both still strain the heart, so the pair is
        // shown; it just may not interrupt.
        let pair = InteractionChecker.check("Amphetamine", against: [makeEntry(substance: "Propranolol", amount: 40)])
            .first { $0.substanceB.lowercased() == "propranolol" }
        #expect(pair != nil, "beta-blocker + stimulant returned nothing")
        #expect(try #require(pair?.prominence) < .blocking)
    }

    @Test
    func `Alpha-2 agonist plus opioid stops the reader`() {
        // The xylazine/"tranq" reality: naloxone reverses the opioid and not the
        // alpha-2 sedation, which is why this one has to interrupt. Clonidine is
        // the prospective (amount-unknown) side so the dose gate leaves it alone —
        // its bundled dose range has a corrupt unit row that can read as
        // sub-threshold.
        let pair = InteractionChecker.check("Clonidine", against: [makeEntry(substance: "Morphine", amount: 30)])
            .first { $0.substanceB.lowercased() == "morphine" }
        #expect(pair != nil, "alpha-2 + opioid returned nothing")
        #expect(pair?.prominence == .blocking)
    }

    // MARK: - Orexin antagonists (DORAs)

    @Test
    func `DORAs resolve to the orexinAntagonist class, not interaction-invisible .other`() {
        // Before: category Depressant → .other → zero rules (interaction-invisible).
        // Now a real class so their additive-sedation cautions fire.
        for name in ["Suvorexant", "Lemborexant", "Daridorexant"] {
            #expect(InteractionChecker.drugClasses(for: name) == [.orexinAntagonist], "\(name)")
        }
    }

    @Test
    func `DORA + opioid is caution, never the benzo-opioid danger tier`() {
        // DORAs add next-day sedation/fall risk but do NOT depress brainstem respiration,
        // so this must read caution — explicitly below the benzo+opioid respiratory-death tier.
        let entry = makeEntry(substance: "Morphine", amount: 30)
        let results = InteractionChecker.check("Suvorexant", against: [entry])
        let pair = results.first { $0.substanceB.lowercased() == "morphine" }
        #expect(pair?.severity == .caution)
        #expect(!results.contains { $0.severity == .dangerous }, "DORA + opioid must never be dangerous")
    }

    @Test
    func `DORA + alcohol is caution, not the benzo+alcohol danger`() {
        // Benzo + alcohol is dangerous; DORA + alcohol is additive impairment, not lethal synergy.
        let entry = makeEntry(substance: "Alcohol", amount: 20)
        let results = InteractionChecker.check("Lemborexant", against: [entry])
        let pair = results.first { $0.substanceB.lowercased() == "alcohol" }
        #expect(pair?.severity == .caution)
        #expect(!results.contains { $0.severity == .dangerous })
    }

    // MARK: - Symmetry

    @Test
    func `Interaction check is symmetric`() {
        let morphineEntry = makeEntry(substance: "Morphine")
        let alprazolamEntry = makeEntry(substance: "Alprazolam")

        let resultsAB = InteractionChecker.check("Alprazolam", against: [morphineEntry])
        let resultsBA = InteractionChecker.check("Morphine", against: [alprazolamEntry])

        #expect(!resultsAB.isEmpty)
        #expect(!resultsBA.isEmpty)
        #expect(resultsAB[0].severity == resultsBA[0].severity)
    }

    // MARK: - No Interaction

    @Test
    func `Supplement + Supplement has no interaction`() {
        let entry = makeEntry(substance: "zzzSupplementAzzz")
        let results = InteractionChecker.check("zzzSupplementBzzz", against: [entry])
        #expect(results.isEmpty)
    }

    // MARK: - Active Entry Detection

    @Test
    func `Entry within duration is active`() {
        let entry = makeEntry(substance: "Caffeine", timestamp: .now.addingTimeInterval(-60))
        let active = InteractionChecker.activeEntries(from: [entry])
        #expect(active.count == 1)
    }

    @Test
    func `Very old entry is inactive`() {
        let entry = makeEntry(substance: "Caffeine", timestamp: .now.addingTimeInterval(-7 * 86_400))
        let active = InteractionChecker.activeEntries(from: [entry])
        #expect(active.isEmpty)
    }

    @Test
    func `Empty entries returns empty active`() {
        let active = InteractionChecker.activeEntries(from: [])
        #expect(active.isEmpty)
    }

    @Test
    func `Multiple entries filters correctly`() {
        let recent = makeEntry(substance: "Caffeine", timestamp: .now.addingTimeInterval(-60))
        let old = makeEntry(substance: "Caffeine", timestamp: .now.addingTimeInterval(-7 * 86_400))
        let active = InteractionChecker.activeEntries(from: [recent, old])
        #expect(active.count == 1)
    }

    // MARK: - Rule identity

    @Test
    func `Two rules sharing boilerplate prose stay distinguishable`() {
        // `barbiturate + antipsychotic` and `alcohol + antipsychotic` are
        // written against the same sentence. A display surface that groups on
        // prose folds them into one finding and asserts a cause they do not
        // share; grouping on `ruleKey` keeps them apart.
        let results = InteractionChecker.checkBatch(
            ["Phenobarbital", "Alcohol", "Aripiprazole"],
            against: [],
            policy: .explore,
        )
        let shared = results.filter { $0.description.contains("Additive CNS depression") }
        #expect(shared.count == 2)
        #expect(Set(shared.map(\.ruleKey)).count == 2)
        #expect(shared.allSatisfy { !$0.ruleKey.isEmpty })
    }
}
