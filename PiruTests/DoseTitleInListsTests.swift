import Foundation
import Testing
@testable import Piru

/// One name per dose on a screen: a list that names a branded dose says the
/// brand, the way the Active Now card and the entry row do.
@Suite("Dose titles in lists")
@MainActor
struct DoseTitleInListsTests {
    private func entry(
        _ substance: String = "Methylphenidate",
        releaseForm: String? = nil,
        productName: String? = nil,
        minutesAgo: Double = 0,
    ) -> DoseEntry {
        DoseEntry(
            substance: substance, amount: 36, unit: "mg", route: .oral,
            releaseForm: releaseForm, productName: productName,
            timestamp: .now.addingTimeInterval(-minutesAgo * 60),
        )
    }

    @Test
    func `A session row names a Concerta dose Concerta`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        let card = SessionCard(
            session: nil, entries: [entry(releaseForm: "XR", productName: "Concerta")], states: [], markers: [],
        )
        #expect(card.substanceSummary == "Concerta")
    }

    @Test
    func `A session row lists two brands of one substance apart`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        let card = SessionCard(
            session: nil,
            entries: [
                entry(releaseForm: "XR", productName: "Concerta", minutesAgo: 60),
                entry(productName: "Ritalin", minutesAgo: 30),
                entry(releaseForm: "XR", productName: "Concerta"),
            ],
            states: [], markers: [],
        )
        #expect(card.substanceSummary == "Concerta, Ritalin")
    }

    @Test
    func `A session row keeps the substance title for an unbranded dose`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let title = try #require(SubstanceLibrary.lookup("Methylphenidate")?.displayTitle)
        let card = SessionCard(session: nil, entries: [entry()], states: [], markers: [])
        #expect(card.substanceSummary == title)
    }

    @Test
    func `Usage gives a branded med its own row`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        let resolved = UsageAnalyticsModel.resolve(entries: [
            entry(releaseForm: "XR", productName: "Concerta", minutesAgo: 120),
            entry(productName: "Ritalin", minutesAgo: 60),
            entry(releaseForm: "XR", productName: "Concerta"),
        ])
        #expect(resolved.substances.map(\.displayName) == ["Concerta", "Ritalin"])
        #expect(resolved.substances.allSatisfy { $0.colorKey == "Methylphenidate" })
        #expect(resolved.snapshots.map(\.substanceIndex) == [0, 1, 0])
    }

    @Test
    func `The effect model's coverage line names the brand`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        let entries = [entry(releaseForm: "XR", productName: "Concerta"), entry("Caffeine")]
        let titles = entries.map { DoseTitle.resolve(for: $0) }
        let partition = SessionResolveModel.mechanisticPartition(entries: entries, titles: titles, pharmacology: [:])
        let all = partition.modeled + partition.ignored
        #expect(all.contains("Concerta"))
        #expect(!all.contains("Methylphenidate"))
    }
}
