import Foundation

/// The fixed tablet/capsule strengths a branded product ships in (Concerta →
/// 18/27/36/54 mg), from the bundled `product_strengths` table.
///
/// **Display/entry convenience only** — the strengths let a logged brand be
/// entered as a *pill* (a chip sets the dose `amount`), exactly as the alcohol
/// logger lets a drink be entered by volume. They drive no pharmacology, no PSID
/// identity, no dose ladder, and no curve.
struct ProductStrengths: Equatable {
    /// Available per-unit strengths in milligrams, ascending.
    let strengths: [Double]
    /// Dosage form — `"tablet"` or `"capsule"` (drives the count noun).
    let form: String
}

/// PSID (Piru Substance ID) resolution — the forward name/alias → FAMILY + form
/// maps the Stage 0.3 dose backfill and identity-keyed features read. The
/// reverse `uid → substances` lookups live on the main type.
extension SubstanceStore {
    /// The tablet/capsule strengths a logged product name ships in ("Concerta" →
    /// 18/27/36/54 mg tablets), or `nil` when the name isn't a known branded
    /// product — in which case the dose stays free-form milligrams.
    ///
    /// **Raw library value**, keyed by a plain lowercased product name (matching
    /// the pipeline's simple key, which deliberately keeps "Ritalin LA" distinct
    /// from "Ritalin"). Display/entry only — see ``ProductStrengths``.
    func productStrengths(forProduct name: String) -> ProductStrengths? {
        productStrengthIndex[name.lowercased().trimmingCharacters(in: .whitespaces)]
    }

    /// The duration-of-effect envelope for a named product ("Concerta" → ~12 h),
    /// or `nil` when the product isn't an authored extended-release formulation.
    /// Keyed by the plain lowercased product name (Concerta ≠ Ritalin LA ≠ Adderall
    /// XR, even though all are "XR"). Lets an ER brand draw a real curve instead of
    /// the parent's IR curve — see `product_durations`.
    func productDuration(forProduct name: String) -> DurationProfile? {
        productDurationIndex[name.lowercased().trimmingCharacters(in: .whitespaces)]
    }
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

    /// The injectable-ester label a logged name/alias names ("Estradiol Valerate" →
    /// `"Valerate"`), or `nil` for a name that doesn't name an ester. The salt/ester
    /// sibling of ``releaseForm(forNameOrAlias:)``; lets a search stage the dose with
    /// the ester pre-selected on `saltForm`.
    func saltForm(forNameOrAlias nameOrAlias: String) -> String? {
        aliasSaltFormIndex[nameOrAlias.lowercased()]
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

    /// A branded product of a substance for the QuickLog brand picker — "Concerta",
    /// "Ritalin LA", "Adderall XR". Sourced from `aliases` (kind='brand'), carrying
    /// the release the brand names (`"XR"`/nil) and whether the build has a duration
    /// curve or tablet strengths for it, so the menu can lead with the brands that
    /// draw a real curve. Brands never carry an isomer — the enantiomer axis is
    /// modeled as `distinct_substance` aliases (Focalin) reached by search — so
    /// selecting one sets `productName` + `releaseForm` only.
    struct BrandProduct: Hashable {
        let name: String
        let releaseForm: String?
        let brandRank: Int?
        let hasCurve: Bool

        /// A brand leads the menu (rather than hiding under "More…") when it draws a
        /// real curve or is a curated flagship — the ones a person is likely to take.
        var isFlagship: Bool {
            hasCurve || brandRank != nil
        }
        /// Extended-release when the brand names the XR facet; immediate/unspecified
        /// otherwise (the "Regular" path, which draws the base curve).
        var isExtendedRelease: Bool {
            releaseForm != nil && releaseForm != PSID.unspecifiedFacet
        }
    }

    /// The branded products a substance ships under, keyed by its PSID FAMILY `uid`,
    /// flagships (curve/curated) first then niche, each group alphabetical. Empty for
    /// substances with no brands; the brand picker is shown only when this is
    /// non-empty. Powers the pill that sets `productName` (→ the product-duration
    /// curve, tablet-strength chips, and brand title) from a real product name.
    func brandProducts(forUID uid: String) -> [BrandProduct] {
        brandProductsByUID[uid] ?? []
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
        formTitle(
            forNameOrAlias: nameOrAlias,
            isomer: isomer(forNameOrAlias: nameOrAlias),
            release: releaseForm(forNameOrAlias: nameOrAlias),
        )
    }

    /// ``formTitle(forNameOrAlias:)`` with the facets supplied rather than
    /// recovered from the name — the form a *logged dose* records.
    ///
    /// A dose's facets don't always come from its name: an isomer can be picked
    /// ("Ketamine" + `S` = Esketamine, where the string names no enantiomer), and
    /// the name a dose is stored under is canonical anyway, so asking it about
    /// facets would answer for the base form. Titling a dose therefore has to pass
    /// what the *entry* holds.
    ///
    /// A `nil` or `"0"` facet is the unspecified sentinel and selects the default
    /// form, so a plain dose composes its plain title.
    func formTitle(forNameOrAlias nameOrAlias: String, isomer: String?, release: String?) -> String? {
        guard let id = substanceID(forNameOrAlias: nameOrAlias) else { return nil }
        return formTitleIndex[FormKey(
            substanceID: id,
            stereo: isomer.flatMap { $0.isEmpty ? nil : $0 } ?? PSID.unspecifiedFacet,
            release: release.flatMap { $0.isEmpty ? nil : $0 } ?? PSID.unspecifiedFacet,
        )]
    }
}
