import Foundation

/// Region-aware display names for substances whose common name differs between
/// the US adopted name and the international / INN spelling — "Acetaminophen"
/// vs "Paracetamol", "Albuterol" vs "Salbutamol", and so on.
///
/// The bundled database stores a single canonical name and keeps the other
/// spelling as a searchable alias. This type picks which spelling to *show*
/// based on the device region, so a US user sees "Acetaminophen" and a user in
/// the UK (or anywhere else) sees "Paracetamol" for the very same record.
///
/// Display-only: both spellings remain searchable via the substance's aliases,
/// so search results are identical regardless of region.
nonisolated enum RegionalSubstanceName {
    private struct Variant {
        let us: String // US adopted name (USAN)
        let intl: String // INN / rest-of-world spelling
    }

    /// Keyed by the canonical name, lowercased. The direction is stated
    /// explicitly per entry, so it doesn't matter which spelling the database
    /// happens to use as the canonical row.
    private static let variants: [String: Variant] = [
        "acetaminophen": Variant(us: "Acetaminophen", intl: "Paracetamol"),
        "salbutamol": Variant(us: "Albuterol", intl: "Salbutamol"),
        "epinephrine": Variant(us: "Epinephrine", intl: "Adrenaline"),
        "norepinephrine": Variant(us: "Norepinephrine", intl: "Noradrenaline"),
        "chlorpheniramine": Variant(us: "Chlorpheniramine", intl: "Chlorphenamine"),
        "estradiol": Variant(us: "Estradiol", intl: "Oestradiol"),
    ]

    /// Regions that use US adopted drug names. The US is the canonical case;
    /// Canada and Japan also say "acetaminophen"/"epinephrine", but the set of
    /// US-name regions is genuinely per-drug, so we don't model that divergence
    /// until it matters — add region codes here if/when it does.
    private static let usAdoptedNameRegions: Set<String> = ["US"]

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
        let usesUSNames = usAdoptedNameRegions.contains(region ?? "US")
        return usesUSNames ? variant.us : variant.intl
    }
}
