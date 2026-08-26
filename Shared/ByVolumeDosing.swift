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
nonisolated struct ByVolumeDosing: Hashable {
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
    /// Mass of one colloquial "standard" unit in ``canonicalUnit`` — 14 g for a US
    /// standard drink. A gloss for reading an amount already logged, never a threshold.
    let standardUnitMass: Double
    /// What that colloquial unit is called on the dose form ("drink").
    let standardUnitLabel: String
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

    /// Ethanol density at 20 °C (g/mL) and the US standard-drink mass (g), for the
    /// targets that cannot read `by_volume_dosing`: the watch (no database on the
    /// wrist) and the pure `Shared/Engines` conversions the widget and Live Activity
    /// run in their own processes, which link no GRDB. Everything inside the Piru
    /// target takes these off the resolved ``ByVolumeDosing`` capability instead.
    ///
    /// `ByVolumeDosingDBTests` asserts each equals its `by_volume_dosing` column, so
    /// the two can be one edit apart but never silently disagree. Never add a third
    /// declaration — that fork is what this pair exists to end.
    nonisolated static let ethanolDensityGramsPerML: Double = 0.789

    nonisolated static let usStandardDrinkGrams: Double = 14

    /// Grams of ethanol in `volumeML` of a drink at `abv` percent.
    /// `grams = volumeML × (abv / 100) × density`. Non-finite or non-positive
    /// inputs yield 0 (blank/garbled field → no dose, never a crash or NaN).
    nonisolated static func grams(
        volumeML: Double,
        abv: Double,
        densityGramsPerML: Double = ByVolumeDosing.ethanolDensityGramsPerML,
    ) -> Double {
        guard volumeML.isFinite, abv.isFinite, densityGramsPerML.isFinite,
              volumeML > 0, abv > 0, densityGramsPerML > 0
        else { return 0 }
        return volumeML * (abv / 100) * densityGramsPerML
    }

    /// Inverse of ``grams(volumeML:abv:densityGramsPerML:)`` — the volume in mL
    /// that yields `grams` of ethanol at the given `abv`. Used to keep the
    /// By-Drink volume consistent when the dose is edited by grams (By Weight).
    /// Non-finite / non-positive inputs yield 0.
    nonisolated static func volumeML(
        grams: Double,
        abv: Double,
        densityGramsPerML: Double = ByVolumeDosing.ethanolDensityGramsPerML,
    ) -> Double {
        guard grams.isFinite, abv.isFinite, densityGramsPerML.isFinite,
              grams > 0, abv > 0, densityGramsPerML > 0
        else { return 0 }
        return grams / ((abv / 100) * densityGramsPerML)
    }

    /// Approximate US standard-drink equivalent of a grams-of-ethanol amount —
    /// the intuitive gloss shown alongside the canonical grams. Convention-dependent
    /// (US 14 g); label it as such, never a safety line.
    nonisolated static func standardDrinks(grams: Double) -> Double {
        guard grams.isFinite, grams > 0 else { return 0 }
        return grams / usStandardDrinkGrams
    }
}

// MARK: - Drink Preset

/// A tappable drink preset: a fixed measured volume + a default strength the user
/// can nudge. Stored as `Measurement<UnitVolume>` so a "pint" is 568 mL whether the
/// user's locale shows it as mL or fl oz — Foundation converts for display.
nonisolated struct DrinkPreset: Hashable, Identifiable {
    /// The closed vocabulary `drink_presets.kind` is written in. The volume and
    /// strength are data; the label and symbol below are app copy keyed by the
    /// case, so a row naming a kind this build doesn't know is dropped rather than
    /// rendered as a raw string.
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

extension DrinkPreset.Kind {
    /// Default emoji for the curated seed — the by-drink UI is emoji-first
    /// (user presets carry a customizable emoji, seeded from these).
    var emoji: String {
        switch self {
        case .beer: "🍺"
        case .wine: "🍷"
        case .shot: "🥃"
        case .pint: "🍺"
        }
    }
}

extension ByVolumeDosing {
    /// Trim a numeric value for display/storage: integer when whole, else one
    /// decimal. Shared by the input field, the presets, and the breadcrumb.
    nonisolated static func formatTrimmed(_ value: Double) -> String {
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
