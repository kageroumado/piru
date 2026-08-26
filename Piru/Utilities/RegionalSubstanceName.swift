import Foundation
import os

/// Region-aware display names for substances whose common name differs by
/// region — "Acetaminophen" (US) vs "Paracetamol", "Albuterol" (US) vs
/// "Salbutamol", "Oestradiol" (UK) vs "Estradiol", and so on.
///
/// The bundled database stores one canonical name and keeps the other spelling
/// as a searchable alias. This type picks which spelling to *show* for the
/// device region: each entry has a `base` spelling shown by default and an
/// `alternate` shown only in its regions. The split is genuinely per-drug — the
/// US/Canada/Japan say "acetaminophen" while only the UK and Commonwealth say
/// "oestradiol" — so a single global "US vs rest" flag won't do.
///
/// Display-only: both spellings remain searchable via the substance's aliases,
/// so search results are identical regardless of region.
///
/// The variants come from the bundled DB's `regional_names`, loaded once by
/// ``SubstanceStore`` at index build. They are held in a lock-guarded static
/// rather than read per call because the one caller — ``Substance/displayTitle``
/// — is `nonisolated` and runs inside the detached library sort, where a GRDB
/// hop per row would be the sort's dominant cost. Before the load lands,
/// ``resolve(canonicalName:region:)`` returns `nil` and every caller falls back
/// to the canonical name.
nonisolated enum RegionalSubstanceName {
    struct Variant: Sendable {
        /// Shown by default, everywhere outside ``alternateRegions``.
        let base: String
        let alternate: String
        /// ISO 3166-1 alpha-2 region codes.
        let alternateRegions: Set<String>
    }

    /// Keyed by the canonical name, lowercased. `base`/`alternate` are stated
    /// explicitly per entry, so it doesn't matter which spelling the database
    /// happens to use as the canonical row.
    private static let table = OSAllocatedUnfairLock<[String: Variant]>(initialState: [:])

    /// Install the variants read from `regional_names`. Called once per store init.
    static func load(_ variants: [String: Variant]) {
        table.withLock { $0 = variants }
    }

    /// The region-appropriate spelling for `canonicalName` in the device region,
    /// or `nil` when the substance has no regional variant (the caller keeps its
    /// existing name).
    static func resolve(canonicalName: String) -> String? {
        resolve(canonicalName: canonicalName, region: Locale.current.region?.identifier)
    }

    /// Region-injectable core, exposed for tests. `region` is an ISO region code
    /// (e.g. "US", "GB"); `nil` is treated as the US default.
    static func resolve(canonicalName: String, region: String?) -> String? {
        guard let variant = table.withLock({ $0[canonicalName.lowercased()] }) else { return nil }
        return variant.alternateRegions.contains(region ?? "US") ? variant.alternate : variant.base
    }
}
