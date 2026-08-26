import Foundation
import Testing
@testable import Piru

/// The by-volume dose input and the saturable-elimination curve both read the bundled DB
/// (`by_volume_dosing`, `drink_presets`, `zero_order_kinetics`). These tests gate the properties a
/// rebuild can break, and — the load-bearing part — that the two declarations of the ethanol
/// density and the standard-drink mass agree.
///
/// The compiled pair exists because the watch has no database and the shared curve engine runs
/// inside the widget and Live Activity, which link no GRDB. That is a real constraint, not a
/// convenience: what it must never become is a second answer. Individual values are not restated
/// beyond that comparison — the pipeline's `test_by_volume_*` gates the rows against their source.
@Suite("ByVolumeDosingDB")
struct ByVolumeDosingDBTests {
    /// The store's index build is what installs `ByVolumeCatalog`, so every test here needs it up.
    init() {
        MainActor.assumeIsolated { _ = SubstanceStore.shared }
    }

    private func alcohol() -> ByVolumeDosing? {
        ByVolumeCatalog.capability(forAnyOf: ["Alcohol"])
    }

    // MARK: - The two declarations must agree

    /// `ByVolumeDosing.ethanolDensityGramsPerML` is the copy the watch and the pure engine
    /// conversions run on; `by_volume_dosing.density_g_per_ml` is the one the app resolves. A drift
    /// between them would show the same pour as two different masses depending on which device
    /// computed it, with nothing on either screen to reveal it.
    @Test
    func `Compiled ethanol density equals the database row`() throws {
        let capability = try #require(alcohol(), "no by_volume_dosing row for Alcohol")
        guard case let .percentByVolume(density) = capability.concentration else {
            Issue.record("Alcohol is not a percent-by-volume substance")
            return
        }
        #expect(density == ByVolumeDosing.ethanolDensityGramsPerML)
    }

    /// Same contract for the standard-drink mass, which has one more consumer than the density:
    /// `TimelineCurveModel.zeroOrderDoseMilligrams` converts a dose logged in "drinks" with it
    /// inside the widget, where the row is unreachable.
    @Test
    func `Compiled standard-drink mass equals the database row`() throws {
        let capability = try #require(alcohol(), "no by_volume_dosing row for Alcohol")
        #expect(capability.standardUnitMass == ByVolumeDosing.usStandardDrinkGrams)
        #expect(capability.canonicalUnit == "g")
    }

    /// The colloquial unit the dose form offers comes from the same row as the mass behind it, so a
    /// "drink" the user picks and the grams it becomes cannot be sourced from different places.
    @Test
    @MainActor
    func `The drink unit alias is the capability's standard unit`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let substance = try #require(SubstanceLibrary.lookup("Alcohol"))
        let capability = try #require(substance.byVolumeDosing)
        let alias = try #require(substance.unitAliases.first { $0.label == capability.standardUnitLabel })
        #expect(alias.amountPerUnit == capability.standardUnitMass)
        #expect(alias.unit == capability.canonicalUnit)
    }

    // MARK: - Capability resolution

    /// The capability is keyed by canonical name *and* alias, so a dose logged as "Ethanol" gets the
    /// by-volume panel rather than a bare mass field.
    @Test
    func `Alcohol resolves through its aliases and nothing else does`() {
        let canonical = alcohol()
        #expect(canonical != nil)
        #expect(ByVolumeCatalog.capability(forAnyOf: ["ethanol"]) == canonical)
        #expect(ByVolumeCatalog.capability(forAnyOf: ["ETHYL ALCOHOL"]) == canonical)
        #expect(ByVolumeCatalog.capability(forAnyOf: ["Caffeine"]) == nil)
    }

    /// The capability converts through its own stored density, not the compiled default — the
    /// property that lets a second adopter land as a row rather than a code change.
    @Test
    func `Capability converts through its own density`() throws {
        let capability = try #require(alcohol())
        let viaCapability = capability.canonicalAmount(volumeML: 500, strength: 5)
        #expect(abs(viaCapability - ByVolumeDosing.grams(volumeML: 500, abv: 5)) < 1e-9)
    }

    /// Presets are what the By-Drink panel and the watch both log from. Their identities and their
    /// order come from the DB; an empty list would silently turn the panel into a bare volume field.
    @Test
    func `Alcohol ships an ordered set of known drink presets`() throws {
        let capability = try #require(alcohol())
        #expect(!capability.drinkPresets.isEmpty, "the By-Drink panel has no chips to offer")
        #expect(Set(capability.drinkPresets.map(\.kind)).count == capability.drinkPresets.count)
        for preset in capability.drinkPresets {
            #expect(preset.volume.converted(to: .milliliters).value > 0)
            #expect(preset.defaultABV > 0)
        }
    }

    /// The wire form the watch renders is built from the same capability the phone's panel uses, so
    /// a preset cannot mean one volume on the phone and another on the wrist.
    @Test
    func `Watch preset payload matches the resolved capability`() throws {
        let capability = try #require(alcohol())
        let wire = ManifestDrinkPreset.wireForm(of: capability)
        #expect(wire.map(\.id) == capability.drinkPresets.map(\.kind.rawValue))
        for (sent, preset) in zip(wire, capability.drinkPresets) {
            #expect(sent.volumeML == preset.volume.converted(to: .milliliters).value)
            #expect(sent.defaultABV == preset.defaultABV)
        }
    }

    // MARK: - Zero-order elimination

    /// The switch onto the dose-scaled linear-decline curve is the presence of a `zero_order_kinetics`
    /// row, replacing a `case "alcohol", "ethanol"` string comparison in the curve engine. This is
    /// the test that the replacement actually engages — and that it engages through an alias too.
    @Test
    @MainActor
    func `Alcohol resolves zero-order kinetics and other substances do not`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        let store = SubstanceStore.shared
        let kinetics = store.zeroOrderKinetics(forSubstanceName: "Alcohol", weightKg: 60)
        #expect(kinetics != nil, "no zero_order_kinetics row reached the curve for Alcohol")
        #expect(store.zeroOrderKinetics(forSubstanceName: "ethanol", weightKg: 60) == kinetics)
        #expect(store.zeroOrderKinetics(forSubstanceName: "Caffeine", weightKg: 60) == nil)
        guard let kinetics else { return }
        #expect(kinetics.vmaxMgPerMin > 0)
        #expect(kinetics.ka > 0)
        #expect(kinetics.bioavailability > 0 && kinetics.bioavailability <= 1)
    }

    /// The curve's bioavailability is the substance's own resolved `pk_routes` F — not a second
    /// number kept beside the Vmax. If the zero-order table ever grows an F column, this fails.
    @Test
    @MainActor
    func `Zero-order bioavailability is the resolved pharmacology parameter`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        let store = SubstanceStore.shared
        let kinetics = store.zeroOrderKinetics(forSubstanceName: "Alcohol", weightKg: 60)
        let resolved = store.pharmacologyParameters(forSubstanceName: "Alcohol").bioavailabilityFraction ?? 1
        #expect(kinetics?.bioavailability == resolved)
    }

    /// Elimination throughput tracks lean/liver mass, so `Vmax` scales linearly with weight — the
    /// property that makes the same dose draw a narrower curve on a heavier person. Held at the band
    /// edges rather than extrapolated.
    @Test
    @MainActor
    func `Vmax scales with weight inside the modeled band and is held outside it`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        let store = SubstanceStore.shared
        guard let at60 = store.zeroOrderKinetics(forSubstanceName: "Alcohol", weightKg: 60),
              let at120 = store.zeroOrderKinetics(forSubstanceName: "Alcohol", weightKg: 120) else {
            Issue.record("no zero-order kinetics for Alcohol")
            return
        }
        #expect(abs(at120.vmaxMgPerMin - 2 * at60.vmaxMgPerMin) < 1e-9)
        let tiny = store.zeroOrderKinetics(forSubstanceName: "Alcohol", weightKg: 5)
        let huge = store.zeroOrderKinetics(forSubstanceName: "Alcohol", weightKg: 999)
        #expect(tiny == store.zeroOrderKinetics(forSubstanceName: "Alcohol", weightKg: PKModel.minimumModeledWeightKg))
        #expect(huge == store.zeroOrderKinetics(forSubstanceName: "Alcohol", weightKg: PKModel.maximumModeledWeightKg))
    }

    /// A dose logged as "2 drinks" must reach the zero-order model at the standard-drink mass rather
    /// than falling through to the phase bell — the conversion that runs inside the widget, where
    /// only the compiled constant is reachable.
    @Test
    func `A dose in drinks converts at the standard-drink mass`() {
        let two = TimelineCurveModel.zeroOrderDoseMilligrams(amount: 2, unit: "drinks")
        #expect(two == 2 * ByVolumeDosing.usStandardDrinkGrams * 1_000)
        #expect(TimelineCurveModel.zeroOrderDoseMilligrams(amount: 2, unit: "g") == 2_000)
        // A volume is not a mass: mL of a drink must fall back rather than be read as milligrams.
        #expect(TimelineCurveModel.zeroOrderDoseMilligrams(amount: 330, unit: "mL") == nil)
    }

    /// The state the widget and Live Activity render carries the kinetics, so those processes reach
    /// the same verdict the app does without a database. A state built for a first-order substance
    /// must carry none, or every dose would draw the alcohol shape.
    @Test
    @MainActor
    func `A built state carries the kinetics the renderers need`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let duration = DurationProfile(
            onset: DurationRange(min: 10, max: 20),
            comeup: DurationRange(min: 20, max: 40),
            peak: DurationRange(min: 45, max: 75),
            offset: DurationRange(min: 90, max: 150),
            afterglow: nil,
            total: DurationRange(min: 180, max: 270),
        )
        let alcohol = ActiveSubstanceState(
            name: "Alcohol", colorHex: "FFFFFF", timestamp: .now, amount: 28, unit: "g",
            routeDisplayName: "Oral", duration: duration, category: .depressant,
            weightKg: 60,
            zeroOrderKinetics: SubstanceStore.shared.zeroOrderKinetics(forSubstanceName: "Alcohol", weightKg: 60),
        )
        #expect(alcohol?.zeroOrder != nil)
        #expect(try TimelineCurveModel.zeroOrderKinetics(for: #require(alcohol)) != nil)

        let caffeine = ActiveSubstanceState(
            name: "Caffeine", colorHex: "FFFFFF", timestamp: .now, amount: 100, unit: "mg",
            routeDisplayName: "Oral", duration: duration, category: .stimulant,
            zeroOrderKinetics: SubstanceStore.shared.zeroOrderKinetics(forSubstanceName: "Caffeine", weightKg: 60),
        )
        #expect(caffeine?.zeroOrder == nil)
    }

    /// The payload is an append-only contract shared with a widget that can be a build behind. A
    /// state encoded without the field must decode as first-order rather than failing to decode.
    @Test
    @MainActor
    func `A state from an older build decodes as first-order`() throws {
        let json = """
        {"substanceName":"Alcohol","colorHex":"FFFFFF","doseTimestamp":0,"amount":28,"unit":"g",
         "route":"Oral","onsetEndMinutes":15,"comeupEndMinutes":45,"peakEndMinutes":105,
         "offsetEndMinutes":225,"totalMinutes":225}
        """
        let decoded = try JSONDecoder().decode(ActiveSubstanceState.self, from: Data(json.utf8))
        #expect(decoded.zeroOrder == nil)
        #expect(TimelineCurveModel.zeroOrderKinetics(for: decoded) == nil)
    }
}
