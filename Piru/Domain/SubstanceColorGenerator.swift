import Foundation

/// The default color of a substance: its class decides the hue, its identity
/// decides where inside that hue's band it sits.
///
/// The output depends only on the category and the seed string, so a substance
/// keeps its color across launches, devices and database rebuilds for as long
/// as its class and PSID family hold.
nonisolated enum SubstanceColorGenerator {
    private enum Band {
        /// The class seed's lightness is pulled into this range before the
        /// spread is applied, so every result stays legible as a dot or curve
        /// on both the light and the dark card.
        static let lightnessCenter = 0.67 ... 0.75
        static let lightnessSpread = 0.07
        /// Chroma as a multiple of the class seed's, so a muted class stays
        /// muted and a vivid one vivid.
        static let chromaScale = 0.65 ... 1.25
        /// Muted classes get at least this much chroma above their seed;
        /// a purely proportional range would leave them one shade.
        static let minimumChromaHeadroom = 0.04
        /// Share of the Display P3 chroma ceiling a generated color may reach;
        /// the last few percent are the panel's most garish colors.
        static let gamutCeilingShare = 0.95
        /// Degrees either side of the class hue. Lightness × chroma alone holds
        /// about six colors at a distinguishable Oklab distance.
        static let hueJitter = 10.0
        /// Below this seed chroma the class is a gray and has no hue to keep.
        static let achromaticSeedChroma = 0.02
        static let achromaticChroma = 0.04 ... 0.09
    }

    /// The generated color for `substance`, seeded by its PSID family.
    @MainActor
    static func color(for substance: Substance) -> Oklch {
        color(category: substance.category, seed: substance.substanceUID ?? substance.name.lowercased())
    }

    /// - Parameter seed: a stable identity string — the PSID family for a
    ///   catalog substance, the lowercased name for a custom one.
    static func color(category: SubstanceCategory, seed: String) -> Oklch {
        let base = category.oklchSeed
        let hash = fnv1a(seed)
        let lightnessDraw = unit(hash, stream: 1)
        let chromaDraw = unit(hash, stream: 2)
        let hueDraw = unit(hash, stream: 3)

        let center = min(max(base.l, Band.lightnessCenter.lowerBound), Band.lightnessCenter.upperBound)
        let lightness = center + (lightnessDraw * 2 - 1) * Band.lightnessSpread

        guard base.c >= Band.achromaticSeedChroma else {
            return Oklch(l: lightness, c: lerp(Band.achromaticChroma, chromaDraw), h: hueDraw * 360)
        }
        let hue = base.h + (hueDraw * 2 - 1) * Band.hueJitter
        // The range is bounded by the gamut before the draw: fitting afterwards
        // would stack every over-the-ceiling draw onto the same edge color.
        let ceiling = Oklch.displayP3ChromaCeiling(l: lightness, h: hue) * Band.gamutCeilingShare
        let high = min(max(base.c * Band.chromaScale.upperBound, base.c + Band.minimumChromaHeadroom), ceiling)
        let low = min(base.c * Band.chromaScale.lowerBound, high * Band.chromaScale.lowerBound)
        return Oklch(l: lightness, c: lerp(low ... high, chromaDraw), h: hue)
    }

    private static func lerp(_ range: ClosedRange<Double>, _ t: Double) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * t
    }

    /// FNV-1a over the UTF-8 bytes. `String.hashValue` is reseeded on every
    /// launch, so it cannot back a color that must stay put.
    private static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return hash
    }

    /// An independent draw in `0..<1` per stream: the SplitMix64 finalizer over
    /// the hash offset by the stream's golden-ratio multiple, top 53 bits kept.
    private static func unit(_ hash: UInt64, stream: UInt64) -> Double {
        var z = hash &+ stream &* 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
