import Foundation

/// Release / duration-of-action window for a long-acting formulation — depot
/// injections, esters, weekly peptides. Distinct from ``DurationProfile``, which
/// is the *acute* dose-effect curve (hours): a single dose of these acts or
/// releases over days to weeks, which is useful to show in the drug card but is
/// NOT plotted as an acute timeline curve. Stored normalized to minutes.
struct DurationOfAction: Codable, Hashable {
    let minMinutes: Double
    let maxMinutes: Double

    init(minMinutes: Double, maxMinutes: Double) {
        self.minMinutes = minMinutes
        self.maxMinutes = maxMinutes
    }

    /// Authored as `{ min, max, unit }` (unit: hours/days/weeks/months) in the
    /// curated overlay; normalized to minutes on decode.
    private enum CodingKeys: String, CodingKey { case min, max, unit }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let factor = Self.minutesPerUnit((try? c.decode(String.self, forKey: .unit)) ?? "days")
        minMinutes = try c.decode(Double.self, forKey: .min) * factor
        maxMinutes = try c.decode(Double.self, forKey: .max) * factor
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(minMinutes / 1_440, forKey: .min)
        try c.encode(maxMinutes / 1_440, forKey: .max)
        try c.encode("days", forKey: .unit)
    }

    static func minutesPerUnit(_ unit: String) -> Double {
        switch unit.lowercased() {
        case "hour", "hours", "h": 60
        case "week", "weeks", "w": 1_440 * 7
        case "month", "months", "mo": 1_440 * 30
        default: 1_440 // days
        }
    }

    /// Human-friendly release window for the drug card — picks the most readable
    /// unit (e.g. "7–10 days", "8–12 weeks", "4–6 months"). Localized.
    var formattedWindow: String {
        let maxDays = maxMinutes / 1_440
        func n(_ minutes: Double, per: Double) -> String {
            let v = minutes / per
            return v.rounded() == v ? String(Int(v)) : v.formatted(.number.precision(.fractionLength(1)))
        }
        if maxDays >= 90 {
            return String(localized: "\(n(minMinutes, per: 1_440 * 30))–\(n(maxMinutes, per: 1_440 * 30)) months", comment: "Long-acting release window")
        } else if maxDays >= 21 {
            return String(localized: "\(n(minMinutes, per: 1_440 * 7))–\(n(maxMinutes, per: 1_440 * 7)) weeks", comment: "Long-acting release window")
        } else {
            return String(localized: "\(n(minMinutes, per: 1_440))–\(n(maxMinutes, per: 1_440)) days", comment: "Long-acting release window")
        }
    }
}

/// One salt/ester form of a substance for a given route — e.g. Magnesium
/// *Citrate* vs *Glycinate* vs *L-Threonate*. The salt genuinely changes dosing
/// (elemental fraction, absorption), so each form carries its own dose ladder
/// and (optionally) duration. Nested under ``SubstanceRoute``: a route's
/// ``SubstanceRoute/saltForms`` lists all forms, ordered with the default first;
/// the route's top-level `doses`/`unit`/`duration` mirror that default form so
/// salt-unaware code keeps working transparently.
/// A single dose-bearing **form** of a route — historically salt-only, now
/// multi-axis (Stage A). Each variant carries its own `unit`/`doses`/`duration`
/// so a resolved enantiomer's distinct pharmacology (armodafinil's longer
/// exposure, Focalin's ~2× potency) is real per-form data, not a cosmetic label.
/// The two orthogonal facets are independent: `saltForm` (the counter-ion) and
/// `isomer` (the stereo code). `nil` on either = unspecified/racemic on that axis.
struct DoseVariant: Codable, Hashable {
    /// Salt/ester label (Citrate, Glycinate, L-Threonate…). `nil` = freebase /
    /// unspecified — the common case, and the racemic form of an isomer family.
    let saltForm: String?
    /// Stereoisomer code (D/S/L/R). `nil` = racemate/unspecified. Drives PSID
    /// identity + dedup; never shown bare (see `isomerDisplayName`).
    let isomer: String?
    /// The recognized name titling this isomer form ("Dexmethylphenidate",
    /// "Esketamine", "Armodafinil"). `nil` for the racemic/unspecified form.
    let isomerDisplayName: String?
    let unit: String
    let doses: DoseRange
    let duration: DurationProfile?
    /// Mass fraction of the elemental active (e.g. elemental magnesium) in this
    /// salt — Magnesium citrate ≈ 0.16, glycinate ≈ 0.14, L-threonate ≈ 0.08.
    /// `nil` when unknown / not applicable. Lets the UI show "= ⟨elemental⟩ mg".
    let elementalFraction: Double?

    nonisolated init(
        saltForm: String? = nil,
        isomer: String? = nil,
        isomerDisplayName: String? = nil,
        unit: String,
        doses: DoseRange,
        duration: DurationProfile? = nil,
        elementalFraction: Double? = nil,
    ) {
        self.saltForm = saltForm
        self.isomer = isomer
        self.isomerDisplayName = isomerDisplayName
        self.unit = unit
        self.doses = doses
        self.duration = duration
        self.elementalFraction = elementalFraction
    }
}

/// Which dosing regime a ladder describes. Several compounds have both, and the
/// two differ by multiples — quetiapine's clinical range is 150–750 mg while its
/// recreational one is 50–150 — so a number shown without its regime can be read
/// as the wrong kind of dose entirely.
enum DoseContext: String, Codable {
    case therapeutic
    case recreational
    case unknown
}

struct SubstanceRoute: Codable {
    let route: RouteOfAdministration
    let unit: String
    let doses: DoseRange
    /// The regime `doses` describes. Prescription and dual-use compounds ship
    /// only their recreational ladder (the build strips therapeutic ones), and
    /// the card labels it so it is never mistaken for a clinical dose.
    let doseContext: DoseContext
    let duration: DurationProfile?
    /// Clinical-protocol dosing (peptides/Rx). When present the UI shows this
    /// instead of the `doses` trip-intensity ladder.
    let protocolDosing: ProtocolDosing?
    /// Release / duration-of-action window for long-acting formulations (depot
    /// injections, weekly peptides). Shown in the drug card; never drawn as an
    /// acute timeline curve.
    let durationOfAction: DurationOfAction?
    /// Salt/ester forms available for this route, ordered with the default
    /// (highest-priority) form first. `nil`/empty for the overwhelming majority
    /// of substances, which have a single unspecified form. When present, the
    /// top-level `unit`/`doses`/`duration` mirror `saltForms.first` (the
    /// default), so code that ignores salt form transparently gets the default.
    /// The salt picker is shown only when this holds more than one form.
    let saltForms: [DoseVariant]?

    nonisolated init(
        route: RouteOfAdministration,
        unit: String,
        doses: DoseRange,
        doseContext: DoseContext = .unknown,
        duration: DurationProfile? = nil,
        protocolDosing: ProtocolDosing? = nil,
        durationOfAction: DurationOfAction? = nil,
        saltForms: [DoseVariant]? = nil,
    ) {
        self.route = route
        self.unit = unit
        self.doses = doses
        self.doseContext = doseContext
        self.duration = duration
        self.protocolDosing = protocolDosing
        self.durationOfAction = durationOfAction
        self.saltForms = saltForms
    }
}
