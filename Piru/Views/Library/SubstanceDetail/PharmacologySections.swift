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
    /// Pushes a metabolite's own detail from an "Also Active" card.
    @Environment(\.appNavigator) private var navigator

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

    var body: some View {
        let hero = model.pharmacologyHero(category: substance.category)

        Group {
            // Unified Pharmacology card — merges the former Mechanism-of-Action and
            // Monoamine-Profile sections (hybrid redesign step 2). The monoamine slider
            // hero appears inline when the substance has a monoamine profile.
            if policy.showsMechanism, let moa = composedMechanism {
                CollapsibleSection(
                    "Pharmacology",
                    systemImage: "atom",
                    onInfo: { onGlossary(.mechanism) },
                    isExpanded: binding(.mechanism, default: policy.mechanismDefaultExpanded),
                ) {
                    PharmacologyCard(moa: moa, monoamine: model.monoamineProfile, category: substance.category, hero: hero)
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

            // Suppressed for receptor-panel classes (opioid/benzo/dissociative): their hero already
            // carries the primary receptors, so a second table would duplicate it.
            if policy.showsReceptorLiterature, hero == nil, !model.visibleLiteratureBindings.isEmpty {
                CollapsibleSection(
                    "Receptor Literature",
                    systemImage: "function",
                    onInfo: { onGlossary(.receptor) },
                    isExpanded: binding(.receptorLit, default: policy.receptorLitDefaultExpanded),
                ) {
                    GroupedReceptorLiterature(rows: model.visibleLiteratureBindings, accent: substance.category.color)
                        .padding(.vertical, 4)
                }
            }

            // "Also Active" — the metabolites doing some of the work. Sits above
            // the reference sections because it answers a different question
            // than they do ("is something other than what I took producing the
            // effect?"), and at a lower tier for the same reason: it is a fact
            // about the user's experience, not pharmacology reference data.
            // Deliberately not collapsible — usually one card, and folding it
            // re-buries the thing being surfaced.
            if !durationChangingMetabolites.isEmpty {
                Section {
                    ForEach(durationChangingMetabolites) { metabolite in
                        ActiveMetaboliteCard(
                            metabolite: metabolite,
                            parentName: substance.displayTitle,
                            parentHalfLifeMinutes: substance.halfLifeMinutes,
                            accent: substance.category.color,
                            parentDurationMinutes: substance.longestRouteDurationMinutes,
                            onOpenSubstance: { navigator.push(.substance(name: $0)) },
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    sectionHeaderWithInfo(
                        "Also Active",
                        systemImage: "arrow.trianglehead.branch",
                        topic: .metabolism,
                    )
                }
            }

            if policy.showsPharmacokinetics, !model.pkRoutes.isEmpty {
                CollapsibleSection(
                    "Pharmacokinetics",
                    systemImage: "waveform.path.ecg",
                    onInfo: { onGlossary(.pharmacokinetics) },
                    isExpanded: binding(.pharmacokinetics, default: policy.pharmacokineticsDefaultExpanded),
                ) {
                    pharmacokineticsBody
                }
            }

            // Metabolism (CYP enzymes / metabolites) — split out of Pharmacokinetics into its own
            // section and placed next to the metabolic-interaction banners below: it's the more
            // actionable, grapefruit-adjacent half of the PK story.
            if policy.showsPharmacokinetics, !model.metabolismRows.isEmpty {
                CollapsibleSection(
                    "Metabolism",
                    systemImage: "arrow.triangle.branch",
                    onInfo: { onGlossary(.metabolism) },
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
                    // Not "fork.knife" — smoking and enzyme induction aren't eating; an up/down glyph
                    // reads as "these change the drug's levels". Trailing (i) explains the section.
                    sectionHeaderWithInfo(
                        "Metabolism Interactions",
                        systemImage: "arrow.up.arrow.down",
                        topic: .metabolismInteractions,
                    )
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
            ForEach(model.pkRoutes) { hit in
                PKRouteRow(hit: hit, accent: substance.category.color)
                if hit.id != model.pkRoutes.last?.id { Divider() }
            }
        }
        .padding(.vertical, 4)
    }

    /// The CYP/enzyme clearance pathways and their metabolites — its own section
    /// now, sitting next to the grapefruit/smoking interaction banners (which act
    /// on these same enzymes).
    private var metabolismBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.metabolismRows) { hit in
                MetabolismRow(hit: hit, accent: substance.category.color)
                if hit.id != model.metabolismRows.last?.id { Divider() }
            }
        }
        .padding(.vertical, 4)
    }

    /// A plain `Section` header (icon + title) with a trailing (i) that opens the card's help sheet —
    /// the equivalent of `CollapsibleSection`'s `onInfo` for the non-collapsible interaction sections.
    private func sectionHeaderWithInfo(
        _ title: LocalizedStringResource,
        systemImage: String,
        topic: PharmacologyGlossarySheet.Topic,
    ) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Button { onGlossary(topic) } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(Theme.accent)
                    .textCase(nil)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("What do these mean?")
        }
    }
}
