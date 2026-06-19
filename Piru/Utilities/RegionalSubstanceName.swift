import Foundation

/// Region-aware display names for substances whose common name differs by
/// region — "Acetaminophen" (US) vs "Paracetamol", "Albuterol" (US) vs
/// "Salbutamol", "Oestradiol" (UK) vs "Estradiol", and so on.
///
/// The bundled database stores one canonical name and keeps the other spelling
/// as a searchable alias. This type picks which spelling to *show* for the
/// device region: each entry has a `base` spelling shown by default and an
/// `alternate` shown only in `alternateRegions`. The split is genuinely
/// per-drug — the US/Canada/Japan say "acetaminophen" while only the UK and
/// Commonwealth say "oestradiol" — so a single global "US vs rest" flag won't do.
///
/// Display-only: both spellings remain searchable via the substance's aliases,
/// so search results are identical regardless of region.
nonisolated enum RegionalSubstanceName {
    private struct Variant {
        let base: String // shown by default (most of the world)
        let alternate: String // shown only in `alternateRegions`
        let alternateRegions: Set<String>
    }

    /// Regions that use US adopted drug names (acetaminophen, epinephrine, …) —
    /// Canada and Japan follow USAN here, unlike most of the world.
    private static let usAdoptedNameRegions: Set<String> = ["US", "CA", "JP"]
    /// Regions that keep the British "oe-" spellings (oestradiol, oestrogen).
    private static let britishSpellingRegions: Set<String> = ["GB", "IE", "AU", "NZ"]

    /// Keyed by the canonical name, lowercased. `base`/`alternate` are stated
    /// explicitly per entry, so it doesn't matter which spelling the database
    /// happens to use as the canonical row.
    private static let variants: [String: Variant] = [
        "acetaminophen": Variant(base: "Paracetamol", alternate: "Acetaminophen", alternateRegions: usAdoptedNameRegions),
        "epinephrine": Variant(base: "Adrenaline", alternate: "Epinephrine", alternateRegions: usAdoptedNameRegions),
        "norepinephrine": Variant(base: "Noradrenaline", alternate: "Norepinephrine", alternateRegions: usAdoptedNameRegions),
        // "Albuterol" is US-only — Canada and Japan use the INN "Salbutamol".
        "salbutamol": Variant(base: "Salbutamol", alternate: "Albuterol", alternateRegions: ["US"]),
        "chlorpheniramine": Variant(base: "Chlorphenamine", alternate: "Chlorpheniramine", alternateRegions: ["US", "CA"]),
        // INN is "estradiol" (the US and most of the world); only the UK and
        // Commonwealth keep "oestradiol".
        "estradiol": Variant(base: "Estradiol", alternate: "Oestradiol", alternateRegions: britishSpellingRegions),
    ]

    /// The region-appropriate spelling for `canonicalName` in the device region,
    /// or `nil` when the substance has no regional variant (the caller keeps its
    /// existing name).
    static func resolve(canonicalName: String) -> String? {
        resolve(canonicalName: canonicalName, region: Locale.current.region?.identifier)
    }

    /// Region-injectable core, exposed for tests. `region` is an ISO region code
    /// (e.g. "US", "GB"); `nil` is treated as the US default.
    static func resolve(canonicalName: String, region: String?) -> String? {
        guard let variant = variants[canonicalName.lowercased()] else { return nil }
        return variant.alternateRegions.contains(region ?? "US") ? variant.alternate : variant.base
    }
}
