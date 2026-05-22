import Foundation
import Testing
@testable import Piru

@MainActor
@Suite("DoseOverride")
struct DoseOverrideTests {

    /// Build a minimal Substance with one oral route and the supplied dose data.
    private func make(
        name: String,
        aliases: [String] = [],
        oralUnit: String = "mg",
        oralDoses: DoseRange = DoseRange()
    ) -> Substance {
        Substance(
            name: name,
            aliases: aliases,
            category: .other,
            defaultRoute: .oral,
            routes: [SubstanceRoute(route: .oral, unit: oralUnit, doses: oralDoses, duration: nil)],
            effects: []
        )
    }

    @Test("Alcohol override applies when canonical name is Alcohol")
    func alcoholByName() {
        // TripSit serves alcohol with doses in "units" (1-6 scale).
        let raw = make(
            name: "Alcohol",
            aliases: ["etoh", "ethanol", "beer"],
            oralUnit: "units",
            oralDoses: DoseRange(threshold: 1, light: 1...2, common: 2...4, heavy: 6)
        )
        let overridden = SubstanceLibrary.applyDoseOverrides([raw]).first!
        let oral = overridden.routes.first { $0.route == .oral }!
        #expect(oral.unit == "g")
        #expect(oral.doses.threshold == 10)
        #expect(oral.doses.heavy == 60)
    }

    @Test("Alcohol override also applies when canonical name is Ethanol (via alias)")
    func ethanolByAlias() {
        // If TripSit didn't load and the merge settled on PsychonautWiki's
        // "Ethanol", the lookup-by-name would miss the override. The
        // alias-aware lookup catches it via the "alcohol" alias.
        let raw = make(
            name: "Ethanol",
            aliases: ["alcohol", "etoh", "beer"],
            oralUnit: "units",
            oralDoses: DoseRange(threshold: 1, light: 1...2, common: 2...4, heavy: 6)
        )
        let overridden = SubstanceLibrary.applyDoseOverrides([raw]).first!
        let oral = overridden.routes.first { $0.route == .oral }!
        #expect(oral.unit == "g")
        #expect(oral.doses.heavy == 60)
        // 5 (entered as "5 g") should now classify as light, not heavy.
        #expect(oral.doses.level(for: 5) == .sub)
        #expect(oral.doses.level(for: 60) == .heavy)
    }

    // MARK: - Unit aliases

    @Test("Alcohol exposes a 'drink' alias that converts to 14 g of ethanol")
    func alcoholDrinkAlias() {
        let alcohol = make(name: "Alcohol", aliases: ["ethanol"], oralUnit: "g")
        let alias = alcohol.unitAliases.first { $0.label == "drink" }
        #expect(alias?.amountPerUnit == 14)
        #expect(alias?.unit == "g")

        // 2 drinks → 28 g
        let converted = alcohol.convert(amount: 2, from: "drink", toRoute: .oral)
        #expect(converted == 28)
    }

    @Test("Ethanol picks up the same drink alias via the aliases array")
    func ethanolDrinkAliasViaAlias() {
        let ethanol = make(name: "Ethanol", aliases: ["alcohol"], oralUnit: "g")
        let converted = ethanol.convert(amount: 3, from: "drink", toRoute: .oral)
        #expect(converted == 42)
    }

    @Test("Substances without aliases return nil for unknown units")
    func noAliasReturnsNil() {
        let caffeine = make(name: "Caffeine", oralUnit: "mg")
        #expect(caffeine.unitAliases.isEmpty)
        #expect(caffeine.convert(amount: 1, from: "cup", toRoute: .oral) == nil)
    }

    @Test("Mass-unit conversion still works alongside alias resolution")
    func directMassConversionWorks() {
        let alcohol = make(name: "Alcohol", oralUnit: "g")
        // 14 g (the canonical alias amount) is reachable from "mg" directly.
        let converted = alcohol.convert(amount: 14000, from: "mg", toRoute: .oral)
        #expect(converted == 14)
    }

    @Test("Substances without an override key are passed through unchanged")
    func passThrough() {
        let raw = make(
            name: "Caffeine",
            aliases: ["coffee"],
            oralUnit: "mg",
            oralDoses: DoseRange(threshold: 20, light: 20...50, common: 50...150, heavy: 400)
        )
        let result = SubstanceLibrary.applyDoseOverrides([raw]).first!
        let oral = result.routes.first { $0.route == .oral }!
        #expect(oral.unit == "mg")
        #expect(oral.doses.heavy == 400)
    }
}
