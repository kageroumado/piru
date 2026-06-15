import Foundation
import Testing
@testable import Piru

/// Salt/ester forms: a route can carry several dose ladders (Magnesium Citrate
/// vs Glycinate vs L-Threonate), nested under one `SubstanceRoute`. The default
/// form is mirrored at the route's top level so salt-unaware code stays correct,
/// and `…(for:saltForm:)` overloads narrow to a chosen form.
@Suite("Salt forms")
struct SaltFormTests {
    /// A multi-salt route: default (top-level) mirrors the first variant.
    private var magnesium: Substance {
        let oral = SubstanceRoute(
            route: .oral,
            unit: "mg",
            doses: DoseRange(common: 400 ... 600), // mirrors Citrate (the default)
            saltForms: [
                SaltVariant(saltForm: "Citrate", unit: "mg", doses: DoseRange(common: 400 ... 600)),
                SaltVariant(saltForm: "Glycinate", unit: "mg", doses: DoseRange(common: 200 ... 400)),
                SaltVariant(saltForm: "L-Threonate", unit: "mg", doses: DoseRange(common: 1_500 ... 2_000)),
            ],
        )
        return Substance(
            name: "Magnesium",
            aliases: [],
            category: .supplement,
            defaultRoute: .oral,
            routes: [oral],
            effects: [],
        )
    }

    /// A normal single-form substance — no salt dimension.
    private var caffeine: Substance {
        Substance(
            name: "Caffeine",
            aliases: [],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(common: 50 ... 100))],
            effects: [],
        )
    }

    // MARK: - Model helpers

    @Test
    func `availableSaltForms preserves stored order`() {
        #expect(magnesium.availableSaltForms == ["Citrate", "Glycinate", "L-Threonate"])
    }

    @Test
    func `saltForms(for:) returns the route's forms`() {
        #expect(magnesium.saltForms(for: .oral) == ["Citrate", "Glycinate", "L-Threonate"])
        #expect(magnesium.saltForms(for: .insufflation).isEmpty)
    }

    @Test
    func `defaultSaltForm is the first form of the default route`() {
        #expect(magnesium.defaultSaltForm == "Citrate")
    }

    @Test
    func `doseRange(for:saltForm:) narrows to the chosen form`() {
        #expect(magnesium.doseRange(for: .oral, saltForm: "Glycinate")?.common == 200 ... 400)
        #expect(magnesium.doseRange(for: .oral, saltForm: "L-Threonate")?.common == 1_500 ... 2_000)
    }

    @Test
    func `doseRange falls back to the default form for nil or unknown salt`() {
        // nil → route default (Citrate); unknown label → route default too.
        #expect(magnesium.doseRange(for: .oral, saltForm: nil)?.common == 400 ... 600)
        #expect(magnesium.doseRange(for: .oral, saltForm: "Sulfate")?.common == 400 ... 600)
    }

    @Test
    func `salt-unaware doseRange equals the default form`() {
        #expect(magnesium.doseRange(for: .oral)?.common == magnesium.doseRange(for: .oral, saltForm: nil)?.common)
    }

    // MARK: - Single-form substances have no salt dimension

    @Test
    func `single-form substance exposes no salt forms`() {
        #expect(caffeine.availableSaltForms.isEmpty)
        #expect(caffeine.saltForms(for: .oral).isEmpty)
        #expect(caffeine.defaultSaltForm == nil)
        // The salt overload still resolves the route's only ladder.
        #expect(caffeine.doseRange(for: .oral, saltForm: nil)?.common == 50 ... 100)
    }

    // MARK: - Bundled DB integration

    @Test
    @MainActor
    func `Magnesium loads its three salt ladders from the bundled DB`() {
        guard let mg = SubstanceStore.shared.lookup("Magnesium") else {
            Issue.record("Magnesium missing from bundled DB")
            return
        }
        #expect(Set(mg.availableSaltForms) == ["Citrate", "Glycinate", "L-Threonate"])
        // Alphabetical ordering puts Citrate first → it's the default.
        #expect(mg.defaultSaltForm == "Citrate")
        // Each salt resolves its own (distinct) ladder.
        #expect(mg.doseRange(for: .oral, saltForm: "Citrate")?.common == 400 ... 600)
        #expect(mg.doseRange(for: .oral, saltForm: "Glycinate")?.common == 200 ... 400)
        #expect(mg.doseRange(for: .oral, saltForm: "L-Threonate")?.common == 1_500 ... 2_000)
    }

    @Test
    @MainActor
    func `Lithium loads Carbonate and Orotate from the bundled DB`() {
        guard let li = SubstanceStore.shared.lookup("Lithium") else {
            Issue.record("Lithium missing from bundled DB")
            return
        }
        #expect(Set(li.availableSaltForms) == ["Carbonate", "Orotate"])
        #expect(li.defaultSaltForm == "Carbonate")
        #expect(li.doseRange(for: .oral, saltForm: "Carbonate")?.common == 600 ... 900)
        #expect(li.doseRange(for: .oral, saltForm: "Orotate")?.common == 125 ... 250)
    }

    @Test
    @MainActor
    func `A single-form bundled substance has no salt dimension`() {
        guard let caffeine = SubstanceStore.shared.lookup("Caffeine") else {
            Issue.record("Caffeine missing from bundled DB")
            return
        }
        #expect(caffeine.availableSaltForms.isEmpty)
    }

    // MARK: - DoseEntry persistence

    @Test
    func `DoseEntry carries an optional saltForm`() {
        let logged = DoseEntry(substance: "Magnesium", amount: 300, unit: "mg", route: .oral, saltForm: "Glycinate")
        #expect(logged.saltForm == "Glycinate")
        let plain = DoseEntry(substance: "Caffeine", amount: 80, unit: "mg", route: .oral)
        #expect(plain.saltForm == nil)
    }
}
