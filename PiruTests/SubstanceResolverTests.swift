import Foundation
import Testing
@testable import Piru

/// Pins the unified set-based route resolver (`SubstanceReadModel.resolveRoutes` +
/// the detail path's auxiliary fold) that collapsed the former batch-vs-detail
/// code paths into one. These assert against the **current bundled DB**
/// (schema v3) via `SubstanceStore.shared.lookup` — the detail/`lookup` path,
/// which is the resolver under test.
///
/// Two kinds of check:
///  1. The **default-salt-mirror invariant** — `makeRoute` is the single point
///     that enforces it, so for every produced route with `saltForms`, the
///     route's top-level `doses`/`unit`/`duration` must equal `saltForms.first`.
///  2. **Structural golden checks** on stable, curated dose values (salt-form
///     sets and `common` ranges) so a future regression in the resolver — or an
///     accidental re-introduction of the per-row N+1 / salt SQL branch with
///     different semantics — is caught. We assert structure/counts and the
///     curated `common` ranges only; brittle internal durations are *not*
///     asserted (a sibling workstream may re-audit salt durations).
@MainActor
@Suite("Substance route resolver")
struct SubstanceResolverTests {
    // MARK: - Default-salt-mirror invariant (the single makeRoute contract)

    /// For every route a resolved substance produces, if it has salt forms then
    /// the top-level ladder must mirror the default (first) salt — the contract
    /// `makeRoute` is the sole enforcement point for. Checked across the
    /// salt-bearing samples plus salt-free controls.
    @Test
    func `Every salted route mirrors its default salt at the top level`() {
        for name in ["Magnesium", "Lithium", "Caffeine", "Methamphetamine"] {
            guard let substance = SubstanceStore.shared.lookup(name) else {
                Issue.record("\(name) missing from bundled DB")
                continue
            }
            for route in substance.routes {
                guard let saltForms = route.saltForms else { continue }
                #expect(!saltForms.isEmpty, "\(name) \(route.route): non-nil saltForms must be non-empty")
                guard let first = saltForms.first else { continue }
                #expect(route.doses == first.doses, "\(name) \(route.route): top-level doses must mirror default salt")
                #expect(route.unit == first.unit, "\(name) \(route.route): top-level unit must mirror default salt")
                #expect(route.duration == first.duration, "\(name) \(route.route): top-level duration must mirror default salt")
            }
        }
    }

    // MARK: - Structural golden checks (current bundled DB, schema v3)

    @Test
    func `Magnesium resolves its three oral salt ladders with curated ranges`() {
        guard let mg = SubstanceStore.shared.lookup("Magnesium") else {
            Issue.record("Magnesium missing from bundled DB")
            return
        }
        #expect(Set(mg.availableSaltForms) == ["Citrate", "Glycinate", "L-Threonate"])
        #expect(Set(mg.saltForms(for: .oral)) == ["Citrate", "Glycinate", "L-Threonate"])
        #expect(mg.doseRange(for: .oral, saltForm: "Citrate")?.common == 400 ... 600)
        #expect(mg.doseRange(for: .oral, saltForm: "Glycinate")?.common == 200 ... 400)
        #expect(mg.doseRange(for: .oral, saltForm: "L-Threonate")?.common == 1_500 ... 2_000)
    }

    @Test
    func `Lithium resolves with no dose ladder and no salt forms`() {
        guard let li = SubstanceStore.shared.lookup("Lithium") else {
            Issue.record("Lithium missing from bundled DB")
            return
        }
        // Prescription-only: the build strips the ladder, and salt forms derive
        // from dose rows, so both go. See SaltFormTests for the full rationale.
        #expect(li.availableSaltForms.isEmpty)
        #expect(li.doseRange(for: .oral, saltForm: "Carbonate") == nil)
    }

    @Test
    func `Caffeine has no salt dimension`() {
        guard let caffeine = SubstanceStore.shared.lookup("Caffeine") else {
            Issue.record("Caffeine missing from bundled DB")
            return
        }
        #expect(caffeine.availableSaltForms.isEmpty)
        for route in caffeine.routes {
            #expect(route.saltForms == nil, "Caffeine \(route.route) must carry no saltForms")
        }
    }

    @Test
    func `A multi-route substance resolves all of its routes (no salt dimension)`() {
        // Methamphetamine carries five distinct routes in the bundled DB and no
        // salt forms — a good probe that the resolver surfaces every route, not
        // just the default.
        guard let meth = SubstanceStore.shared.lookup("Methamphetamine") else {
            Issue.record("Methamphetamine missing from bundled DB")
            return
        }
        let routes = Set(meth.routes.map(\.route))
        let expected: Set<RouteOfAdministration> = [
            .oral, .insufflation, .inhalation, .intravenous, .rectal,
        ]
        #expect(expected.isSubset(of: routes), "expected all of \(expected), got \(routes)")
        #expect(meth.availableSaltForms.isEmpty)
        // Oral is the default route (RouteOfAdministration.allCases order).
        #expect(meth.defaultRoute == .oral)
    }

    // MARK: - Auxiliary route fold (protocol / duration-of-action)

    /// The detail path folds protocol dosing onto its route — exercising
    /// `attachAuxiliaryRoutes`, the MainActor layer that adds the protocol/DOA
    /// data the off-main resolver can't build. BPC-157 is dosed on a
    /// subcutaneous schedule in the bundled DB.
    @Test
    func `A peptide's subcutaneous route carries its protocol dosing`() {
        guard let bpc = SubstanceStore.shared.lookup("BPC-157") else {
            Issue.record("BPC-157 missing from bundled DB")
            return
        }
        let sc = bpc.routes.first { $0.route == .subcutaneous }
        #expect(sc != nil, "BPC-157 should resolve a subcutaneous route")
        #expect(sc?.protocolDosing != nil, "subcutaneous route should carry protocol dosing")
    }

    /// CJC-1295 ships a subcutaneous duration-of-action (release window) in the
    /// bundled DB; the detail path must surface it.
    @Test
    func `A long-acting peptide's route carries its duration-of-action window`() {
        guard let cjc = SubstanceStore.shared.lookup("CJC-1295") else {
            Issue.record("CJC-1295 missing from bundled DB")
            return
        }
        let sc = cjc.routes.first { $0.route == .subcutaneous }
        #expect(sc != nil, "CJC-1295 should resolve a subcutaneous route")
        #expect(sc?.durationOfAction != nil, "subcutaneous route should carry a duration-of-action window")
    }

    // MARK: - Both callers agree (set-based batch vs single-id detail)

    /// The batch loader (`all`) and the detail path (`lookup`) share the resolver
    /// for dose/duration; assert the **dose-bearing** routes they produce for a
    /// salted substance are identical (the detail path additionally folds in
    /// protocol/DOA, absent here, so the route shapes coincide).
    @Test
    func `Batch and detail paths agree on a salted substance's dose ladders`() {
        guard let detail = SubstanceStore.shared.lookup("Magnesium"),
              let browse = SubstanceStore.shared.all.first(where: { $0.name == "Magnesium" }) else {
            Issue.record("Magnesium missing from bundled DB")
            return
        }
        #expect(Set(detail.routes.map(\.route)) == Set(browse.routes.map(\.route)))
        for route in [RouteOfAdministration.oral] {
            #expect(detail.saltForms(for: route) == browse.saltForms(for: route))
            #expect(
                detail.doseRange(for: route, saltForm: "Glycinate")?.common
                    == browse.doseRange(for: route, saltForm: "Glycinate")?.common,
            )
        }
    }
}
