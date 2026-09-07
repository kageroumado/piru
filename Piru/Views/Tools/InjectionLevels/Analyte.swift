import Foundation

/// A hormone the Injection Levels tool models depot esters for. Hormone-agnostic by
/// design (Specs/injection-levels-tool.md §6) — the depot math is identical, only
/// the ester parameters and the canonical unit differ.
///
/// The tool only ever offers an analyte the bundled DB actually has ester PK data
/// for (``SubstanceStore/analytesWithEsterData()``), so a case here without shipped
/// `ester_pk` rows simply never appears in the picker.
enum Analyte: String, CaseIterable, Identifiable, Sendable {
    case estradiol
    case testosterone

    var id: String {
        rawValue
    }

    /// The `ester_pk.analyte` / `LabMeasurement.analyteKey` key.
    var key: String {
        rawValue
    }

    var displayName: LocalizedStringResource {
        switch self {
        case .estradiol: "Estradiol"
        case .testosterone: "Testosterone"
        }
    }

    /// The unit lab levels are stored and drawn in.
    var canonicalUnit: String {
        switch self {
        case .estradiol: "pg/mL"
        case .testosterone: "ng/dL"
        }
    }

    /// The molar (SI) unit labs outside the US commonly report in.
    var molarUnit: String {
        switch self {
        case .estradiol: "pmol/L"
        case .testosterone: "nmol/L"
        }
    }

    /// Both units the input sheet accepts, canonical first.
    var acceptedUnits: [String] {
        [canonicalUnit, molarUnit]
    }

    /// Molar mass, g/mol (estradiol 272.38, testosterone 288.42). Used only to
    /// convert a molar-unit entry to the canonical mass unit; a physical constant,
    /// not substance-keyed pharmacology.
    private var molarMass: Double {
        switch self {
        case .estradiol: 272.38
        case .testosterone: 288.42
        }
    }

    /// Molar-per-canonical conversion factor: `1 canonicalUnit = factor · molarUnit`.
    /// Estradiol: 1 pg/mL = 3.671 pmol/L. Testosterone: 1 ng/dL = 0.03467 nmol/L.
    /// Derived from the molar mass, so the two stay consistent.
    var molarPerCanonical: Double {
        switch self {
        // pg/mL = 1e-9 g/L → mol/L = 1e-9 / MW → pmol/L = 1e3 · that.
        case .estradiol: 1e-9 / molarMass * 1e12
        // ng/dL = 1e-8 g/L → mol/L = 1e-8 / MW → nmol/L = 1e9 · that.
        case .testosterone: 1e-8 / molarMass * 1e9
        }
    }

    /// Convert a value the user typed in `unit` into the canonical unit.
    func toCanonical(_ value: Double, from unit: String) -> Double {
        unit == molarUnit ? value / molarPerCanonical : value
    }

    /// Convert a canonical-unit value into `unit` for display.
    func fromCanonical(_ value: Double, to unit: String) -> Double {
        unit == molarUnit ? value * molarPerCanonical : value
    }
}
