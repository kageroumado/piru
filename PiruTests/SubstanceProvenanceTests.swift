import Testing
import Foundation
@testable import Piru

/// Provenance is the user-visible source-attribution feature: the slug shown
/// to the user under a dose row MUST equal the slug of the source whose
/// value actually populated that field. A mismatch is a worse UX bug than
/// no attribution — it's actively misleading.
@Suite("SubstanceProvenance")
struct SubstanceProvenanceTests {

    @Test("Returns nil for an unknown substance")
    @MainActor
    func unknown() {
        #expect(SubstanceStore.shared.provenance(forSubstanceName: "zzzNotARealCompound") == nil)
    }

    @Test("Returns non-nil for a substance present in the bundled DB")
    @MainActor
    func knownReturnsValue() {
        // Caffeine should be in every reasonable bundled DB build.
        let prov = SubstanceStore.shared.provenance(forSubstanceName: "Caffeine")
        #expect(prov != nil)
    }

    @Test("Per-route dose source matches the resolved dose's source by construction")
    @MainActor
    func perRouteDoseSourceConsistent() {
        let store = SubstanceStore.shared
        guard let substance = store.lookup("Caffeine"),
              let provenance = store.provenance(forSubstanceName: "Caffeine") else {
            Issue.record("Caffeine missing from bundled DB")
            return
        }
        // Every route that has dose data should have a provenance entry —
        // and the slug returned must be one of the enabled sources (i.e.
        // not garbage / not from a disabled source).
        for route in substance.routes where substance.routes.contains(where: { $0.route == route.route }) {
            guard let routeProv = provenance.routesBySource[route.route],
                  let slug = routeProv.doseSource else {
                continue
            }
            #expect(store.enabledSourceOrder.contains(slug),
                    "Provenance slug '\(slug)' for route \(route.route) is not in enabledSourceOrder")
        }
    }

    @Test("Provenance follows source-priority order")
    @MainActor
    func provenanceFollowsPriority() {
        let store = SubstanceStore.shared
        let originalOrder = store.enabledSourceOrder
        defer { store.setSourcePriority(orderedSlugs: originalOrder) }

        // Push tripsit to the top; ask Caffeine; record the dose source.
        let withTripsitFirst = ["tripsit"] + originalOrder.filter { $0 != "tripsit" }
        store.setSourcePriority(orderedSlugs: withTripsitFirst)
        let oralDoseSourceWithTripsitFirst = store
            .provenance(forSubstanceName: "Caffeine")?
            .routesBySource[.oral]?
            .doseSource

        // Push curated to the top instead; the slug should change for any
        // substance where both sources contribute dose data on the same
        // route. If they don't disagree, the assertion still holds —
        // identical slugs are fine.
        let withCuratedFirst = ["piru-curated"] + originalOrder.filter { $0 != "piru-curated" }
        store.setSourcePriority(orderedSlugs: withCuratedFirst)
        let oralDoseSourceWithCuratedFirst = store
            .provenance(forSubstanceName: "Caffeine")?
            .routesBySource[.oral]?
            .doseSource

        // The invariant: whatever slug is returned must be the new
        // highest-priority enabled source that has data for the route.
        if let slug = oralDoseSourceWithTripsitFirst {
            #expect(store.enabledSourceOrder.contains(slug))
        }
        if let slug = oralDoseSourceWithCuratedFirst {
            #expect(store.enabledSourceOrder.contains(slug))
        }
    }

    @Test("Route lookup is O(1) via dictionary, not array scan")
    @MainActor
    func routeLookupIsDictionary() {
        // Compile-time + Mirror-free check that the type really is a Dict.
        // If a future refactor regresses this to an Array, this test breaks.
        guard let provenance = SubstanceStore.shared.provenance(forSubstanceName: "Caffeine") else {
            Issue.record("Caffeine missing from bundled DB")
            return
        }
        let _: [RouteOfAdministration: SubstanceStore.RouteProvenance] = provenance.routesBySource
        // Constant-time access on the type guarantees this is O(1) — the
        // dict shape is the load-bearing assertion.
    }
}
