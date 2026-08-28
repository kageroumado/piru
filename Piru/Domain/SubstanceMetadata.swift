import SwiftUI

/// Predicted / forensic physicochemical descriptors, decoded from the
/// `substances` table's Stage-1 columns. **Not clinical values** — logP/TPSA/
/// HBA/HBD are computed (PubChem XLogP3 / NPS-DataHub) and the LD50 figures are *rodent*
/// order-of-magnitude toxicity, never a human "safe dose". The detail card
/// surfaces them behind an explicit honesty footnote (see ``SubstanceDetailView``).
struct Physicochemical: Codable, Hashable {
    /// Octanol/water partition coefficient (lipophilicity), computed.
    let logP: Double?
    /// Topological polar surface area, Å².
    let tpsa: Double?
    /// Hydrogen-bond acceptor count.
    let hba: Int?
    /// Hydrogen-bond donor count.
    let hbd: Int?
    /// Rodent oral LD50, mg/kg — order-of-magnitude toxicity, not a safe dose.
    let ld50OralMgPerKg: Double?
    /// Rodent dermal LD50, mg/kg — order-of-magnitude toxicity, not a safe dose.
    let ld50DermalMgPerKg: Double?
    /// Melting point, °C.
    let meltingPointC: Double?
    /// Boiling point, °C.
    let boilingPointC: Double?

    /// `true` when at least one descriptor is populated — the card only renders
    /// when there's something to show.
    var hasAnyValue: Bool {
        logP != nil || tpsa != nil || hba != nil
            || hbd != nil || ld50OralMgPerKg != nil || ld50DermalMgPerKg != nil
            || meltingPointC != nil || boilingPointC != nil
    }

    /// `true` when either LD50 figure is present — gates the rodent-toxicity
    /// honesty footnote so it only shows when an LD50 is actually displayed.
    var hasLD50: Bool {
        ld50OralMgPerKg != nil || ld50DermalMgPerKg != nil
    }
}

/// How a compound is surfaced under the display policy. Baked at build time
/// into `substances.display_class`. Gates dose/duration visibility and whether
/// the compound appears in recreational category browsing. See
/// `docs/` and `pipeline/build/sqlite.py:classify_compounds`.
enum CompoundDisplayClass: String, Codable {
    /// Recreational use is the primary frame — full dose ladder + duration.
    case recreational
    /// A medical drug that PsychonautWiki/TripSit also document recreationally
    /// (mirtazapine, DXM, gabapentin, …). Shown like recreational.
    case dualUse = "dual_use"
    /// Over-the-counter — dose is on the package, so dose may be shown without
    /// a recreational signal. Duration suppressed when implausible (>24h).
    case otc
    /// Prescription medication, no recreational value — show mechanism /
    /// indications / warnings, but NEVER dose or duration (a doctor's domain).
    case medicalRx = "medical_rx"
    /// No recreational value at all (antibiotics, …). Trackable + recognisable
    /// but hidden from recreational browsing; no dose/duration.
    case nonRecreational = "non_recreational"

    /// Whether "Limited data" / "Limited human data" may be said about this
    /// compound at all — before any row count is consulted.
    ///
    /// The label reads as a statement about the **molecule's evidence base**, not
    /// about what Piru happens to have ingested. That makes it false for anything
    /// approved: atorvastatin, omeprazole, testosterone and calcium have vast human
    /// literature whatever this database holds, so no row count can license the
    /// phrase for them. It belongs to research chemicals with little or no human
    /// data — which is exactly the recreational / dual-use half of the catalog.
    var mayReportLimitedData: Bool {
        switch self {
        case .recreational, .dualUse: true
        case .otc, .medicalRx, .nonRecreational: false
        }
    }

    /// Dose ladder visible. Suppressed for medical/non-recreational compounds.
    var showsDoseLadder: Bool {
        switch self {
        case .recreational, .dualUse, .otc: true
        case .medicalRx, .nonRecreational: false
        }
    }

    /// Duration profile visible. (OTC additionally requires a plausible
    /// duration — gate on `Substance.durationImplausible` at the call site.)
    var showsDuration: Bool {
        switch self {
        case .recreational, .dualUse, .otc: true
        case .medicalRx, .nonRecreational: false
        }
    }

    /// Whether this compound appears in recreational category browsing. Non-
    /// recreational compounds stay searchable (for medication tracking) but are
    /// not surfaced in the browse grid.
    var surfacesInBrowse: Bool {
        self != .nonRecreational
    }
}

/// A single contraindication or boxed warning sourced from a clinical label.
///
/// Exactly one of ``flag`` and ``text`` carries the content. A ``flag`` means
/// the label's sentence was matched to Piru's vocabulary and Piru supplies the
/// wording; ``text`` survives only where the source already gave a name rather
/// than a sentence — a condition ("Anuria") or a boxed warning's own title.
struct Contraindication: Codable, Hashable {
    let flag: ContraindicationFlag?
    let text: String?
    let isBoxedWarning: Bool

    /// What to put on screen.
    var display: LocalizedStringResource {
        if let flag { return flag.label }
        // `verbatim`-equivalent: a surviving `text` is a condition name read
        // from the source, not a catalog key.
        return LocalizedStringResource(stringLiteral: text ?? "")
    }
    /// The label or guideline the block came from. These were the only
    /// substantive claims in the app a reader had no way to check.
    var sourceURL: String?
}

/// Cross-benzodiazepine dose equivalency (relative to 10 mg diazepam). Sourced
/// from the TripSit benzo dataset; the only such data in Piru.
struct DiazepamEquivalent: Codable, Hashable {
    let doseMg: Double?
    let equivalentDiazepamMg: Double?
    let displayText: String?
    /// Whether this row's number matches the reference table it is attributed to. The upstream
    /// dataset carries no per-value source, so the pipeline attaches a citation only where the
    /// shipped value agrees with Ashton Table 1 — leaving the five benzodiazepines Ashton omits
    /// (brotizolam, etizolam, flutoprazepam, midazolam, phenazepam) honestly unsourced.
    var isCited: Bool = false

    init(
        doseMg: Double?,
        equivalentDiazepamMg: Double?,
        displayText: String?,
        isCited: Bool = false,
    ) {
        self.doseMg = doseMg
        self.equivalentDiazepamMg = equivalentDiazepamMg
        self.displayText = displayText
        self.isCited = isCited
    }
}

/// A primary reference for a compound — a DOI, PubMed ID, URL, or free-text
/// label ("Egrifta SmPC"). Surfaced in the detail "References" section so every
/// curated claim is traceable to its source.
struct Citation: Codable, Hashable {
    let doi: String?
    let pmid: Int?
    let url: String?
    let title: String?

    init(doi: String? = nil, pmid: Int? = nil, url: String? = nil, title: String? = nil) {
        self.doi = doi
        self.pmid = pmid
        self.url = url
        self.title = title
    }

    /// A tappable link, when the reference resolves to one. Free-text labels
    /// (stored in `url` without an http scheme) return nil → rendered as text.
    var resolvedURL: URL? {
        if let doi, !doi.isEmpty { return URL(string: "https://doi.org/\(doi)") }
        if let pmid { return URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/") }
        if let url, url.hasPrefix("http") { return URL(string: url) }
        return nil
    }

    /// Human-facing label.
    var label: String {
        if let title, !title.isEmpty { return title }
        if let doi, !doi.isEmpty { return "DOI \(doi)" }
        if let pmid { return "PMID \(pmid)" }
        if let url, !url.isEmpty { return url }
        return String(localized: "Reference")
    }
}

/// A citation attached to a ``MythBust``, carrying the *role* it plays in the
/// correction so the UI can style it and so the source of a myth is never shown
/// as if it supported the myth. See ``MythCitation/Role``.
struct MythCitation: Codable, Hashable {
    /// How a reference relates to the misconception it accompanies.
    enum Role: String, Codable, Hashable {
        /// Evidence that refutes the claim — the default (accent-styled chip).
        case refutes
        /// The (usually retracted) source the myth originally came from, cited
        /// only to discredit it. Must never be presented as supporting
        /// evidence; the UI marks it "retracted" and may link the retraction
        /// notice rather than the paper.
        case retractedSource
        /// A dataset / registry used as evidence (e.g. a pharmacovigilance
        /// database showing zero sole-agent cases).
        case dataset
    }

    let citation: Citation
    let role: Role
    /// Optional one-line gloss shown beside the chip ("null in abstinent users").
    let note: String?

    init(citation: Citation, role: Role = .refutes, note: String? = nil) {
        self.citation = citation
        self.role = role
        self.note = note
    }
}

/// A short attributed quotation surfaced beneath a ``MythBust``. Rare —
/// reserved for flagship substances where a primary voice sharpens the
/// correction (e.g. a pharmacologist on the MDMA retraction scandal).
struct PullQuote: Codable, Hashable {
    let text: String
    let attribution: String
}

/// One evidence-checked correction to a common claim about a substance — the
/// "cited misconceptions" surface. An uncited myth-bust is just a
/// counter-assertion, so every ``MythBust`` **must** carry at least one
/// ``citations`` entry (enforced in `validate_curated.py`). Curated and
/// deliberately popular-substances-only; absent for the long tail, which is
/// correct rather than a gap.
struct MythBust: Codable, Hashable {
    /// The claim as people actually state it — e.g. "It burns holes in your brain".
    let claim: String
    /// The evidence-based correction. May contain Markdown `**bold**` for the
    /// load-bearing phrase; rendered with `AttributedString(markdown:)`.
    let correction: String
    /// Sources substantiating the correction. Non-empty by contract.
    let citations: [MythCitation]
    /// A rare flagship-only pull-quote; nil for the overwhelming majority.
    let pullQuote: PullQuote?

    init(claim: String, correction: String, citations: [MythCitation], pullQuote: PullQuote? = nil) {
        self.claim = claim
        self.correction = correction
        self.citations = citations
        self.pullQuote = pullQuote
    }
}

/// One hand-curated notable combination — a row in the detail page's
/// "Combinations" section. Editorial content ranked by evidence, not
/// reputation: what to know *before* taking it, complementing the
/// `InteractionChecker` (which fires on doses already logged). Curated and
/// popular-substances-only; absent for the long tail.
struct Combination: Codable, Hashable, Sendable {
    /// Evidence-ranked severity tier for a combination row.
    enum Severity: String, Codable, Hashable, Sendable {
        /// Life-threatening; avoid entirely (e.g. MDMA + MAOIs).
        case danger
        /// Real risk; be careful (e.g. MDMA + alcohol).
        case caution
        /// Worth knowing; not dangerous (e.g. SSRIs mostly blunt MDMA).
        case note
    }

    let severity: Severity
    /// Substance or class name (e.g. "MAOIs", "Alcohol").
    let name: String
    /// Plain-language explanation naming the direction of risk and why. May
    /// contain Markdown `**bold**`; rendered with `AttributedString(markdown:)`.
    let description: String
    /// Optional qualifier tag (e.g. "blunts").
    let note: String?
}

/// Curated thermoregulation/hydration guidance — the detail page's "Water &
/// heat" card. Bounded on both sides: a rate while active *and* the warning
/// that over-drinking causes hyponatremia. Only for substances that raise body
/// temperature or alter fluid balance; nil for the long tail.
struct WaterHeatGuidance: Codable, Hashable, Sendable {
    /// Big-number display (e.g. "≈ 1 glass / hour").
    let headline: String
    /// Explanation of why, and the upper bound. May contain Markdown `**bold**`.
    let body: String
}

/// One rung of a titration ramp, e.g. "2.5 mg" during "weeks 1–4".
struct TitrationStep: Codable, Hashable {
    /// Amount in the route's `unit`.
    let amount: Double
    /// Localized phase label, e.g. "weeks 1–4", "month 2".
    let label: String
}

/// Clinical-protocol dosing for compounds taken on a schedule (peptides, some
/// prescription drugs) rather than along a trip-intensity ladder. When present,
/// the detail UI renders this instead of the `DoseRange` threshold→heavy tiers.
/// Amounts are in the owning `SubstanceRoute.unit` (mcg, mg, or IU).
struct ProtocolDosing: Codable, Hashable {
    /// Typical dose range low/high (either may be nil for a single fixed dose).
    let lowAmount: Double?
    let highAmount: Double?
    /// Localized frequency, e.g. "2×/day", "once weekly", "every 2 months".
    let frequency: String
    /// Optional titration ramp (dose escalates over time).
    let titration: [TitrationStep]?
    /// Course length, e.g. "8–12 weeks", "cycle then break". nil = ongoing/unknown.
    let courseDuration: String?
    /// Administration notes, e.g. "fasted", "before sleep".
    let notes: String?

    init(
        lowAmount: Double? = nil,
        highAmount: Double? = nil,
        frequency: String,
        titration: [TitrationStep]? = nil,
        courseDuration: String? = nil,
        notes: String? = nil,
    ) {
        self.lowAmount = lowAmount
        self.highAmount = highAmount
        self.frequency = frequency
        self.titration = titration
        self.courseDuration = courseDuration
        self.notes = notes
    }
}

/// How a peptide/biologic is supplied — determines whether reconstitution UI
/// applies and how the substance is handled.
enum SuppliedForm: String, Codable, Hashable {
    /// Freeze-dried powder in an mg vial — must be reconstituted before use.
    case lyophilizedVial = "lyophilized_vial"
    /// Ready-to-inject solution (prefilled pen/vial).
    case solution
    /// Topical serum/cream (cosmetic peptides) — dosed as a formulation %.
    case topical
    /// Slow-release implant (e.g. Scenesse).
    case implant
    /// Orally administered capsule/tablet.
    case oralCapsule = "oral_capsule"

    var displayName: LocalizedStringResource {
        switch self {
        case .lyophilizedVial: "Lyophilized powder (vial)"
        case .solution: "Ready-to-inject solution"
        case .topical: "Topical formulation"
        case .implant: "Slow-release implant"
        case .oralCapsule: "Oral capsule"
        }
    }

    /// Whether the reconstitution calculator is meaningful for this form.
    var isReconstituted: Bool {
        self == .lyophilizedVial
    }
}

/// Cold-chain / handling requirement for a peptide or biologic.
struct StorageRequirement: Codable, Hashable {
    enum Temperature: String, Codable, Hashable {
        case roomTemp = "room_temp"
        case refrigerate
        case freeze

        var displayName: LocalizedStringResource {
            switch self {
            case .roomTemp: "Room temperature"
            case .refrigerate: "Refrigerate (2–8 °C)"
            case .freeze: "Freeze"
            }
        }

        /// SF Symbol summarizing the requirement.
        var icon: String {
            switch self {
            case .roomTemp: "thermometer.medium"
            case .refrigerate: "refrigerator"
            case .freeze: "snowflake"
            }
        }
    }

    let temperature: Temperature
    let lightSensitive: Bool
    /// Days the product stays stable once reconstituted (refrigerated). nil = unknown.
    let reconstitutedStabilityDays: Double?

    init(temperature: Temperature, lightSensitive: Bool = false, reconstitutedStabilityDays: Double? = nil) {
        self.temperature = temperature
        self.lightSensitive = lightSensitive
        self.reconstitutedStabilityDays = reconstitutedStabilityDays
    }
}

/// Peptide/biologic-specific reference data. Presence switches the detail UI to
/// a peptide presentation (amino-acid sequence, handling, reconstitution) instead
/// of the psychoactive trip-arc model.
struct PeptideProfile: Codable, Hashable {
    /// Amino-acid sequence, one-letter with modification notes
    /// (e.g. "Ac-Nle-cyclo[Asp-His-D-Phe-Arg-Trp-Lys]-NH2"). nil = not published.
    let sequence: String?
    let suppliedForm: SuppliedForm?
    /// Typical vial size in mg, seeds the reconstitution calculator.
    let typicalVialMg: Double?
    /// Recommended reconstitution solvent (e.g. "Bacteriostatic water").
    let reconstitutionSolvent: String?
    let storage: StorageRequirement?
    /// IU↔mg bridge for hormones dosed in international units (GH, HCG, …).
    let iuPerMg: Double?

    init(
        sequence: String? = nil,
        suppliedForm: SuppliedForm? = nil,
        typicalVialMg: Double? = nil,
        reconstitutionSolvent: String? = nil,
        storage: StorageRequirement? = nil,
        iuPerMg: Double? = nil,
    ) {
        self.sequence = sequence
        self.suppliedForm = suppliedForm
        self.typicalVialMg = typicalVialMg
        self.reconstitutionSolvent = reconstitutionSolvent
        self.storage = storage
        self.iuPerMg = iuPerMg
    }

    /// True when at least one field carries usable information.
    var hasAnyValue: Bool {
        sequence != nil || suppliedForm != nil || typicalVialMg != nil
            || reconstitutionSolvent != nil || storage != nil || iuPerMg != nil
    }
}
