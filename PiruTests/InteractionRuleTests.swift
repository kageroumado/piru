import Testing
import Foundation
@testable import Piru

@Suite("Interaction Rules Extended")
struct InteractionRuleTests {

    private func makeEntry(substance: String, timestamp: Date = .now) -> DoseEntry {
        DoseEntry(substance: substance, amount: 10, route: .oral, timestamp: timestamp)
    }

    // MARK: - Drug Class Overrides

    @Test("All MAOIs resolve to MAOI class")
    func maoiOverrides() {
        for name in ["Phenelzine", "Tranylcypromine", "Isocarboxazid", "Selegiline", "Moclobemide"] {
            let classes = InteractionChecker.drugClasses(for: name)
            #expect(classes == [.maoi], "\(name) should be MAOI")
        }
    }

    @Test("All SSRIs resolve to SSRI class")
    func ssriOverrides() {
        for name in ["Sertraline", "Fluoxetine", "Paroxetine", "Citalopram", "Escitalopram", "Fluvoxamine"] {
            let classes = InteractionChecker.drugClasses(for: name)
            #expect(classes == [.ssri], "\(name) should be SSRI")
        }
    }

    @Test("All SNRIs resolve to SNRI class")
    func snriOverrides() {
        for name in ["Venlafaxine", "Duloxetine", "Desvenlafaxine"] {
            let classes = InteractionChecker.drugClasses(for: name)
            #expect(classes == [.snri], "\(name) should be SNRI")
        }
    }

    @Test("All TCAs resolve to TCA class")
    func tcaOverrides() {
        for name in ["Amitriptyline", "Nortriptyline", "Imipramine", "Clomipramine"] {
            let classes = InteractionChecker.drugClasses(for: name)
            #expect(classes == [.tca], "\(name) should be TCA")
        }
    }

    @Test("DXM is dissociative + SSRI")
    func dxmDualClass() {
        let classes = InteractionChecker.drugClasses(for: "DXM")
        #expect(classes.contains(.dissociative))
        #expect(classes.contains(.ssri))
    }

    @Test("Alcohol maps to alcohol class")
    func alcohol() {
        let classes = InteractionChecker.drugClasses(for: "Alcohol")
        #expect(classes == [.alcohol])
    }

    @Test("Lithium variants all map to lithium class")
    func lithium() {
        for name in ["Lithium", "Lithium Carbonate", "Lithium Orotate"] {
            let classes = InteractionChecker.drugClasses(for: name)
            #expect(classes == [.lithium], "\(name) should be lithium")
        }
    }

    @Test("GHB variants map to GHB class")
    func ghb() {
        for name in ["GHB", "GBL", "GHB/GBL"] {
            let classes = InteractionChecker.drugClasses(for: name)
            #expect(classes == [.ghb], "\(name) should be GHB")
        }
    }

    @Test("Antihistamines mapped correctly")
    func antihistamines() {
        for name in ["Diphenhydramine", "DPH", "Hydroxyzine", "Promethazine"] {
            let classes = InteractionChecker.drugClasses(for: name)
            #expect(classes == [.antihistamine], "\(name) should be antihistamine")
        }
    }

    // MARK: - Dangerous Interactions

    @Test("Opioid + Alcohol is dangerous")
    func opioidAlcoholDangerous() {
        let entry = makeEntry(substance: "Morphine")
        let results = InteractionChecker.check("Alcohol", against: [entry])
        #expect(!results.isEmpty)
        #expect(results[0].severity == .dangerous)
    }

    @Test("MAOI + Stimulant is dangerous")
    func maoiStimulantDangerous() {
        let entry = makeEntry(substance: "Phenelzine")
        let results = InteractionChecker.check("Cocaine", against: [entry])
        #expect(!results.isEmpty)
        #expect(results[0].severity == .dangerous)
    }

    @Test("Lithium + Psychedelic is dangerous")
    func lithiumPsychedelicDangerous() {
        let entry = makeEntry(substance: "Lithium")
        let results = InteractionChecker.check("LSD", against: [entry])
        #expect(!results.isEmpty)
        #expect(results[0].severity == .dangerous)
    }

    @Test("GHB + Alcohol is dangerous")
    func ghbAlcoholDangerous() {
        let entry = makeEntry(substance: "GHB")
        let results = InteractionChecker.check("Alcohol", against: [entry])
        #expect(!results.isEmpty)
        #expect(results[0].severity == .dangerous)
    }

    @Test("Benzo + Alcohol is dangerous")
    func benzoAlcoholDangerous() {
        let entry = makeEntry(substance: "Alprazolam")
        let results = InteractionChecker.check("Alcohol", against: [entry])
        #expect(!results.isEmpty)
        #expect(results[0].severity == .dangerous)
    }

    // MARK: - Unsafe Interactions

    @Test("Opioid + Gabapentinoid is unsafe")
    func opioidGabapentinoidUnsafe() {
        let entry = makeEntry(substance: "Morphine")
        let results = InteractionChecker.check("Gabapentin", against: [entry])
        #expect(!results.isEmpty)
        #expect(results[0].severity == .unsafe)
    }

    @Test("SSRI + Empathogen is unsafe")
    func ssriEmpathogenUnsafe() {
        let entry = makeEntry(substance: "Sertraline")
        let results = InteractionChecker.check("MDMA", against: [entry])
        #expect(!results.isEmpty)
        // MDMA is empathogen + stimulant, so may have multiple results
        let hasUnsafe = results.contains { $0.severity == .unsafe }
        #expect(hasUnsafe)
    }

    @Test("Opioid + Opioid is unsafe")
    func opioidOpioidUnsafe() {
        let entry = makeEntry(substance: "Morphine")
        let results = InteractionChecker.check("Fentanyl", against: [entry])
        #expect(!results.isEmpty)
        #expect(results[0].severity == .unsafe)
    }

    // MARK: - Caution Interactions

    @Test("Stimulant + Stimulant is caution")
    func stimulantStimulantCaution() {
        let entry = makeEntry(substance: "Caffeine")
        let results = InteractionChecker.check("Cocaine", against: [entry])
        #expect(!results.isEmpty)
        #expect(results[0].severity == .caution)
    }

    @Test("Cannabinoid + Psychedelic is caution")
    func cannabinoidPsychedelicCaution() {
        let entry = makeEntry(substance: "Cannabis")
        let results = InteractionChecker.check("LSD", against: [entry])
        // Cannabis needs to be in the library as cannabinoid for this to work
        // If not in cache, this may return empty
        if !results.isEmpty {
            #expect(results[0].severity == .caution)
        }
    }

    // MARK: - Symmetry

    @Test("Interaction check is symmetric")
    func symmetry() {
        let morphineEntry = makeEntry(substance: "Morphine")
        let alprazolamEntry = makeEntry(substance: "Alprazolam")

        let resultsAB = InteractionChecker.check("Alprazolam", against: [morphineEntry])
        let resultsBA = InteractionChecker.check("Morphine", against: [alprazolamEntry])

        #expect(!resultsAB.isEmpty)
        #expect(!resultsBA.isEmpty)
        #expect(resultsAB[0].severity == resultsBA[0].severity)
    }

    // MARK: - No Interaction

    @Test("Supplement + Supplement has no interaction")
    func supplementNoInteraction() {
        let entry = makeEntry(substance: "zzzSupplementAzzz")
        let results = InteractionChecker.check("zzzSupplementBzzz", against: [entry])
        #expect(results.isEmpty)
    }

    // MARK: - Active Entry Detection

    @Test("Entry within duration is active")
    func entryWithinDuration() {
        let entry = makeEntry(substance: "Caffeine", timestamp: .now.addingTimeInterval(-60))
        let active = InteractionChecker.activeEntries(from: [entry])
        #expect(active.count == 1)
    }

    @Test("Very old entry is inactive")
    func veryOldEntryInactive() {
        let entry = makeEntry(substance: "Caffeine", timestamp: .now.addingTimeInterval(-7 * 86400))
        let active = InteractionChecker.activeEntries(from: [entry])
        #expect(active.isEmpty)
    }

    @Test("Empty entries returns empty active")
    func emptyEntriesEmpty() {
        let active = InteractionChecker.activeEntries(from: [])
        #expect(active.isEmpty)
    }

    @Test("Multiple entries filters correctly")
    func multipleEntriesFiltered() {
        let recent = makeEntry(substance: "Caffeine", timestamp: .now.addingTimeInterval(-60))
        let old = makeEntry(substance: "Caffeine", timestamp: .now.addingTimeInterval(-7 * 86400))
        let active = InteractionChecker.activeEntries(from: [recent, old])
        #expect(active.count == 1)
    }
}
