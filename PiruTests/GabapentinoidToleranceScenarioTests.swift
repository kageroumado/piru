import Foundation
import Testing
@testable import Piru

/// Scenario gate for the α2δ class on the **bundled** pharmacology: pregabalin's presence must follow
/// its 6 h plasma half-life, not its 32 nM binding Kᵢ. With the Kᵢ as half-max, one 600 mg dose kept
/// α2δ occupancy at 0.95 two days later and a once-weekly dose read as "mild tolerance" — the
/// 2026-09-22 Discord report ("~4 days to recover" after three weekly doses). Directional assertions
/// only; the class kinetics are graded low and these lock the relationships, not the digits.
@Suite("Gabapentinoid tolerance scenarios")
@MainActor
struct GabapentinoidToleranceScenarioTests {
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func alpha2Delta(_ entries: [DoseEntry], at now: Date = now) -> ClassTolerance? {
        ToleranceStore.simulate(entries: entries, now: now, weightKg: 60) {
            SubstanceStore.shared.pharmacologyParameters(forSubstanceName: $0)
        }[.alpha2Delta]
    }

    private func pregabalin(_ mg: Double, hoursAgo: Double, from now: Date = now) -> DoseEntry {
        DoseEntry(substance: "Pregabalin", amount: mg, timestamp: now.addingTimeInterval(-hoursAgo * 3_600))
    }

    @Test
    func `A single dose has cleared two days later`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let dose = pregabalin(600, hoursAgo: 48)
        let state = try #require(alpha2Delta([dose]))
        #expect(state.occupancyNow < 0.10, "occupancy two days after one dose: \(state.occupancyNow)")
        #expect(ToleranceBucket(responseFraction: state.responseFraction) == .rested)
    }

    @Test
    func `Three doses a week apart do not earn a tolerance card`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        // The reported log: 600 mg, 600 mg a week later, 300 mg eight days after that, read 2.5 days on.
        let entries = [
            pregabalin(600, hoursAgo: 17.5 * 24),
            pregabalin(600, hoursAgo: 10.5 * 24),
            pregabalin(300, hoursAgo: 2.5 * 24),
        ]
        let state = try #require(alpha2Delta(entries))
        #expect(state.severity < ToleranceRow.minimumCardSeverity)
    }

    @Test
    func `Two weeks of daily dosing still reads as tolerance`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        // Sedation habituates over weeks of daily use (Owen 2007) — the effect the class models.
        let entries = (0 ..< 14).map { pregabalin(300, hoursAgo: Double($0) * 24 + 1) }
        let state = try #require(alpha2Delta(entries))
        #expect(state.severity >= ToleranceRow.minimumCardSeverity)
    }
}
