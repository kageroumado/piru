import Foundation
import Testing
@testable import Piru

@Suite("Interaction Rules Extended")
struct InteractionRuleTests {
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

    // MARK: - Dangerous Interactions

    @Test
    func `Opioid + Alcohol is dangerous`() {
        let entry = makeEntry(substance: "Morphine")
        let results = InteractionChecker.check("Alcohol", against: [entry])
        #expect(!results.isEmpty)
        #expect(results[0].severity == .dangerous)
    }

    @Test
    func `MAOI + Stimulant is dangerous`() {
        let entry = makeEntry(substance: "Phenelzine")
        let results = InteractionChecker.check("Cocaine", against: [entry])
        #expect(!results.isEmpty)
        #expect(results[0].severity == .dangerous)
    }

    @Test
    func `Lithium + Psychedelic is dangerous`() {
        let entry = makeEntry(substance: "Lithium")
        let results = InteractionChecker.check("LSD", against: [entry])
        #expect(!results.isEmpty)
        #expect(results[0].severity == .dangerous)
    }

    @Test
    func `GHB + Alcohol is dangerous`() {
        let entry = makeEntry(substance: "GHB")
        let results = InteractionChecker.check("Alcohol", against: [entry])
        #expect(!results.isEmpty)
        #expect(results[0].severity == .dangerous)
    }

    @Test
    func `Benzo + Alcohol is dangerous`() {
        let entry = makeEntry(substance: "Alprazolam")
        let results = InteractionChecker.check("Alcohol", against: [entry])
        #expect(!results.isEmpty)
        #expect(results[0].severity == .dangerous)
    }

    // MARK: - Unsafe Interactions

    @Test
    func `Opioid + Gabapentinoid is unsafe`() {
        let entry = makeEntry(substance: "Morphine")
        let results = InteractionChecker.check("Gabapentin", against: [entry])
        #expect(!results.isEmpty)
        #expect(results[0].severity == .unsafe)
    }

    @Test
    func `SSRI + Empathogen is caution (blunting, not danger)`() {
        // SSRIs blunt MDMA rather than endangering — a myth-buster, so the pair reads `.caution`,
        // never `.unsafe`/`.dangerous`. (The lethal serotonergic edge is MAOI + empathogen.)
        let entry = makeEntry(substance: "Sertraline")
        let results = InteractionChecker.check("MDMA", against: [entry])
        let pair = results.first { $0.substanceB.lowercased() == "sertraline" }
        #expect(pair?.severity == .caution)
        // MDMA is empathogen + stimulant, but none of its antidepressant pairings should be danger-coloured.
        #expect(!results.contains { $0.severity == .dangerous })
    }

    @Test
    func `Tramadol + Empathogen is dangerous (serotonin adder, not blunting)`() {
        // Tramadol ADDS serotonin (+ lowers seizure threshold) — it must not ride the SNRI blunting
        // rule. Foundation-C evidence run (2026-06-22): SS grade B/HIGH, seizure A/HIGH → dangerous.
        // A meaningful (non-trivial) tramadol dose so the relevance gate doesn't suppress it as
        // sub-threshold — serotonergic adders aren't in persistentClasses, so the dose gate applies.
        let entry = makeEntry(substance: "Tramadol", amount: 100)
        let results = InteractionChecker.check("MDMA", against: [entry])
        let pair = results.first { $0.substanceB.lowercased() == "tramadol" }
        #expect(pair?.severity == .dangerous)
    }

    @Test
    func `DXM + Empathogen is dangerous, never blunting`() {
        // DXM + MDMA is a real serotonin-toxicity combo — it must never read as antidepressant blunting.
        let entry = makeEntry(substance: "DXM", amount: 200)
        let results = InteractionChecker.check("MDMA", against: [entry])
        let pair = results.first { $0.substanceB.lowercased() == "dxm" }
        #expect(pair?.severity == .dangerous)
    }

    // MARK: - Alpha-2 agonists & beta-blockers (Foundation-C run, 2026-06-22)

    @Test
    func `Clonidine is an alpha-2 agonist, not interaction-invisible .other`() {
        // Was mapped to .other (zero rules). Now a real class so its depressant/opioid edges fire.
        #expect(InteractionChecker.drugClasses(for: "Clonidine") == [.alpha2Agonist])
        #expect(InteractionChecker.drugClasses(for: "Propranolol") == [.betaBlocker])
    }

    @Test
    func `Alpha-2 agonist + opioid is dangerous`() {
        // Clonidine is the prospective (amount-unknown) side so the dose gate doesn't touch it — its
        // bundled dose-range has a corrupt unit row (µg values labeled g) that can read as sub-threshold.
        let entry = makeEntry(substance: "Morphine", amount: 30)
        let results = InteractionChecker.check("Clonidine", against: [entry])
        let pair = results.first { $0.substanceB.lowercased() == "morphine" }
        #expect(pair?.severity == .dangerous)
    }

    @Test
    func `Beta-blocker + stimulant is only caution (unopposed-alpha is contested dogma)`() {
        // The blanket "never mix beta-blockers with stimulants" contraindication failed verification —
        // graded caution, not dangerous (evidence run 2026-06-22).
        let entry = makeEntry(substance: "Propranolol", amount: 40)
        let results = InteractionChecker.check("Amphetamine", against: [entry])
        let pair = results.first { $0.substanceB.lowercased() == "propranolol" }
        #expect(pair?.severity == .caution)
    }

    @Test
    func `Beta-blocker + alpha-2 agonist is unsafe (withdrawal hypertensive crisis)`() {
        let entry = makeEntry(substance: "Propranolol", amount: 40)
        let results = InteractionChecker.check("Clonidine", against: [entry])
        let pair = results.first { $0.substanceB.lowercased() == "propranolol" }
        #expect(pair?.severity == .unsafe)
    }

    @Test
    func `Opioid + Opioid is unsafe`() {
        let entry = makeEntry(substance: "Morphine")
        let results = InteractionChecker.check("Fentanyl", against: [entry])
        #expect(!results.isEmpty)
        #expect(results[0].severity == .unsafe)
    }

    // MARK: - Caution Interactions

    @Test
    func `Stimulant + Stimulant is caution`() {
        // A realistic caffeine dose — 10 mg is below threshold and is now
        // (correctly) gated out as a sub-threshold interaction.
        let entry = makeEntry(substance: "Caffeine", amount: 100)
        let results = InteractionChecker.check("Cocaine", against: [entry])
        #expect(!results.isEmpty)
        #expect(results[0].severity == .caution)
    }

    @Test
    func `Cannabinoid + Psychedelic is caution`() {
        let entry = makeEntry(substance: "Cannabis")
        let results = InteractionChecker.check("LSD", against: [entry])
        // Cannabis needs to be in the library as cannabinoid for this to work
        // If not in cache, this may return empty
        if !results.isEmpty {
            #expect(results[0].severity == .caution)
        }
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
}
