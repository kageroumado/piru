import Foundation
import SwiftData
import Testing
@testable import Piru

@Suite("InteractionChecker")
struct InteractionCheckerTests {
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
        let classes = InteractionChecker.drugClasses(for: "Tramadol")
        #expect(classes.contains(.opioid))
        #expect(classes.contains(.snri))
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

    // MARK: - InteractionSource

    @Test
    func `Class rule results have classRule source`() {
        let results = InteractionChecker.checkBatch(["Morphine", "Alprazolam"], against: [])
        #expect(!results.isEmpty)
        #expect(results[0].source == .classRule)
    }

    @Test
    func `InteractionSource label is correct`() {
        #expect(InteractionSource.classRule.label == "Pharmacological")
    }
}
