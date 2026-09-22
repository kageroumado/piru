import Foundation
import Testing
@testable import Piru

@Suite("Oklch Display P3")
struct OklchDisplayP3Tests {
    /// Reference values from `design-system/color/colorimetry.py`
    /// (`oklch_to_rgb(space="p3")`, `fit_chroma(space="p3")`). That module
    /// reaches Oklab through XYZ and `Oklch` uses Ottosson's direct sRGB
    /// matrices; the two agree to ~4e-4 per component, so the tolerance is a
    /// quarter of one 8-bit code value.
    private static let tolerance = 1e-3

    @Test(arguments: [
        (Oklch(l: 0.765, c: 0.175, h: 62.6), P3Color(red: 0.94274, green: 0.60431, blue: 0.21763)),
        (Oklch(l: 0.615, c: 0.213, h: 312.4), P3Color(red: 0.64043, green: 0.34215, blue: 0.84269)),
        (Oklch(l: 0.648, c: 0.007, h: 285.9), P3Color(red: 0.55660, green: 0.55661, blue: 0.57347)),
    ])
    func `Matches the design-system converter`(color: Oklch, expected: P3Color) {
        let p3 = color.displayP3
        #expect(abs(p3.red - expected.red) < Self.tolerance)
        #expect(abs(p3.green - expected.green) < Self.tolerance)
        #expect(abs(p3.blue - expected.blue) < Self.tolerance)
    }

    @Test
    func `Chroma ceiling matches the design-system gamut fit`() {
        #expect(abs(Oklch.displayP3ChromaCeiling(l: 0.7, h: 145) - 0.29866) < Self.tolerance)
    }

    @Test
    func `An out-of-gamut color keeps lightness and hue and lands on the ceiling`() {
        let wild = Oklch(l: 0.7, c: 0.4, h: 145)
        #expect(!wild.isInDisplayP3)
        let fitted = wild.fittedToDisplayP3
        #expect(fitted.isInDisplayP3)
        #expect(fitted.l == wild.l)
        #expect(fitted.h == wild.h)
        #expect(abs(fitted.c - 0.29866) < Self.tolerance)
    }

    @Test
    func `A color beyond sRGB survives the P3 round trip`() {
        let vivid = Oklch(l: 0.7, c: 0.28, h: 145)
        let back = Oklch(displayP3: vivid.displayP3)
        #expect(abs(back.l - vivid.l) < 1e-6)
        #expect(abs(back.c - vivid.c) < 1e-6)
        #expect(abs(back.h - vivid.h) < 1e-4)
    }
}

@Suite("SubstanceColorGenerator")
struct SubstanceColorGeneratorTests {
    private static let hueJitter = 10.0

    private func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    /// The tripwire: a change to the hash, the streams or the band recolors
    /// every user's journal, so it has to be deliberate.
    @Test
    func `Pinned colors stay put`() {
        let amphetamine = SubstanceColorGenerator.color(category: .stimulant, seed: "KWTSXDURSIMDCE")
        let lsd = SubstanceColorGenerator.color(category: .psychedelic, seed: "VAYOSLLFUXYJDT")
        #expect(abs(amphetamine.l - Self.pinnedAmphetamine.l) < 1e-9)
        #expect(abs(amphetamine.c - Self.pinnedAmphetamine.c) < 1e-9)
        #expect(abs(amphetamine.h - Self.pinnedAmphetamine.h) < 1e-9)
        #expect(abs(lsd.l - Self.pinnedLSD.l) < 1e-9)
        #expect(abs(lsd.c - Self.pinnedLSD.c) < 1e-9)
        #expect(abs(lsd.h - Self.pinnedLSD.h) < 1e-9)
    }

    private static let pinnedAmphetamine = Oklch(l: 0.7451375251428101, c: 0.17061943064171395, h: 54.20993733345348)
    private static let pinnedLSD = Oklch(l: 0.6510313115503726, c: 0.21530413367688286, h: 316.9249603689005)

    @Test(arguments: SubstanceCategory.allCases)
    func `Every class stays in its hue family, in gamut, in the legible band`(category: SubstanceCategory) {
        for index in 0 ..< 200 {
            let color = SubstanceColorGenerator.color(category: category, seed: "SEED\(index)")
            #expect(color.isInDisplayP3)
            #expect((0.60 ... 0.82).contains(color.l))
            if category != .other {
                #expect(hueDistance(color.h, category.oklchSeed.h) <= Self.hueJitter + 1e-9)
            }
        }
    }

    @Test
    func `The gray class spreads around the wheel at low chroma`() {
        let colors = (0 ..< 200).map { SubstanceColorGenerator.color(category: .other, seed: "SEED\($0)") }
        let sextants = Set(colors.map { Int($0.h / 60) })
        #expect(sextants.count == 6)
        #expect(colors.allSatisfy { $0.c <= 0.09 + 1e-9 })
    }

    @Test
    func `Siblings in one class are mostly tellable apart`() {
        let colors = (0 ..< 12).map { SubstanceColorGenerator.color(category: .stimulant, seed: "SIBLING\($0)") }
        var close = 0
        var pairs = 0
        for i in colors.indices {
            for j in colors.indices where j > i {
                pairs += 1
                if oklabDistance(colors[i], colors[j]) < 0.03 { close += 1 }
            }
        }
        #expect(Double(close) / Double(pairs) < 0.15)
    }

    private func oklabDistance(_ x: Oklch, _ y: Oklch) -> Double {
        let (xa, xb) = (x.c * cos(x.h * .pi / 180), x.c * sin(x.h * .pi / 180))
        let (ya, yb) = (y.c * cos(y.h * .pi / 180), y.c * sin(y.h * .pi / 180))
        return sqrt(pow(x.l - y.l, 2) + pow(xa - ya, 2) + pow(xb - yb, 2))
    }
}
