import Foundation

/// What to call a logged dose.
///
/// The one place the title precedence lives (`Specs/psid-identity-consumption.md`
/// LB-3). Every in-app surface that renders a dose's name resolves here, so the
/// journal, session detail, entry detail, the Live Activity, and the PDF all
/// answer the same question the same way.
///
/// ```
/// 1. User relabel        — explicit standing intent, always wins
/// 2. Product name        — the user's word at capture ("Concerta", "Vyvanse")
/// 3. Composed form title — the catalog's, for the form the dose recorded
/// 4. displayNameSnapshot — locale-stable anchor, for catalog misses
/// 5. Raw substance       — never dropped
/// ```
///
/// **Not for identity-poor surfaces.** The widgets can't reach the catalog, so
/// they read ``DoseEntry/displayNameSnapshot`` directly instead of resolving
/// here — see `RecentDoseWidget`. In-app the snapshot is a *fallback*, never the
/// source: it is deliberately canonical, region-unresolved, and un-relabelled, so
/// rendering it directly would show "Acetaminophen" to a Paracetamol region and
/// drop the user's relabel.
enum DoseTitle {
    /// The dose's title, resolved live.
    ///
    /// Resolves through ``SubstanceLibrary/lookup(_:)`` — a dict hit over
    /// the warm batch cache — never `lookupByNameOrAlias`, which is ~21 SQL per
    /// substance on a cold cache. Cheap enough for a memoized derive layer;
    /// **not** cheap enough for a row `body`. Call it from `JournalModel.derived`
    /// or a `DayEntryCore` builder, not from a view.
    @MainActor
    static func resolve(for entry: DoseEntry) -> String {
        let substance = SubstanceLibrary.lookup(entry.substance)
        // Resolve to the canonical name *first*, then ask about a relabel. The
        // relabel table is canonical-name-keyed while the catalog resolves names
        // or aliases, so looking up the raw string would miss the relabel on any
        // dose logged under an alias.
        let canonical = substance?.name ?? entry.substance

        // 1. A relabel is a standing "always call this X" and outranks everything,
        //    including regionalization — which it loses to today, because the
        //    overlay injects it into `displayName` and `displayTitle` resolves the
        //    regional variant ahead of that. Fixing it here rather than in
        //    `displayTitle` keeps the blast radius to dose titles; the library and
        //    inventory keep the old order (a noted tension, spec §Non-goals).
        if let relabel = CustomSubstanceStore.shared.relabel(forCanonicalName: canonical) {
            return relabel
        }

        // 2. The user's own word. Outranked only by a relabel, because "this dose
        //    was Concerta" is a weaker claim than "always call this X".
        if let product = entry.productName?.trimmingCharacters(in: .whitespaces), !product.isEmpty {
            return product
        }

        // 3. The catalog's title for the form this dose recorded — "Esketamine"
        //    for a picked isomer, "Methylphenidate XR" for a recovered brand.
        //    Safe to render only because an unmodeled form no longer draws a
        //    contradicting curve (D.4/LB-2).
        let base: String = if entry.namesAForm, let composed = SubstanceLibrary.formTitle(
            for: canonical, isomer: entry.isomer, release: entry.releaseForm,
        ) {
            composed
        } else if let substance {
            // 4/5. No facets: the catalog's plain (regionalized) title, else the
            //      snapshot for a substance the catalog no longer knows, else the
            //      string the dose was logged under — which is never dropped.
            substance.displayTitle
        } else if let snapshot = entry.displayNameSnapshot?.trimmingCharacters(in: .whitespaces), !snapshot.isEmpty {
            snapshot
        } else {
            entry.substance
        }

        // Fold an injectable ester into the name — "Estradiol Valerate". Only an
        // ester on `saltForm`, not a mineral salt (which stays a chip), and never
        // over a relabel/product name above.
        if SubstanceStore.shared.isEster(entry.saltForm, forParentUID: substance?.substanceUID),
           let ester = entry.saltForm, !base.localizedCaseInsensitiveContains(ester) {
            return "\(base) \(ester)"
        }
        return base
    }

    /// The locale-stable identity anchor to persist on a dose —
    /// ``DoseEntry/displayNameSnapshot``.
    ///
    /// Deliberately **canonical**: never region-resolved (Acetaminophen, not
    /// Paracetamol) and never relabelled. It is what the identity-poor surfaces
    /// read (widgets, which can't reach the catalog) and what in-app rendering
    /// falls back to when the catalog no longer knows a substance. Regionalizing
    /// it would also be impossible to undo later — `RegionalSubstanceName` keys on
    /// a canonical substance name, and "Methylphenidate XR" is not one.
    ///
    /// Every write site must call this: composing the answer independently per
    /// call site risks inconsistent snapshots for the same substance — e.g. one
    /// path capturing only the isomer's name while another captures the full
    /// composed title for the same Concerta dose.
    @MainActor
    static func snapshot(canonicalName: String, isomer: String?, releaseForm: String?) -> String? {
        SubstanceLibrary.formTitle(for: canonicalName, isomer: isomer, release: releaseForm)
            ?? SubstanceLibrary.lookup(canonicalName)?.name
    }
}

extension DoseEntry {
    /// Whether this dose records a form distinct from the substance's default —
    /// a picked isomer or a named release form. Drives whether a title composes
    /// (``DoseTitle``) rather than reading the plain catalog title.
    nonisolated var namesAForm: Bool {
        let namesIsomer = (isomer?.isEmpty == false) && isomer != "0"
        return namesIsomer || namesUnmodeledForm
    }
}
