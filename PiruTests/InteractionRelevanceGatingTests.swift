import Foundation
import Testing
@testable import Piru

/// Stage 3a — interaction de-noising. The checker no longer fires on a binary
/// "is it within some window" test: on warn surfaces it reads the same effect
/// curves the timeline draws and gates each pair on real temporal overlap and
/// dose, while the Tools ▸ Interactions explorer still surfaces everything.
@MainActor
@Suite("Interaction Relevance Gating")
struct InteractionRelevanceGatingTests {
    private func entry(
        _ name: String,
        amount: Double = 10,
        route: RouteOfAdministration = .oral,
        hoursAgo: Double = 0,
    ) -> DoseEntry {
        DoseEntry(
            substance: name,
            amount: amount,
            route: route,
            timestamp: Date.now.addingTimeInterval(-hoursAgo * 3_600),
        )
    }

    // MARK: - Class-resolution preconditions

    //
    // The temporal/dose tests below assume these resolutions; assert them up
    // front so a data-layer change produces a clear failure here rather than a
    // confusing one downstream.

    @Test
    func `substances resolve to the expected classes`() {
        #expect(InteractionChecker.drugClasses(for: "Kratom").contains(.opioid))
        #expect(InteractionChecker.drugClasses(for: "Alprazolam").contains(.benzodiazepine))
        #expect(InteractionChecker.drugClasses(for: "Phenelzine").contains(.maoi))
        #expect(InteractionChecker.drugClasses(for: "MDMA").contains(.empathogen))
    }

    // MARK: - Temporal gate (the headline false-red)

    @Test
    func `Kratom in the morning goes silent against a benzo at night`() {
        // Kratom's effect curve (~6 h) is long gone 12 h later; the prospective
        // benzo starts now, so the two curves never co-occur.
        let active = [entry("Kratom", amount: 5, hoursAgo: 12)]
        let results = InteractionChecker.check("Alprazolam", against: active)
        #expect(results.isEmpty, "A faded morning dose must not red-flag tonight's benzo")
    }

    @Test
    func `A concurrent kratom + benzo stays dangerous`() {
        let active = [entry("Kratom", amount: 5, hoursAgo: 0)]
        let results = InteractionChecker.check("Alprazolam", against: active)
        #expect(results.contains { $0.severity == .dangerous })
    }

    // MARK: - Dose gate

    @Test
    func `A clearly sub-threshold active dose is suppressed`() {
        // 0.0001 mg alprazolam (heavy ≈ 2 mg) is pharmacologically nothing — the
        // *interaction* is irrelevant even though both are present now.
        let active = [entry("Alprazolam", amount: 0.0001, hoursAgo: 0)]
        let results = InteractionChecker.check("Kratom", against: active)
        #expect(results.isEmpty, "A trivial dose must not drive an interaction warning")
    }

    @Test
    func `A meaningful concurrent dose still warns`() {
        let active = [entry("Alprazolam", amount: 1.8, hoursAgo: 0)]
        let results = InteractionChecker.check("Kratom", against: active)
        #expect(results.contains { $0.severity == .dangerous })
    }

    // MARK: - Persistent hard edges bypass the gate

    @Test
    func `A MAOI taken a day ago still fires against an empathogen`() {
        // Irreversible MAO inhibition outlasts the subjective curve, so the
        // effect-overlap gate must not silence it.
        let active = [entry("Phenelzine", amount: 15, hoursAgo: 24)]
        let results = InteractionChecker.check("MDMA", against: active)
        #expect(
            results.contains { $0.severity == .dangerous },
            "MAOI + empathogen is a persistent edge and must not be gated away",
        )
    }

    // MARK: - Ordering

    @Test
    func `Results are ordered by relevance, not raw severity`() {
        let active = [
            entry("Alprazolam", amount: 1.8, hoursAgo: 0), // concurrent, dangerous
            entry("Cannabis", amount: 20, hoursAgo: 0), // concurrent, caution
        ]
        let results = InteractionChecker.check("Heroin", against: active)
        // Every adjacent pair must be non-increasing in displayScore.
        for i in 1 ..< max(results.count, 1) where results.count > 1 {
            #expect(results[i - 1].displayScore >= results[i].displayScore)
        }
        // The concurrent dangerous opioid+benzo pair should top the list.
        #expect(results.first?.severity == .dangerous)
    }

    // MARK: - Explore policy never suppresses

    @Test
    func `The manual picker returns rules with no timestamps`() {
        let results = InteractionChecker.checkBatch(["Heroin", "Alprazolam"], against: [], policy: .explore)
        #expect(results.contains { $0.severity == .dangerous })
    }

    @Test
    func `Explore surfaces a faded pair that warn mode would hide`() {
        let active = [entry("Kratom", amount: 5, hoursAgo: 12)]
        let warn = InteractionChecker.checkBatch(["Alprazolam"], against: active, policy: .warn)
        let explore = InteractionChecker.checkBatch(["Alprazolam"], against: active, policy: .explore)
        #expect(warn.isEmpty, "Warn mode hides the faded pair")
        #expect(!explore.isEmpty, "Explore mode surfaces every possible interaction")
    }
}
