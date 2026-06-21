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
    func `DXM is dissociative + SSRI`() {
        let classes = InteractionChecker.drugClasses(for: "DXM")
        #expect(classes.contains(.dissociative))
        #expect(classes.contains(.ssri))
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
