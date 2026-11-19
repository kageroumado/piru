import Foundation

/// A dose amount bound to the unit it was written in.
///
/// Storage keeps the written pair (`DoseEntry.amount` + `unit`); this is the
/// parsed form every computation works from. Weighing a dose against a ladder,
/// a reference dose or another dose goes through ``value(in:)``, ``ratio(to:)``
/// or ``adding(_:)``, each of which answers `nil` when the two sides measure
/// different things — so a gram is never divided by a milligram, and an mL of
/// GHB is never placed on a gram ladder.
nonisolated enum DoseQuantity: Hashable, Sendable {
    case mass(Measurement<UnitDoseMass>)
    case volume(Measurement<UnitVolume>)
    /// A unit with no physical conversion: IU, puffs, drops, or a mass on a
    /// stated basis ("mg (freebase)"). Comparable only with the same unit.
    case count(Double, unit: String)

    /// Parse a written amount and unit. `aliases` are the substance's colloquial
    /// units ("drink" = 14 g of ethanol, a user's "capsule" = 30 mg): each becomes
    /// a unit of its own that converts like any other.
    init(_ amount: Double, unit: String, aliases: [UnitAlias] = []) {
        if let mass = Self.massUnit(unit) {
            self = .mass(Measurement(value: amount, unit: mass))
        } else if let volume = Self.volumeUnit(unit) {
            self = .volume(Measurement(value: amount, unit: volume))
        } else if let alias = aliases.first(where: { $0.label.caseInsensitiveCompare(unit) == .orderedSame }),
                  let aliasUnit = alias.massUnit {
            self = .mass(Measurement(value: amount, unit: aliasUnit))
        } else {
            self = .count(amount, unit: unit)
        }
    }

    /// The number as written, in ``unitSymbol``.
    var value: Double {
        switch self {
        case let .mass(measurement): measurement.value
        case let .volume(measurement): measurement.value
        case let .count(value, _): value
        }
    }

    /// The written unit's symbol.
    var unitSymbol: String {
        switch self {
        case let .mass(measurement): measurement.unit.symbol
        case let .volume(measurement): measurement.unit.symbol
        case let .count(_, unit): unit
        }
    }

    /// What kind of thing this measures. Two quantities of the same family can be
    /// summed and compared; across families they cannot.
    enum Family: Hashable, Sendable {
        case mass
        case volume
        case count(String)
    }

    var family: Family {
        switch self {
        case .mass: .mass
        case .volume: .volume
        case let .count(_, unit): .count(Self.key(unit))
        }
    }

    /// The amount in milligrams, or `nil` when this is not a mass.
    var milligrams: Double? {
        guard case let .mass(measurement) = self else { return nil }
        return measurement.value(in: .milligrams)
    }

    /// The amount expressed in the written unit `unit`, or `nil` when `unit`
    /// measures something else (mL for a mass, IU for anything but IU).
    func value(in unit: String) -> Double? {
        switch self {
        case let .mass(measurement):
            Self.massUnit(unit).map { measurement.value(in: $0) }
        case let .volume(measurement):
            Self.volumeUnit(unit).map { measurement.converted(to: $0).value }
        case let .count(value, written):
            Self.key(written) == Self.key(unit) ? value : nil
        }
    }

    /// The amount expressed in whatever unit `other` is written in — its alias
    /// units included — or `nil` when the two measure different things.
    func value(inUnitOf other: DoseQuantity) -> Double? {
        switch (self, other) {
        case let (.mass(lhs), .mass(rhs)): lhs.value(in: rhs.unit)
        case let (.volume(lhs), .volume(rhs)): lhs.converted(to: rhs.unit).value
        case let (.count(lhs, lhsUnit), .count(_, rhsUnit)) where Self.key(lhsUnit) == Self.key(rhsUnit): lhs
        default: nil
        }
    }

    /// `self ÷ other` as a pure number, or `nil` when they measure different
    /// things or `other` is zero.
    func ratio(to other: DoseQuantity) -> Double? {
        guard other.value != 0, let numerator = value(inUnitOf: other) else { return nil }
        return numerator / other.value
    }

    /// The sum, in `self`'s unit, or `nil` when the two measure different things.
    func adding(_ other: DoseQuantity) -> DoseQuantity? {
        guard let addend = other.value(inUnitOf: self) else { return nil }
        return with(value: value + addend)
    }

    /// The quantity a mixed list is best summed in: the first one of the family
    /// most of them share, the earliest family winning a tie. A lone mL dose ahead
    /// of ten mg ones must not leave the mg doses out of the sum.
    static func reference(among quantities: [DoseQuantity]) -> DoseQuantity? {
        var counts: [Family: Int] = [:]
        for quantity in quantities {
            counts[quantity.family, default: 0] += 1
        }
        guard let most = counts.values.max() else { return nil }
        return quantities.first { counts[$0.family] == most }
    }

    /// The same unit carrying a different number.
    func with(value newValue: Double) -> DoseQuantity {
        switch self {
        case let .mass(measurement): .mass(Measurement(value: newValue, unit: measurement.unit))
        case let .volume(measurement): .volume(Measurement(value: newValue, unit: measurement.unit))
        case let .count(_, unit): .count(newValue, unit: unit)
        }
    }

    // MARK: - Units

    /// Every bare spelling of a mass unit.
    ///
    /// "µg" and "μg" are different codepoints — MICRO SIGN (U+00B5) and GREEK
    /// SMALL LETTER MU (U+03BC) — and the catalog contains both, because
    /// upstreams type them differently. Missing either one silently drops every
    /// microgram-dosed drug out of tolerance, combined depression and tiering,
    /// exactly where the margin is thinnest.
    ///
    /// Deliberately bare spellings only. A qualified unit ("mg (freebase)",
    /// "mg (salt)") states a basis, and folding it onto plain mg would let a
    /// freebase amount be compared against a salt amount as though the qualifier
    /// were decoration. Rate and per-mass units ("µg/kg", "mcg/hr") are not
    /// masses and parse as counts.
    private static let massUnits: [String: UnitDoseMass] = [
        "µg": .micrograms, "μg": .micrograms, "mcg": .micrograms, "ug": .micrograms,
        "microgram": .micrograms, "micrograms": .micrograms, "mcgs": .micrograms, "ugs": .micrograms,
        "mg": .milligrams, "mgs": .milligrams, "milligram": .milligrams, "milligrams": .milligrams,
        "g": .grams, "gs": .grams, "gram": .grams, "grams": .grams, "gm": .grams,
    ]

    private static let volumeUnits: [String: UnitVolume] = [
        "ml": .milliliters, "milliliter": .milliliters, "milliliters": .milliliters, "cc": .milliliters,
    ]

    private static func key(_ unit: String) -> String {
        unit.trimmingCharacters(in: .whitespaces).lowercased()
    }

    static func massUnit(_ unit: String) -> UnitDoseMass? {
        massUnits[key(unit)]
    }

    /// The bare mass a qualified unit opens with — `g` for "g active GHB / sodium
    /// oxybate", `mg` for "mg THC", `µg` for "µg LSD base" — or `nil` when the unit
    /// is bare already or opens with something else ("mg/kg" is a rate).
    static func basisMassUnit(_ unit: String) -> UnitDoseMass? {
        let trimmed = unit.trimmingCharacters(in: .whitespaces)
        guard let split = trimmed.firstIndex(where: { $0 == " " || $0 == "(" }) else { return nil }
        return massUnit(String(trimmed[..<split]))
    }

    static func volumeUnit(_ unit: String) -> UnitVolume? {
        volumeUnits[key(unit)]
    }
}

/// Mass as doses are measured: a dimension whose base unit is the milligram.
///
/// Foundation's `UnitMass` converts through kilograms, which turns 0.08 g into
/// 80.00000000000001 mg — enough to drop a dose logged exactly on a tier boundary
/// into the tier below, and enough that `0.08 g == 80 mg` is false. Through a
/// milligram base both are exact, and so is every alias unit (a drink is 14 000
/// mg, a tab its strength). Defined as a dimension of its own because `UnitMass`
/// is final on the open-source Foundation the Android build compiles against.
final nonisolated class UnitDoseMass: Dimension, @unchecked Sendable {
    static let micrograms = UnitDoseMass(symbol: "µg", converter: UnitConverterLinear(coefficient: 0.001))
    static let milligrams = UnitDoseMass(symbol: "mg", converter: UnitConverterLinear(coefficient: 1))
    static let grams = UnitDoseMass(symbol: "g", converter: UnitConverterLinear(coefficient: 1_000))

    override static func baseUnit() -> UnitDoseMass {
        milligrams
    }
}

extension Measurement<UnitDoseMass> {
    nonisolated static func mg(_ value: Double) -> Self {
        Self(value: value, unit: .milligrams)
    }

    nonisolated static func g(_ value: Double) -> Self {
        Self(value: value, unit: .grams)
    }

    /// This mass expressed in `unit`.
    nonisolated func value(in unit: UnitDoseMass) -> Double {
        converted(to: unit).value
    }
}

/// A colloquial unit that resolves to a fixed amount in a known physical unit.
/// e.g. `("drink", 14, "g")` for alcohol — "2 drinks" is 28 g of ethanol.
nonisolated struct UnitAlias: Hashable, Sendable {
    /// User-facing display label (what appears in the unit picker).
    let label: String
    /// How many `unit`s a single instance of `label` represents.
    let amountPerUnit: Double
    /// The physical unit that `amountPerUnit` is denominated in.
    let unit: String

    /// The alias as a mass unit of its own ("drink" = 14 000 mg), or `nil` when it
    /// is denominated in something other than a mass.
    var massUnit: UnitDoseMass? {
        guard amountPerUnit > 0, let base = DoseQuantity.massUnit(unit) else { return nil }
        let milligrams = Measurement(value: amountPerUnit, unit: base).value(in: .milligrams)
        return UnitDoseMass(symbol: label, converter: UnitConverterLinear(coefficient: milligrams))
    }
}

extension DoseEntry {
    /// The logged amount as written, or `nil` when no amount was recorded.
    /// Colloquial units are folded to their mass when an entry is saved;
    /// ``Substance/quantity(of:)`` reads the substance's aliases as well, so
    /// prefer it wherever the substance is at hand.
    var quantity: DoseQuantity? {
        isUnknownDose ? nil : DoseQuantity(amount, unit: unit)
    }
}
