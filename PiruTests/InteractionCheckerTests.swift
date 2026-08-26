import Foundation
import SwiftData
import Testing
@testable import Piru

@Suite("InteractionChecker")
struct InteractionCheckerTests {
    init() async {
        await SubstanceStore.shared.ensureAllLoaded()
    }

    // MARK: - Helpers

    /// Create a DoseEntry using an in-memory SwiftData container
    private static func makeEntry(
        substance: String,
        amount: Double = 10,
        route: RouteOfAdministration = .oral,
        timestamp: Date = .now,
    ) throws -> DoseEntry {
        DoseEntry(
            substance: substance,
            amount: amount,
            route: route,
            timestamp: timestamp,
        )
    }

    // MARK: - InteractionSeverity

    @Test
    func `Severity ordering`() {
        #expect(InteractionSeverity.caution < .unsafe)
        #expect(InteractionSeverity.unsafe < .dangerous)
        #expect(InteractionSeverity.caution < .dangerous)
    }

    @Test
    func `Severity labels`() {
        #expect(InteractionSeverity.caution.label == "Caution")
        #expect(InteractionSeverity.unsafe.label == "Unsafe")
        #expect(InteractionSeverity.dangerous.label == "Dangerous")
    }

    // MARK: - drugClasses()

    @Test
    func `Override substance returns correct class`() {
        let classes = InteractionChecker.drugClasses(for: "Sertraline")
        #expect(classes == [.ssri])
    }

    @Test
    func `Override is case-insensitive`() {
        let classes = InteractionChecker.drugClasses(for: "sertraline")
        #expect(classes == [.ssri])
    }

    @Test
    func `Dual-class substance returns multiple classes`() {
        // Tramadol is an opioid AND a serotonin-adder (not a blunting antidepressant), so it rides
        // .serotonergic, not .snri — see the Foundation-C serotonergic run (2026-06-22).
        let classes = InteractionChecker.drugClasses(for: "Tramadol")
        #expect(classes.contains(.opioid))
        #expect(classes.contains(.serotonergic))
        #expect(classes.count == 2)
    }

    @Test
    func `MDMA returns empathogen and stimulant`() {
        let classes = InteractionChecker.drugClasses(for: "MDMA")
        #expect(classes.contains(.empathogen))
        #expect(classes.contains(.stimulant))
    }

    @Test
    func `Substance from library falls back to category`() {
        // Alprazolam should be in the library as a benzodiazepine
        let classes = InteractionChecker.drugClasses(for: "Alprazolam")
        #expect(classes == [.benzodiazepine])
    }

    @Test
    func `Unknown substance returns empty`() {
        let classes = InteractionChecker.drugClasses(for: "zzzNotARealDrugzzz")
        #expect(classes.isEmpty)
    }

    @Test
    func `Alias resolves through the library to the canonical drug class`() {
        // Xanax → Alprazolam → .benzodiazepine. Catches regressions in the
        // lazy `SubstanceLibrary.lookupByNameOrAlias` fallback added when
        // the precomputed cache went away.
        let classes = InteractionChecker.drugClasses(for: "Xanax")
        #expect(classes == [.benzodiazepine])
    }

    @Test
    func `Repeated unknown lookups are stable (negative cache)`() {
        let a = InteractionChecker.drugClasses(for: "zzzAnotherFakeOne")
        let b = InteractionChecker.drugClasses(for: "zzzAnotherFakeOne")
        #expect(a.isEmpty && b.isEmpty)
    }

    // MARK: - check()

    @Test
    func `Detects dangerous opioid + benzo interaction`() throws {
        let morphineEntry = try Self.makeEntry(substance: "Morphine")
        let results = InteractionChecker.check("Alprazolam", against: [morphineEntry])
        #expect(!results.isEmpty)
        #expect(results[0].severity == .dangerous)
    }

    @Test
    func `Detects dangerous MAOI + SSRI interaction`() throws {
        let maoi = try Self.makeEntry(substance: "Phenelzine")
        let results = InteractionChecker.check("Sertraline", against: [maoi])
        #expect(!results.isEmpty)
        #expect(results[0].severity == .dangerous)
    }

    @Test
    func `No interaction for unrelated substances`() throws {
        let caffeine = try Self.makeEntry(substance: "Caffeine")
        let results = InteractionChecker.check("Melatonin", against: [caffeine])
        #expect(results.isEmpty)
    }

    @Test
    func `Skips same substance`() throws {
        let caffeine = try Self.makeEntry(substance: "Caffeine")
        let results = InteractionChecker.check("Caffeine", against: [caffeine])
        #expect(results.isEmpty)
    }

    @Test
    func `Skips same substance case-insensitive`() throws {
        let caffeine = try Self.makeEntry(substance: "caffeine")
        let results = InteractionChecker.check("Caffeine", against: [caffeine])
        #expect(results.isEmpty)
    }

    @Test
    func `Deduplicates by substance pair keeping highest severity`() throws {
        // Tramadol is [opioid, snri], and an MAOI entry should trigger multiple rules
        // but only the highest severity per pair should survive
        let maoi = try Self.makeEntry(substance: "Phenelzine")
        let results = InteractionChecker.check("Tramadol", against: [maoi])
        let pairs = results.map {
            [$0.substanceA, $0.substanceB].sorted().joined(separator: "|")
        }
        let uniquePairs = Set(pairs)
        #expect(pairs.count == uniquePairs.count)
    }

    @Test
    func `Results are sorted by severity descending`() throws {
        let maoi = try Self.makeEntry(substance: "Phenelzine")
        let results = InteractionChecker.check("Tramadol", against: [maoi])
        for i in 0 ..< (results.count - 1) {
            #expect(results[i].severity >= results[i + 1].severity)
        }
    }

    // MARK: - checkBatch()

    @Test
    func `Batch checks within-batch interactions`() {
        let results = InteractionChecker.checkBatch(
            ["Morphine", "Alprazolam"],
            against: [],
        )
        #expect(!results.isEmpty)
        #expect(results[0].severity == .dangerous)
    }

    @Test
    func `Batch combines active entry and within-batch checks`() throws {
        let caffeine = try Self.makeEntry(substance: "Caffeine")
        let results = InteractionChecker.checkBatch(
            ["Morphine", "Alprazolam"],
            against: [caffeine],
        )
        // Should at least have the morphine+alprazolam dangerous interaction
        let hasDangerous = results.contains { $0.severity == .dangerous }
        #expect(hasDangerous)
    }

    @Test
    func `Empty batch returns empty results`() {
        let results = InteractionChecker.checkBatch([], against: [])
        #expect(results.isEmpty)
    }

    @Test
    func `Batch deduplicates keeping highest severity`() {
        let results = InteractionChecker.checkBatch(
            ["Morphine", "Alprazolam"],
            against: [],
        )
        let pairs = results.map {
            [$0.substanceA, $0.substanceB].sorted().joined(separator: "|")
        }
        let uniquePairs = Set(pairs)
        #expect(pairs.count == uniquePairs.count)
    }

    // MARK: - activeEntries()

    @Test
    func `Recent entry is active`() throws {
        let entry = try Self.makeEntry(
            substance: "Caffeine",
            timestamp: Date.now.addingTimeInterval(-60), // 1 minute ago
        )
        let active = InteractionChecker.activeEntries(from: [entry])
        #expect(active.count == 1)
    }

    @Test
    func `Old entry is not active`() throws {
        let entry = try Self.makeEntry(
            substance: "Caffeine",
            timestamp: Date.now.addingTimeInterval(-86_401), // over 24h ago
        )
        let active = InteractionChecker.activeEntries(from: [entry])
        #expect(active.isEmpty)
    }

    @Test
    func `Entry within 24h fallback is active for unknown substance`() throws {
        let entry = try Self.makeEntry(
            substance: "zzzUnknownSubstancezzz",
            timestamp: Date.now.addingTimeInterval(-3_600), // 1h ago
        )
        let active = InteractionChecker.activeEntries(from: [entry])
        #expect(active.count == 1)
    }

    @Test
    func `Unknown substance entry over 24h is inactive`() throws {
        let entry = try Self.makeEntry(
            substance: "zzzUnknownSubstancezzz",
            timestamp: Date.now.addingTimeInterval(-90_000), // 25h ago
        )
        let active = InteractionChecker.activeEntries(from: [entry])
        #expect(active.isEmpty)
    }

    // MARK: - Prominence

    @Test
    func `A dangerous pair may block; a caution pair may not`() throws {
        let danger = try #require(
            InteractionChecker.checkBatch(["Morphine", "Alprazolam"], against: []).first,
        )
        #expect(danger.severity == .dangerous)
        #expect(danger.prominence == .blocking)

        // Two stimulants is real cardiovascular strain and a real `caution` —
        // and the reason the commit gate stopped firing for a coffee.
        let caution = try #require(
            InteractionChecker.checkBatch(["Caffeine", "Amphetamine"], against: []).first,
        )
        #expect(caution.severity == .caution)
        #expect(caution.prominence == .background)
    }

    @Test
    func `A surface floor admits what clears it and counts the rest`() {
        let results = InteractionChecker.checkBatch(
            ["Morphine", "Alprazolam", "Caffeine", "Amphetamine"],
            against: [],
        )
        let admitted = results.admitted(.notable)
        #expect(!admitted.isEmpty)
        #expect(admitted.allSatisfy { $0.severity != .caution })
        #expect(admitted.count + results.belowFloor(.notable) == results.count)
    }

    // MARK: - Bundled class-pair rules

    @Test
    func `TripSit fills pairs curation does not cover`() throws {
        // Tramadol is `serotonergic` here, and no curated rule pairs that class
        // with alcohol, benzodiazepines, GHB or stimulants — every one of which
        // TripSit covers, on seizure and respiratory grounds. A pair with no
        // curated copy shows the row's own note, so a non-empty description is
        // what says the bundled layer reached the reader.
        #expect(InteractionRuleCopy.note(.serotonergic, .alcohol) == nil, "this pair is curated now")
        let results = InteractionChecker.checkBatch(["Tramadol", "Alcohol"], against: [])
        let finding = try #require(results.first)
        #expect(!finding.description.isEmpty)
    }

    @Test
    func `A curated rule wins over the bundled one`() throws {
        // TripSit and curation both name serotonergic + SSRI. The curated verdict
        // is the one that has been checked, and its sentence is the one shown —
        // which is the observable difference, since a TripSit row would arrive as
        // that source's own prose.
        let curated = try #require(InteractionRuleCopy.note(.serotonergic, .ssri))
        let results = InteractionChecker.checkBatch(["Tramadol", "Sertraline"], against: [])
        let finding = try #require(results.first)
        #expect(finding.description == String(localized: curated))
    }

    @Test
    func `The curated MDMA and SSRI adjudication survives the merge`() throws {
        // The folk ordering says danger; the replicated human finding is 30-80%
        // effect blockade. A bundled rule must not overturn that.
        let results = InteractionChecker.checkBatch(["MDMA", "Sertraline"], against: [])
        let finding = try #require(results.first)
        #expect(finding.prominence < .blocking, "blockade must not arrive as a danger")
        #expect(finding.description.localizedCaseInsensitiveContains("blunt"))
    }

    @Test
    func `One or two findings are never folded`() {
        // Folding buys nothing here, and a disclosure reading "1 more" over an
        // empty list reads as an error.
        for names in [["Caffeine", "Amphetamine"], ["Morphine", "Alprazolam"]] {
            let results = InteractionChecker.checkBatch(names, against: [])
            #expect(results.count <= 2)
            let split = results.partitionedForReview()
            #expect(split.shown.count == results.count)
            #expect(split.folded.isEmpty)
        }
    }

    @Test
    func `Past two, the quiet ones move out of the way`() {
        let results = InteractionChecker.checkBatch(
            ["Morphine", "Alprazolam", "Caffeine", "Amphetamine", "Cannabis"],
            against: [],
        )
        #expect(results.count > 2)
        let split = results.partitionedForReview()
        #expect(split.shown.allSatisfy { $0.prominence >= .notable })
        #expect(split.folded.allSatisfy { $0.prominence < .notable })
        #expect(split.shown.count + split.folded.count == results.count)
    }

    @Test
    func `A set that is entirely quiet folds whole`() {
        // Three stimulants: every pairing is a caution, so the count is the
        // honest summary and no single row deserves the space.
        let results = InteractionChecker.checkBatch(
            ["Caffeine", "Amphetamine", "Methylphenidate", "Cocaine"],
            against: [],
        )
        #expect(results.count > 2)
        #expect(results.allSatisfy { $0.prominence < .notable })
        let split = results.partitionedForReview()
        #expect(split.shown.isEmpty)
        #expect(split.folded.count == results.count)
    }

    @Test
    func `The lead clause is the mechanism, without the elaboration`() throws {
        let danger = try #require(
            InteractionChecker.checkBatch(["Morphine", "Alprazolam"], against: []).first,
        )
        #expect(!danger.leadClause.contains("—"))
        #expect(danger.leadClause.count < danger.description.count)
        #expect(!danger.leadClause.isEmpty)
    }
}
