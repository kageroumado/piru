import Foundation

/// PSID (Piru Substance ID) resolution — the forward name/alias → FAMILY + form
/// maps the Stage 0.3 dose backfill and identity-keyed features read. Split out
/// of ``SubstanceStore`` for file size; the reverse `uid → substances` lookups
/// live on the main type.
extension SubstanceStore {
    /// The PSID FAMILY (`substance_uid`) for a substance named or aliased
    /// `nameOrAlias`, or `nil` when the name doesn't resolve or the row has no uid.
    ///
    /// **Raw library value** — bypasses the custom overlay; app code resolves
    /// through ``SubstanceLibrary/substanceUID(for:)``.
    func substanceUID(forNameOrAlias nameOrAlias: String) -> String? {
        guard let id = substanceID(forNameOrAlias: nameOrAlias) else { return nil }
        return idToUIDIndex[id]
    }

    /// The isomer form-code a logged name/alias names ("Focalin" → `"D"`), from
    /// the facet-annotated alias table, or `nil` for the racemic/unspecified form.
    /// Lets the PSID backfill recover the form a legacy string logged.
    func isomer(forNameOrAlias nameOrAlias: String) -> String? {
        aliasIsomerIndex[nameOrAlias.lowercased()]
    }

    /// The release form-code a logged name/alias names ("Concerta"/"Adderall XR" →
    /// `"XR"`, "Vivitrol" → `"DEP"`), or `nil` for the standard/unspecified form.
    /// The release sibling of ``isomer(forNameOrAlias:)``; a brand can name both
    /// axes at once ("Focalin XR" → isomer `"D"` + release `"XR"`).
    func releaseForm(forNameOrAlias nameOrAlias: String) -> String? {
        aliasReleaseFormIndex[nameOrAlias.lowercased()]
    }

    /// Row ids sharing the PSID FAMILY `uid`, in canonical-name order; empty when
    /// unknown. Usually one row, several for co-familied-but-unfolded pairs.
    func substanceIDs(forUID uid: String) -> [Int64] {
        uidToID[uid] ?? []
    }

    /// Identifies one `substance_forms` row for a substance. See
    /// ``SubstanceStore/formTitleIndex`` for why this keys on the row id and omits
    /// salt. `stereo`/`release` use the PSID facet codes, where `"0"` is the
    /// racemic/standard sentinel.
    struct FormKey: Hashable {
        let substanceID: Int64
        let stereo: String
        let release: String
    }

    /// The composed display title for the form a logged name/alias names —
    /// "Dexmethylphenidate XR" for `"Focalin XR"`, "Methylphenidate XR" for
    /// `"Concerta"`, "Methylphenidate" for a plain one. `nil` when the name doesn't
    /// resolve or names no enumerated form, so callers fall back to the canonical
    /// name.
    ///
    /// Titles come straight from the build's `substance_forms`, so composition
    /// (which facet leads, how a suffix reads) is decided once, in the pipeline.
    func formTitle(forNameOrAlias nameOrAlias: String) -> String? {
        guard let id = substanceID(forNameOrAlias: nameOrAlias) else { return nil }
        return formTitleIndex[FormKey(
            substanceID: id,
            stereo: isomer(forNameOrAlias: nameOrAlias) ?? PSID.unspecifiedFacet,
            release: releaseForm(forNameOrAlias: nameOrAlias) ?? PSID.unspecifiedFacet,
        )]
    }
}
