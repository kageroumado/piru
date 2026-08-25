import Foundation

/// A substance's drug.community intensity spectrum, as a sequence of dose bands.
///
/// Community-reported experiential data — distinct from Piru's vetted science
/// cards. Powers the circular dose-intensity dial on the Effects & Intensity
/// screen. dc's six fixed levels are mapped onto Piru's dose-band vocabulary at
/// ingest (`drug_community_effects.py`); the top band is "Overdose".
struct SpectrumBand: Identifiable, Hashable {
    /// 0 = Threshold … 5 = Overdose. Also the display order.
    let bandIndex: Int
    /// Raw band key (`"Threshold"`…`"Overdose"`); the view maps it to a
    /// localized label — never show this string directly.
    let bandKey: String
    /// What the experience is like at this dose band.
    let summary: String
    /// The effects most often reported at this band, frequency-descending.
    let topEffects: [BandEffect]

    var id: Int {
        bandIndex
    }
    var isOverdose: Bool {
        bandIndex >= 5
    }
}

/// An effect and how many reports mentioned it at a given dose band.
struct BandEffect: Hashable {
    let name: String
    let frequency: Int
}

/// A drug.community reported effect, enriched with how often it's reported and
/// the dose band at which it first becomes prominent. Grouped by ``domain`` in
/// the UI and sorted by ``reportCount``.
///
/// `name` is the raw drug.community string (kept for identity/dedup). `displayName`
/// is the short, localized label resolved from the effect vocabulary when a curated
/// alias matched (falling back to `name` — no-silent-caps).
struct ReportedEffect: Identifiable, Hashable {
    let name: String
    /// Short, locale-resolved label for the UI (canonical vocab term when mapped,
    /// else the raw `name`). Defaults to `name` for call sites that don't resolve it.
    var displayName: String
    let domain: EffectDomain
    let reportCount: Int
    /// Dose band (0…5) at which this effect first becomes prominent, if known.
    let emergesBand: Int?

    init(name: String, displayName: String? = nil, domain: EffectDomain, reportCount: Int, emergesBand: Int?) {
        self.name = name
        self.displayName = displayName ?? name
        self.domain = domain
        self.reportCount = reportCount
        self.emergesBand = emergesBand
    }

    var id: String {
        name
    }
}

/// The coarse experiential domain a reported effect belongs to. drug.community's
/// 21 fine-grained domains are folded into these five UI groups at ingest.
/// `rawValue` matches the stored `reported_effects.domain` string.
enum EffectDomain: String, CaseIterable {
    case emotional = "Emotional"
    case cognitive = "Cognitive"
    case sensory = "Sensory"
    case physical = "Physical"
    case social = "Social"
}
