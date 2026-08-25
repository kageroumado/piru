import SwiftUI

/// The pharmacology cluster: the unified Pharmacology (mechanism) card, the
/// pharma-nerd Receptor Literature / Pharmacokinetics / Metabolism disclosures,
/// and the metabolic-interaction and contraceptive-caution banners. Grouped into
/// one subview so the async pharma fields (`literatureBindings`, `pkRoutes`,
/// `metabolismRows`, …) invalidate only this boundary as they load off the store,
/// not the whole detail screen. Owns its own disclosure state, so the parent
/// carries none of the `*Expanded` flags.
struct PharmacologySections: View {
    let substance: Substance
    let model: SubstanceDetailModel
    let policy: DisclosurePolicy
    let profile: UserProfile
    let onGlossary: (PharmacologyGlossarySheet.Topic) -> Void

    private enum Disclosure: Hashable {
        case mechanism
        case receptorLit
        case pharmacokinetics
        case metabolism
    }

    /// Section expansion state. Absence of a key means "use the policy default
    /// for the current tier"; once the user toggles a section, the stored Bool
    /// sticks. The keys are dropped on profile change so the new tier's defaults
    /// take effect (otherwise the user would be permanently stuck on whatever
    /// defaults applied the first time the section was rendered).
    @State private var expanded: [Disclosure: Bool] = [:]

    /// The metabolites worth a section — the ones that outlive the dose. See
    /// ``ActiveMetabolite/earnsOwnSection(parentHalfLifeMinutes:parentDurationMinutes:)``;
    /// the rest stay in the Metabolism disclosure below rather than being
    /// promoted to a headline that implies news.
    private var durationChangingMetabolites: [ActiveMetabolite] {
        model.activeMetabolites.filter {
            $0.earnsOwnSection(
                parentHalfLifeMinutes: substance.halfLifeMinutes,
                parentDurationMinutes: substance.longestRouteDurationMinutes,
            )
        }
    }

    /// Metabolites whose formation runs through a polymorphic enzyme
    /// (CYP2D6/CYP2C19) *and* that carry real effect — the codeine → morphine,
    /// tramadol → M1, oxycodone → oxymorphone, atomoxetine, aripiprazole set.
    /// How much of a dose you convert is substantially genetic, which is the
    /// single most actionable fact on those drugs. It belongs in Metabolism as a
    /// calm line rather than as a headline (the review's editorial gate keeps
    /// divergent/ratio facts out of "Also Active"). Suppressed for any metabolite
    /// that already earns an "Also Active" card — its own card states it — so the
    /// note never appears twice on one screen.
    private var polymorphicConversionMetabolites: [ActiveMetabolite] {
        let carded = Set(durationChangingMetabolites.map(\.id))
        return model.activeMetabolites.filter {
            $0.conversionVariesByGenetics && $0.isMateriallyActive && !carded.contains($0.id)
        }
    }

    var body: some View {
        let hero = model.pharmacologyHero(category: substance.category)

        Group {
            // Unified Pharmacology card — merges the former Mechanism-of-Action and
            // Monoamine-Profile sections (hybrid redesign step 2). The monoamine slider
            // hero appears inline when the substance has a monoamine profile.
            if policy.showsMechanism, let moa = composedMechanism {
                CollapsibleSection(
                    "Pharmacology",
                    onInfo: { onGlossary(.mechanism) },
                    isExpanded: binding(.mechanism, default: policy.mechanismDefaultExpanded),
                ) {
                    // Card and footer share one row — see ``DoseDurationSection``
                    // for why a peer row grows a hairline at some card heights.
                    VStack(alignment: .leading, spacing: 0) {
                        // Load-bearing, not decoration. Every number below this line was
                        // measured on the molecule, and without the line the card reads as
                        // receptor data for a plant — which is how cannabis came to carry a
                        // CB1 Kᵢ in the first place.
                        if let ingredient = ActiveIngredient.resolve(substance.name) {
                            ActiveIngredientNote(
                                preparation: substance.displayTitle,
                                ingredient: ingredient,
                                accent: substance.category.color,
                            )
                        }
                        PharmacologyCard(
                            moa: moa,
                            monoamine: model.monoamineProfile,
                            category: substance.category,
                            hero: hero,
                            signature: model.classSignature,
                            onMonoamineInfo: { onGlossary(.monoamine) },
                        )
                        if let cascade = model.signallingCascade {
                            SignallingCascadeRow(cascade: cascade, accent: substance.category.color)
                        }
                        if let slug = model.provenance?.mechanismSource {
                            SourceAttributionRow(
                                slug: slug,
                                label: "Mechanism",
                                deepLink: SubstanceSourceLinks.deepLink(slug, substance: substance),
                                substanceName: substance.name, field: .mechanism,
                            )
                        }
                    }
                }
            }

            // Suppressed for receptor-panel classes (opioid/benzo/dissociative): their hero already
            // carries the primary receptors, so a second table would duplicate it.
            if policy.showsReceptorLiterature, hero == nil, !model.visibleLiteratureBindings.isEmpty {
                CollapsibleSection(
                    "Receptor Literature",
                    onInfo: { onGlossary(.receptor) },
                    isExpanded: binding(.receptorLit, default: policy.receptorLitDefaultExpanded),
                ) {
                    GroupedReceptorLiterature(rows: model.visibleLiteratureBindings, accent: substance.category.color)
                        .padding(.vertical, 4)
                }
            }

            // "Also Active" moved OUT of this cluster and onto the main screen
            // (``AlsoActiveSection``): it answers "is something other than what
            // I took producing this effect?", which is a fact about the user's
            // experience rather than pharmacology reference data — and this
            // cluster is hidden entirely below the Pharma Nerd tier, so living
            // here meant most readers never saw it.

            if policy.showsPharmacokinetics, !model.pkRoutes.isEmpty {
                CollapsibleSection(
                    "Pharmacokinetics",
                    onInfo: { onGlossary(.pharmacokinetics) },
                    isExpanded: binding(.pharmacokinetics, default: policy.pharmacokineticsDefaultExpanded),
                ) {
                    pharmacokineticsBody
                }
            }

            // Metabolism (CYP enzymes / metabolites) — split out of Pharmacokinetics into its own
            // section and placed next to the metabolic-interaction banners below: it's the more
            // actionable, grapefruit-adjacent half of the PK story.
            // No ⓘ on this header. ``AlsoActiveSection`` already opens the identical
            // `.metabolism` sheet, and it is the only ⓘ a Casual reader can reach —
            // so the duplicate to cut is this one, not that one.
            if policy.showsPharmacokinetics, !model.metabolismRows.isEmpty {
                CollapsibleSection(
                    "Metabolism",
                    isExpanded: binding(.metabolism, default: policy.pharmacokineticsDefaultExpanded),
                ) {
                    metabolismBody
                }
            }

            // Metabolic modulation (Stage 4c) — grapefruit/smoking/self-edge education for
            // substances with a major clearance route through a modulated enzyme.
            if !model.metabolicEducation.isEmpty {
                Section {
                    ForEach(model.metabolicEducation) { effect in
                        MetabolicModulationBanner(effect: effect)
                    }
                } header: {
                    // No ⓘ: each banner states its own effect in a sentence, so a help sheet one
                    // header below the Metabolism card was the sixth ⓘ on one screen and explained
                    // nothing the banner didn't.
                    Text("Metabolism Interactions")
                }
            }

            // Measured PK interactions from the literature, below the predicted
            // modulation banners above. The order is the claim strength: those are
            // modeled and badged as predictions, these are what a study measured.
            // Two thirds of these rows name a drug *class* rather than a drug, which
            // is why they live here on the substance's own page — the pair matcher in
            // `InteractionChecker` can only ever fire on the third that names
            // something the catalog carries.
            if policy.showsPharmacokinetics, !model.pkInteractions.isEmpty {
                Section {
                    // One List row holding a stack, not a row per element: a
                    // `Divider()` emitted as a sibling of the row inside a
                    // `ForEach` lands in that row's implicit horizontal layout
                    // and draws as a short VERTICAL rule with blank space
                    // around it.
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.pkInteractions) { hit in
                            PKInteractionRow(hit: hit)
                            if hit.id != model.pkInteractions.last?.id { Divider() }
                        }
                    }
                } header: {
                    Text("Measured Interactions")
                }
            }

            // Enzyme-induction contraceptive caution — a CYP3A4 inducer (modafinil, rifampicin, …)
            // can lower hormonal-contraception levels. Ungated (a safety fact), kept to one compact
            // note since it only applies to people on hormonal birth control.
            if let contraceptionCaution = model.contraceptionCaution {
                Section {
                    ContraceptionCautionBanner(inducer: contraceptionCaution)
                }
            }
        }
        .onChange(of: profile) { _, _ in
            // Reset stuck overrides so the new tier's policy defaults win. Any
            // disclosure the user touches after this point sticks until the next
            // profile change.
            expanded[.mechanism] = nil
            expanded[.receptorLit] = nil
            expanded[.pharmacokinetics] = nil
        }
    }

    private func binding(_ key: Disclosure, default def: Bool) -> Binding<Bool> {
        Binding(
            get: { expanded[key] ?? def },
            set: { expanded[key] = $0 },
        )
    }

    /// Mechanism shown in the detail card, composed from three sources by
    /// precedence so real receptor data isn't hidden behind a generic template.
    /// This keeps substances with clear receptor data (mephedrone, the MMC
    /// cathinones) from showing a generic "Monoamine Modulator" mechanism.
    private var composedMechanism: MechanismOfAction? {
        MechanismOfActionDatabase.resolvedMechanism(
            dbMechanism: substance.mechanismOfAction,
            substanceName: substance.name,
            category: substance.category,
        )
    }

    /// Per-route PK (bioavailability/tmax/half-life) above the CYP metabolism
    /// pathways, each row carrying its own source/citation. Mirrors the Receptor
    /// Literature layout — dense, attributed, pharma-nerd-only.
    private var pharmacokineticsBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.pkRoutes) { row in
                PKRouteRow(hit: row.hit, studyCount: row.studyCount, accent: substance.category.color)
                if row.id != model.pkRoutes.last?.id { Divider() }
            }
            // What the numbers above mean at a given plasma level. Under the
            // routes rather than beside them: a threshold is about the drug, not
            // about how it got in.
            if !model.concentrationThresholds.isEmpty {
                Divider()
                ForEach(model.concentrationThresholds) { hit in
                    ConcentrationThresholdRow(hit: hit, accent: substance.category.color)
                    if hit.id != model.concentrationThresholds.last?.id { Divider() }
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// The CYP/enzyme clearance pathways and their metabolites — its own section
    /// now, sitting next to the grapefruit/smoking interaction banners (which act
    /// on these same enzymes).
    /// The single row that should carry each curated divergent note. Several raw
    /// rows can name one metabolite family (MDMA lists MDA, S-MDA and R-MDA, all
    /// matching the MDA note), so the note is pinned to the first matching row —
    /// which in practice is the canonical one that also resolves to the library.
    private var divergentNoteRowIDs: Set<SubstanceStore.MetabolismHit.ID> {
        var seenNotes = Set<String>()
        var out = Set<SubstanceStore.MetabolismHit.ID>()
        for hit in model.metabolismRows {
            guard let metabolite = hit.metaboliteName,
                  let note = MetaboliteEditorial.divergentNote(parent: substance.name, metabolite: metabolite)
            else { continue }
            if seenNotes.insert(String(localized: note)).inserted { out.insert(hit.id) }
        }
        return out
    }

    private var metabolismBody: some View {
        let noteRows = divergentNoteRowIDs
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(model.metabolismRows) { hit in
                // The metabolite row now folds its own curated "acts differently"
                // one-liner in (parentName keys ``MetaboliteEditorial``), deduped to
                // one row, so the separate divergent-notes block below is gone.
                MetabolismRow(
                    hit: hit,
                    accent: substance.category.color,
                    parentName: substance.name,
                    showsDivergentNote: noteRows.contains(hit.id),
                )
                if hit.id != model.metabolismRows.last?.id { Divider() }
            }
            // The "conversion is partly genetic" line stays as a section note — it's
            // a between-people fact, not tied to any single metabolite row.
            if !polymorphicConversionMetabolites.isEmpty {
                Divider()
                metabolismNote(
                    "How much of a dose becomes its active form is partly genetic — the same dose can produce noticeably more effect in some people than in others.",
                    systemImage: "person.2",
                )
            }
        }
        .padding(.vertical, 4)
    }

    /// A caption-weight note beneath the enzyme pathways — the divergent-metabolite
    /// sentences and the genetic-conversion line. Caption weight keeps it a note,
    /// not a headline; the leading glyph signals the axis (branch = different
    /// pharmacology, person-pair = between-people variability).
    private func metabolismNote(_ text: LocalizedStringResource, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "Cannabis acts through Δ9-THC — everything below is THC's." The one line that
/// keeps a preparation's pharmacology card from reading as receptor data for a
/// plant. See ``ActiveIngredient`` for why the mapping exists at all.
struct ActiveIngredientNote: View {
    let preparation: String
    let ingredient: String
    let accent: Color

    @Environment(\.appNavigator) private var navigator

    var body: some View {
        Button {
            navigator.push(.substance(name: ingredient))
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "arrow.trianglehead.branch")
                    .font(.caption2)
                    .accessibilityHidden(true)
                // Both names are proper nouns supplied at runtime, so the sentence
                // is a catalog key with two substituted names rather than three
                // concatenated `Text`s (`Text + Text` is deprecated in iOS 26).
                Text(
                    "\(preparation) acts through \(ingredient) — the pharmacology below is \(ingredient)'s.",
                    comment: "Preparation borrowing its active ingredient's pharmacology",
                )
                .font(.caption)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(accent)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 10)
    }
}
