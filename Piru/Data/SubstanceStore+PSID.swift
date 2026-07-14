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

    /// Row ids sharing the PSID FAMILY `uid`, in canonical-name order; empty when
    /// unknown. Usually one row, several for co-familied-but-unfolded pairs.
    func substanceIDs(forUID uid: String) -> [Int64] {
        uidToID[uid] ?? []
    }
}
