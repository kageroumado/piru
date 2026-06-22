import Foundation

// MARK: - By-Volume Dosing

/// A substance whose natural input is a **concentration applied to a measured
/// volume** rather than a mass entered directly — alcohol by %ABV today, dissolved
/// solids (mg/mL) later. Substances opt in (alcohol is the only adopter in v1); the
/// capability owns the density constant and the canonical-unit conversion so the
/// dose form stays substance-agnostic.
///
/// The user measures in volume (a 330 mL can, a 175 mL glass); Piru stores the
/// canonical mass (grams of ethanol) the dose ladder and PK model run on. This type
/// is the exact, uncontested arithmetic between the two — not a model, no confidence
/// hedge: `grams = volume × (ABV/100) × density`.
struct ByVolumeDosing: Hashable {
    /// How a strength figure maps onto a volume.
    enum Concentration: Hashable {
        /// Percent volume-by-volume of a liquid with the given density (g/mL).
        /// Alcohol: the strength field is ABV %, ethanol density 0.789 g/mL at 20 °C.
        case percentByVolume(densityGramsPerML: Double)
        // Future: `case massPerVolume` — mg/mL stock solutions (GHB/GBL, RC stock),
        // where the strength field is a concentration in mg/mL. Adopting it needs
        // only a new case here + a curated blob, no new input UI.
    }

    let concentration: Concentration
    /// The unit stored on the resulting `DoseEntry` — "g" for alcohol — and what
    /// the dose ladder / PK pipeline consume. The whole point of canonicalising.
    let canonicalUnit: String
    /// Tappable presets that pre-fill a volume + a default strength (Beer/Wine/…).
    /// First-class, not optional: the watch flow logs primarily from these.
    let drinkPresets: [DrinkPreset]

    /// Canonical-unit amount for a measured `volumeML` at the given `strength`.
    /// For `.percentByVolume`, `strength` is ABV % and the result is grams of ethanol.
    func canonicalAmount(volumeML: Double, strength: Double) -> Double {
        switch concentration {
        case let .percentByVolume(density):
            Self.grams(volumeML: volumeML, abv: strength, densityGramsPerML: density)
        }
    }

    // MARK: Pure conversion

    /// Ethanol density at 20 °C (g/mL). Temperature variance is negligible for
    /// dose tracking — don't over-precision the readout.
    static let ethanolDensityGramsPerML: Double = 0.789

    /// US standard drink — 14 g of pure ethanol per
    /// [NIAAA](https://www.niaaa.nih.gov/alcohols-effects-health/overview-alcohol-consumption/what-standard-drink).
    /// A comparison gloss, not a safety threshold.
    static let usStandardDrinkGrams: Double = 14

    /// Grams of ethanol in `volumeML` of a drink at `abv` percent.
    /// `grams = volumeML × (abv / 100) × density`. Non-finite or non-positive
    /// inputs yield 0 (blank/garbled field → no dose, never a crash or NaN).
    static func grams(
        volumeML: Double,
        abv: Double,
        densityGramsPerML: Double = ByVolumeDosing.ethanolDensityGramsPerML,
    ) -> Double {
        guard volumeML.isFinite, abv.isFinite, densityGramsPerML.isFinite,
              volumeML > 0, abv > 0, densityGramsPerML > 0
        else { return 0 }
        return volumeML * (abv / 100) * densityGramsPerML
    }

    /// Approximate US standard-drink equivalent of a grams-of-ethanol amount —
    /// the intuitive gloss shown alongside the canonical grams. Convention-dependent
    /// (US 14 g); label it as such, never a safety line.
    static func standardDrinks(grams: Double) -> Double {
        guard grams.isFinite, grams > 0 else { return 0 }
        return grams / usStandardDrinkGrams
    }
}

// MARK: - Drink Preset

/// A tappable drink preset: a fixed measured volume + a default strength the user
/// can nudge. Stored as `Measurement<UnitVolume>` so a "pint" is 568 mL whether the
/// user's locale shows it as mL or fl oz — Foundation converts for display.
struct DrinkPreset: Hashable, Identifiable {
    enum Kind: String, Hashable, CaseIterable {
        case beer
        case wine
        case shot
        case pint
    }

    let kind: Kind
    let volume: Measurement<UnitVolume>
    /// Pre-filled ABV %, user-adjustable.
    let defaultABV: Double

    var id: Kind {
        kind
    }

    var name: LocalizedStringResource {
        switch kind {
        case .beer: "Beer"
        case .wine: "Wine"
        case .shot: "Shot"
        case .pint: "Pint"
        }
    }

    /// SF Symbol for the preset chip.
    var systemImage: String {
        switch kind {
        case .beer: "mug"
        case .wine: "wineglass"
        case .shot: "cup.and.saucer"
        case .pint: "mug.fill"
        }
    }
}

// MARK: - Curated Catalog

extension ByVolumeDosing {
    /// Curated by-volume capability for alcohol — the only adopter in v1. Mirrors
    /// the hardcoded `drink` unit alias (a curated Swift constant, not pipeline
    /// data); promote to the data layer when a second substance adopts it.
    static let alcohol = ByVolumeDosing(
        concentration: .percentByVolume(densityGramsPerML: ethanolDensityGramsPerML),
        canonicalUnit: "g",
        drinkPresets: [
            DrinkPreset(kind: .beer, volume: Measurement(value: 330, unit: .milliliters), defaultABV: 5),
            DrinkPreset(kind: .wine, volume: Measurement(value: 150, unit: .milliliters), defaultABV: 13),
            DrinkPreset(kind: .shot, volume: Measurement(value: 44, unit: .milliliters), defaultABV: 40),
            DrinkPreset(kind: .pint, volume: Measurement(value: 568, unit: .milliliters), defaultABV: 5),
        ],
    )

    /// Lookup by canonical substance name / alias (lowercased).
    static let catalog: [String: ByVolumeDosing] = [
        "alcohol": alcohol,
        "ethanol": alcohol,
    ]

    /// Trim a numeric value for display/storage: integer when whole, else one
    /// decimal. Shared by the input field, the presets, and the breadcrumb.
    static func formatTrimmed(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

// MARK: - Notes Breadcrumb Codec

/// Encodes/decodes the by-volume origin stored on a dose's `notes` — canonical
/// millilitres + ABV, with an optional drink name (`"IPA · 568 mL · 6% ABV"` or
/// `"330 mL · 5% ABV"`). The form/tray prepends it on save and re-derives the
/// name/volume/strength fields from it on edit. The canonical-mL form keeps the
/// parse locale-independent.
enum ByVolumeBreadcrumb {
    static let separator = " · "

    static func make(name: String? = nil, volumeML: Double, abv: Double) -> String {
        let core = "\(ByVolumeDosing.formatTrimmed(volumeML)) mL\(separator)\(ByVolumeDosing.formatTrimmed(abv))% ABV"
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return "\(name)\(separator)\(core)"
        }
        return core
    }

    /// First `"[name · ]<v> mL · <a>% ABV"` found in `notes` (prepended as the
    /// leading line), or nil. Case-insensitive, whitespace-tolerant. `name` is the
    /// optional text before the volume, with its trailing separator removed.
    static func parse(_ notes: String) -> (name: String?, volumeML: Double, abv: Double)? {
        let pattern = #/([0-9]+(?:\.[0-9]+)?)\s*mL\s*·\s*([0-9]+(?:\.[0-9]+)?)\s*%\s*ABV/#
            .ignoresCase()
        for raw in notes.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            guard let m = line.firstMatch(of: pattern),
                  let ml = Double(m.1), let abv = Double(m.2) else { continue }
            var prefix = String(line[line.startIndex ..< m.range.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            if prefix.hasSuffix("·") { prefix = String(prefix.dropLast()).trimmingCharacters(in: .whitespaces) }
            return (prefix.isEmpty ? nil : prefix, ml, abv)
        }
        return nil
    }

    /// Strip the breadcrumb line from `notes`, returning the user's own remaining
    /// text (so the form shows their note without the machine prefix on edit).
    static func strip(from notes: String) -> String {
        let lines = notes.split(separator: "\n", omittingEmptySubsequences: false)
        let kept = lines.filter { parse(String($0)) == nil }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
