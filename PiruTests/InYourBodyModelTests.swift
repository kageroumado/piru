import Foundation
import Testing
@testable import Piru

/// What In Your Body's cards state beside the chart: when an active substance leaves the active
/// list, and where a regular schedule stands on its plateau.
@MainActor
@Suite("In Your Body models")
struct InYourBodyModelTests {
    private let now = Date.now

    private func daily(_ substance: String, mg: Double, days: Int) -> [DoseEntry] {
        (0 ..< days).map { day in
            DoseEntry(
                substance: substance, amount: mg, unit: "mg", route: .oral,
                timestamp: now.addingTimeInterval(-Double(day) * 86_400 - 3 * 3_600),
            )
        }
    }

    @Test
    func `An active substance says when its last dose stops counting as active`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let first = DoseEntry(substance: "Caffeine", amount: 100, unit: "mg", route: .oral, timestamp: now.addingTimeInterval(-4 * 3_600))
        let second = DoseEntry(substance: "Caffeine", amount: 100, unit: "mg", route: .oral, timestamp: now.addingTimeInterval(-3_600))
        let lone = try #require(ActiveSubstanceCalculator.compute(from: [first], colorMap: [:], now: now).first)
        let both = try #require(ActiveSubstanceCalculator.compute(from: [first, second], colorMap: [:], now: now).first)
        let loneUntil = try #require(lone.activeUntil)
        let bothUntil = try #require(both.activeUntil)
        #expect(loneUntil > now)
        // The newer dose is the last to fall below the floor, three hours after the older one.
        #expect(abs(bothUntil.timeIntervalSince(loneUntil) - 3 * 3_600) < 60)
        // Past the stated time the calculator no longer lists the substance.
        let after = ActiveSubstanceCalculator.compute(from: [first, second], colorMap: [:], now: bothUntil.addingTimeInterval(120))
        #expect(after.isEmpty)
    }

    /// The single-daily case: sertraline every morning for months reached its plateau long ago, so
    /// the card says by when, and carries today's modeled amount.
    @Test
    func `A schedule older than its settling time reads as settled`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let projection = try #require(
            SteadyStateProjectionBuilder.compute(entries: daily("Sertraline", mg: 100, days: 150), colorMap: [:], now: now).first,
        )
        #expect(projection.isSettled)
        #expect(projection.settledBy < now)
        #expect(projection.currentAmount > projection.result.troughAmount * 0.9)
        #expect(projection.currentAmount < projection.result.peakAmount * 1.1)
    }

    @Test
    func `A schedule younger than its settling time is still climbing`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let projection = try #require(
            SteadyStateProjectionBuilder.compute(entries: daily("Sertraline", mg: 100, days: 5), colorMap: [:], now: now).first,
        )
        #expect(!projection.isSettled)
        #expect(projection.elapsedMinutes < projection.result.time95)
        #expect(projection.elapsedMinutes > 4 * 1_440)
    }
}
