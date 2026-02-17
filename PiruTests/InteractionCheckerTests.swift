import Testing
import SwiftData
import Foundation
@testable import Piru

@Suite("InteractionChecker")
struct InteractionCheckerTests {

    // MARK: - Helpers

    /// Create a DoseEntry using an in-memory SwiftData container
    private static func makeEntry(
        substance: String,
        amount: Double = 10,
        route: RouteOfAdministration = .oral,
        timestamp: Date = .now
    ) throws -> DoseEntry {
        let entry = DoseEntry(
            substance: substance,
            amount: amount,
            route: route,
            timestamp: timestamp
        )
        return entry
    }

    // MARK: - InteractionSeverity

    @Test("Severity ordering")
    func severityOrdering() {
        #expect(InteractionSeverity.caution < .unsafe)
        #expect(InteractionSeverity.unsafe < .dangerous)
        #expect(InteractionSeverity.caution < .dangerous)
    }

    @Test("Severity labels")
    func severityLabels() {
        #expect(InteractionSeverity.caution.label == "Caution")
        #expect(InteractionSeverity.unsafe.label == "Unsafe")
        #expect(InteractionSeverity.dangerous.label == "Dangerous")
    }

    // MARK: - drugClasses()

    @Test("Override substance returns correct class")
    func drugClassOverride() {
        let classes = InteractionChecker.drugClasses(for: "Sertraline")
        #expect(classes == [.ssri])
    }

    @Test("Override is case-insensitive")
    func drugClassOverrideCaseInsensitive() {
        let classes = InteractionChecker.drugClasses(for: "sertraline")
        #expect(classes == [.ssri])
    }

    @Test("Dual-class substance returns multiple classes")
    func drugClassDual() {
        let classes = InteractionChecker.drugClasses(for: "Tramadol")
        #expect(classes.contains(.opioid))
        #expect(classes.contains(.snri))
        #expect(classes.count == 2)
    }

    @Test("MDMA returns empathogen and stimulant")
    func drugClassMDMA() {
        let classes = InteractionChecker.drugClasses(for: "MDMA")
        #expect(classes.contains(.empathogen))
        #expect(classes.contains(.stimulant))
    }

    @Test("Substance from library falls back to category")
    func drugClassFromCategory() {
        // Alprazolam should be in the library as a benzodiazepine
        let classes = InteractionChecker.drugClasses(for: "Alprazolam")
        #expect(classes == [.benzodiazepine])
    }

    @Test("Unknown substance returns empty")
    func drugClassUnknown() {
        let classes = InteractionChecker.drugClasses(for: "zzzNotARealDrugzzz")
        #expect(classes.isEmpty)
    }

    // MARK: - check()

    @Test("Detects dangerous opioid + benzo interaction")
    func dangerousOpioidBenzo() throws {
        let morphineEntry = try Self.makeEntry(substance: "Morphine")
        let results = InteractionChecker.check("Alprazolam", against: [morphineEntry])
        #expect(!results.isEmpty)
        #expect(results[0].severity == .dangerous)
    }

    @Test("Detects dangerous MAOI + SSRI interaction")
    func dangerousMAOISSRI() throws {
        let maoi = try Self.makeEntry(substance: "Phenelzine")
        let results = InteractionChecker.check("Sertraline", against: [maoi])
        #expect(!results.isEmpty)
        #expect(results[0].severity == .dangerous)
    }

    @Test("No interaction for unrelated substances")
    func noInteraction() throws {
        let caffeine = try Self.makeEntry(substance: "Caffeine")
        let results = InteractionChecker.check("Melatonin", against: [caffeine])
        #expect(results.isEmpty)
    }

    @Test("Skips same substance")
    func skipsSameSubstance() throws {
        let caffeine = try Self.makeEntry(substance: "Caffeine")
        let results = InteractionChecker.check("Caffeine", against: [caffeine])
        #expect(results.isEmpty)
    }

    @Test("Skips same substance case-insensitive")
    func skipsSameSubstanceCaseInsensitive() throws {
        let caffeine = try Self.makeEntry(substance: "caffeine")
        let results = InteractionChecker.check("Caffeine", against: [caffeine])
        #expect(results.isEmpty)
    }

    @Test("Deduplicates by substance pair keeping highest severity")
    func deduplicatesByPair() throws {
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

    @Test("Results are sorted by severity descending")
    func resultsSortedBySeverity() throws {
        let maoi = try Self.makeEntry(substance: "Phenelzine")
        let results = InteractionChecker.check("Tramadol", against: [maoi])
        for i in 0..<(results.count - 1) {
            #expect(results[i].severity >= results[i + 1].severity)
        }
    }

    // MARK: - checkBatch()

    @Test("Batch checks within-batch interactions")
    func batchWithinBatch() throws {
        let results = InteractionChecker.checkBatch(
            ["Morphine", "Alprazolam"],
            against: []
        )
        #expect(!results.isEmpty)
        #expect(results[0].severity == .dangerous)
    }

    @Test("Batch combines active entry and within-batch checks")
    func batchCombined() throws {
        let caffeine = try Self.makeEntry(substance: "Caffeine")
        let results = InteractionChecker.checkBatch(
            ["Morphine", "Alprazolam"],
            against: [caffeine]
        )
        // Should at least have the morphine+alprazolam dangerous interaction
        let hasDangerous = results.contains { $0.severity == .dangerous }
        #expect(hasDangerous)
    }

    @Test("Empty batch returns empty results")
    func batchEmpty() throws {
        let results = InteractionChecker.checkBatch([], against: [])
        #expect(results.isEmpty)
    }

    @Test("Batch deduplicates keeping highest severity")
    func batchDeduplicates() throws {
        let results = InteractionChecker.checkBatch(
            ["Morphine", "Alprazolam"],
            against: []
        )
        let pairs = results.map {
            [$0.substanceA, $0.substanceB].sorted().joined(separator: "|")
        }
        let uniquePairs = Set(pairs)
        #expect(pairs.count == uniquePairs.count)
    }

    // MARK: - activeEntries()

    @Test("Recent entry is active")
    func recentEntryActive() throws {
        let entry = try Self.makeEntry(
            substance: "Caffeine",
            timestamp: Date.now.addingTimeInterval(-60) // 1 minute ago
        )
        let active = InteractionChecker.activeEntries(from: [entry])
        #expect(active.count == 1)
    }

    @Test("Old entry is not active")
    func oldEntryInactive() throws {
        let entry = try Self.makeEntry(
            substance: "Caffeine",
            timestamp: Date.now.addingTimeInterval(-86401) // over 24h ago
        )
        let active = InteractionChecker.activeEntries(from: [entry])
        #expect(active.isEmpty)
    }

    @Test("Entry within 24h fallback is active for unknown substance")
    func fallback24h() throws {
        let entry = try Self.makeEntry(
            substance: "zzzUnknownSubstancezzz",
            timestamp: Date.now.addingTimeInterval(-3600) // 1h ago
        )
        let active = InteractionChecker.activeEntries(from: [entry])
        #expect(active.count == 1)
    }

    @Test("Unknown substance entry over 24h is inactive")
    func fallback24hExpired() throws {
        let entry = try Self.makeEntry(
            substance: "zzzUnknownSubstancezzz",
            timestamp: Date.now.addingTimeInterval(-90000) // 25h ago
        )
        let active = InteractionChecker.activeEntries(from: [entry])
        #expect(active.isEmpty)
    }
}
