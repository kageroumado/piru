import Foundation
import Testing
@testable import Piru

@Suite("ByVolumeDosing")
struct ByVolumeDosingTests {
    // MARK: - Worked examples (exact arithmetic)

    @Test
    func `330 mL can at 5% ABV is ~13 g ethanol`() {
        let g = ByVolumeDosing.grams(volumeML: 330, abv: 5)
        #expect(abs(g - 330 * 0.05 * 0.789) < 1e-9)
        #expect(abs(g - 13.02) < 0.01)
    }

    @Test
    func `175 mL wine at 13% ABV is ~17.9 g ethanol`() {
        let g = ByVolumeDosing.grams(volumeML: 175, abv: 13)
        #expect(abs(g - 17.95) < 0.01)
    }

    @Test
    func `44 mL shot at 40% ABV is ~13.9 g ethanol`() {
        let g = ByVolumeDosing.grams(volumeML: 44, abv: 40)
        #expect(abs(g - 13.89) < 0.01)
    }

    @Test
    func `568 mL pint at 5.2% ABV is ~23.3 g ethanol`() {
        let g = ByVolumeDosing.grams(volumeML: 568, abv: 5.2)
        #expect(abs(g - 23.30) < 0.01)
    }

    // MARK: - Density override

    @Test
    func `density override changes the result proportionally`() {
        let standard = ByVolumeDosing.grams(volumeML: 100, abv: 10)
        let denser = ByVolumeDosing.grams(volumeML: 100, abv: 10, densityGramsPerML: 1.0)
        #expect(abs(standard - 7.89) < 1e-9)
        #expect(abs(denser - 10.0) < 1e-9)
    }

    // MARK: - Guards

    @Test
    func `non-positive and non-finite inputs yield zero`() {
        #expect(ByVolumeDosing.grams(volumeML: 0, abv: 5) == 0)
        #expect(ByVolumeDosing.grams(volumeML: 330, abv: 0) == 0)
        #expect(ByVolumeDosing.grams(volumeML: -100, abv: 5) == 0)
        #expect(ByVolumeDosing.grams(volumeML: 330, abv: -5) == 0)
        #expect(ByVolumeDosing.grams(volumeML: .nan, abv: 5) == 0)
        #expect(ByVolumeDosing.grams(volumeML: 330, abv: .infinity) == 0)
        #expect(ByVolumeDosing.grams(volumeML: 330, abv: 5, densityGramsPerML: 0) == 0)
    }

    // MARK: - Inverse (grams → volume)

    @Test
    func `volumeML inverts grams at a held ABV`() {
        let g = ByVolumeDosing.grams(volumeML: 330, abv: 5)
        let ml = ByVolumeDosing.volumeML(grams: g, abv: 5)
        #expect(abs(ml - 330) < 1e-6)
    }

    @Test
    func `volumeML round-trips a range of drinks`() {
        for (vol, abv) in [(150.0, 13.0), (44.0, 40.0), (500.0, 8.0)] {
            let g = ByVolumeDosing.grams(volumeML: vol, abv: abv)
            #expect(abs(ByVolumeDosing.volumeML(grams: g, abv: abv) - vol) < 1e-6)
        }
    }

    @Test
    func `volumeML guards non-positive and non-finite inputs`() {
        #expect(ByVolumeDosing.volumeML(grams: 0, abv: 5) == 0)
        #expect(ByVolumeDosing.volumeML(grams: 13, abv: 0) == 0)
        #expect(ByVolumeDosing.volumeML(grams: .nan, abv: 5) == 0)
        #expect(ByVolumeDosing.volumeML(grams: 13, abv: .infinity) == 0)
    }

    // MARK: - Standard-drink gloss

    @Test
    func `standard drinks divides grams by 14`() {
        #expect(abs(ByVolumeDosing.standardDrinks(grams: 14) - 1.0) < 1e-9)
        #expect(abs(ByVolumeDosing.standardDrinks(grams: 28) - 2.0) < 1e-9)
        #expect(abs(ByVolumeDosing.standardDrinks(grams: 19.7) - 1.407) < 0.001)
        #expect(ByVolumeDosing.standardDrinks(grams: 0) == 0)
        #expect(ByVolumeDosing.standardDrinks(grams: -5) == 0)
    }

    // MARK: - Capability instance method

    @Test
    func `percentByVolume capability computes grams via its own density`() {
        let cap = ByVolumeDosing.alcohol
        let g = cap.canonicalAmount(volumeML: 500, strength: 5)
        #expect(abs(g - ByVolumeDosing.grams(volumeML: 500, abv: 5)) < 1e-9)
        #expect(cap.canonicalUnit == "g")
    }

    // MARK: - Curated catalog

    @Test
    func `alcohol and ethanol resolve to the same curated capability`() {
        #expect(ByVolumeDosing.catalog["alcohol"] == ByVolumeDosing.alcohol)
        #expect(ByVolumeDosing.catalog["ethanol"] == ByVolumeDosing.alcohol)
        #expect(ByVolumeDosing.catalog["caffeine"] == nil)
    }

    @Test
    func `alcohol presets cover beer wine shot pint with expected volumes`() {
        let presets = ByVolumeDosing.alcohol.drinkPresets
        #expect(presets.map(\.kind) == [.beer, .wine, .shot, .pint])
        let beer = presets.first { $0.kind == .beer }
        #expect(beer?.volume == Measurement(value: 330, unit: .milliliters))
        #expect(beer?.defaultABV == 5)
        let shot = presets.first { $0.kind == .shot }
        #expect(shot?.defaultABV == 40)
    }

    // MARK: - Substance lookup

    @Test
    func `Substance exposes the by-volume capability for alcohol only`() {
        let alcohol = Substance(
            name: "Alcohol", aliases: [], category: .depressant,
            defaultRoute: .oral, routes: [], effects: [],
        )
        #expect(alcohol.byVolumeDosing == ByVolumeDosing.alcohol)

        let caffeine = Substance(
            name: "Caffeine", aliases: [], category: .stimulant,
            defaultRoute: .oral, routes: [], effects: [],
        )
        #expect(caffeine.byVolumeDosing == nil)
    }

    @Test
    func `by-volume capability resolves through a substance alias`() {
        let ethanol = Substance(
            name: "Ethyl alcohol", aliases: ["ethanol"], category: .depressant,
            defaultRoute: .oral, routes: [], effects: [],
        )
        #expect(ethanol.byVolumeDosing == ByVolumeDosing.alcohol)
    }

    // MARK: - Breadcrumb codec (Stage 1 storage / Stage 2 round-trip)

    @Test
    func `breadcrumb formats canonical mL and ABV`() {
        #expect(ByVolumeBreadcrumb.make(volumeML: 330, abv: 5) == "330 mL · 5% ABV")
        #expect(ByVolumeBreadcrumb.make(volumeML: 568, abv: 5.2) == "568 mL · 5.2% ABV")
    }

    @Test
    func `breadcrumb with a name prefixes it`() {
        #expect(ByVolumeBreadcrumb.make(name: "IPA", volumeML: 568, abv: 6) == "IPA · 568 mL · 6% ABV")
        #expect(ByVolumeBreadcrumb.make(name: "  ", volumeML: 330, abv: 5) == "330 mL · 5% ABV")
        #expect(ByVolumeBreadcrumb.make(name: nil, volumeML: 330, abv: 5) == "330 mL · 5% ABV")
    }

    @Test
    func `breadcrumb round-trips through parse`() {
        let crumb = ByVolumeBreadcrumb.make(volumeML: 175, abv: 13)
        let parsed = ByVolumeBreadcrumb.parse(crumb)
        #expect(parsed?.name == nil)
        #expect(parsed?.volumeML == 175)
        #expect(parsed?.abv == 13)
    }

    @Test
    func `named breadcrumb round-trips with its name`() {
        let crumb = ByVolumeBreadcrumb.make(name: "IPA", volumeML: 568, abv: 6)
        let parsed = ByVolumeBreadcrumb.parse(crumb)
        #expect(parsed?.name == "IPA")
        #expect(parsed?.volumeML == 568)
        #expect(parsed?.abv == 6)
    }

    @Test
    func `parse finds the breadcrumb as the leading line above a user note`() {
        let notes = "330 mL · 5% ABV\nfelt relaxed, #chill"
        let parsed = ByVolumeBreadcrumb.parse(notes)
        #expect(parsed?.volumeML == 330)
        #expect(parsed?.abv == 5)
    }

    @Test
    func `parse is case-insensitive and whitespace-tolerant`() {
        let parsed = ByVolumeBreadcrumb.parse("500 ml·12.5 % abv")
        #expect(parsed?.volumeML == 500)
        #expect(parsed?.abv == 12.5)
    }

    @Test
    func `parse returns nil for notes without a breadcrumb`() {
        #expect(ByVolumeBreadcrumb.parse("just a normal note") == nil)
        #expect(ByVolumeBreadcrumb.parse("") == nil)
    }

    @Test
    func `strip removes the breadcrumb line and keeps the user note`() {
        let notes = "330 mL · 5% ABV\nfelt relaxed"
        #expect(ByVolumeBreadcrumb.strip(from: notes) == "felt relaxed")
    }

    @Test
    func `strip yields empty when the breadcrumb is the only content`() {
        #expect(ByVolumeBreadcrumb.strip(from: "330 mL · 5% ABV") == "")
    }
}
