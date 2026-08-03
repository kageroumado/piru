import SwiftUI

/// The placement-driven composition of the substance-detail screen. It reuses
/// the existing section views as content but decides — per the user's
/// disclosure tier and the compound's spine — which sections render inline,
/// which fold into a collapsed group, which move behind a "Show all" deep page,
/// and which are hidden. The single source of truth is
/// ``DisclosurePolicy/placement(for:spine:)``.
///
/// This is the thin coordinator the redesign calls for: no async data of its
/// own (that lives in the shared ``SubstanceDetailModel``), no duplicated
/// route/salt state (owned by ``SubstanceDetailView``) — just the arrangement.
struct SubstanceDetailLayout: View {
    let substance: Substance
    let model: SubstanceDetailModel
    let policy: DisclosurePolicy
    let profile: UserProfile
    let routes: RouteResolution
    let routeSelection: Binding<RouteOfAdministration>
    let saltSelection: Binding<String?>
    let isomerSelection: Binding<String?>
    let historyEntries: [DoseEntry]
    let inventoryItems: [InventoryItem]
    let selectedSaltForm: String?
    /// The user's personal-override notes for this substance, if any.
    let personalNotes: String?
    let showAllEffects: Binding<Bool>
    let showAllInventory: Binding<Bool>
    let cautionsExpanded: Binding<Bool>
    let onGlossary: (PharmacologyGlossarySheet.Topic) -> Void

    private func placement(_ section: DetailSection) -> SectionPlacement {
        policy.placement(for: section, displayClass: substance.displayClass)
    }

    var body: some View {
        // 1. Header — identity above the fold: name, category chip, alias chips,
        //    formula. Replaces the old full-width "Also known as" card.
        SubstanceDetailHeader(substance: substance)

        // 3. Your history — the user's own data leads (only when entries exist).
        if !historyEntries.isEmpty {
            HistorySection(entries: historyEntries, model: model, defaultUnit: substance.defaultUnit)
        }

        // 3. Dose & Duration — the single most-consulted card (proto10). Inline on
        //    the recreational spine; hidden on the medical one (the matrix decides).
        if placement(.doseDuration) == .inline {
            DoseDurationSection(
                routes: routes,
                routeSelection: routeSelection,
                saltSelection: saltSelection,
                isomerSelection: isomerSelection,
                provenance: model.provenance,
            )
        }

        // 4. Effects — the dose dial and what's reported at each band. The dose
        //    card above carries the same five tiers as a *grid*: same scale,
        //    different instrument for a different question.
        if placement(.effects) == .inline {
            EffectsSection(substance: substance, policy: policy, showAllEffects: showAllEffects)
        }

        // 5–6. What makes it different / In the body — mechanism · receptor · PK ·
        //      metabolism, one inline block or one deep-page target.
        pharmacologyInline

        // What else it touches — hERG, bladder, taste receptors. Called
        // unconditionally rather than through the placement matrix: it self-hides
        // on absent data and folds identically at every tier and on both spines,
        // so a matrix row would encode no decision. The matrix is for sections
        // whose placement actually varies.
        OffTargetSection(substance: substance, model: model)

        // Two class cards, each self-hiding outside its family: the benzodiazepine
        // duration ladder and the antidepressant class explainer. Same reasoning
        // as above for staying out of the placement matrix.
        BenzoDurationSection(substance: substance, model: model)
        DrugClassSection(substance: substance)

        // Metabolites doing some of the work — on the main screen at every tier.
        AlsoActiveSection(substance: substance, model: model, onGlossary: onGlossary)

        // What it is, in prose — below the dose card and the mechanism, not
        // above them. It is the least surprising thing on the screen: by the
        // time you have read how much and how it works, the encyclopedia
        // paragraph is reference, not headline. Self-hides for the ~80% of the
        // library with no overview.
        OverviewSection(substance: substance)

        // Medical lead — self-hides when the compound carries no medical data (so
        // it drops out for the recreational spine, leads for the medical one).
        MedicalInfoSection(substance: substance, cautionsExpanded: cautionsExpanded)

        // 9. Common misconceptions — collapsed, one claim row apiece.
        if placement(.misconceptions) == .inline {
            MythBustSection(misconceptions: substance.misconceptions, accent: substance.category.color)
        }

        // Peptide protocol/reconstitution (self-hides for non-peptides).
        SubstancePeptideSection(substance: substance)

        // Inventory — a logistics concern, not a "what is this" one: it drops below
        // the substance body rather than sitting between Dose and Effects.
        InventoryStockSection(
            substanceName: substance.name,
            selectedSaltForm: selectedSaltForm,
            inventoryItems: inventoryItems,
            showAllInventory: showAllInventory,
        )

        if let personalNotes, !personalNotes.trimmingCharacters(in: .whitespaces).isEmpty {
            Section("Your Notes") {
                Text(personalNotes)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        // 10. Reference depth: inline collapsed for Pharma Nerd; otherwise reached
        //     via per-section "Show all" (Curious) or the launcher (Casual).
        referenceDepth
    }

    /// The pharmacology cluster, shown inline only when its placement is inline
    /// (Pharma Nerd). At Curious it becomes a "Show all" target; at Casual it's
    /// hidden. Keyed on `.mechanism` as the cluster's representative row.
    @ViewBuilder private var pharmacologyInline: some View {
        if placement(.mechanism) != .hidden {
            PharmacologySections(
                substance: substance,
                model: model,
                policy: policy,
                profile: profile,
                onGlossary: onGlossary,
            )
        }
    }

    @ViewBuilder private var referenceDepth: some View {
        // Identity — category, default route, and the full alias list, collapsed.
        // The header's alias chips only exist for a substance with curated
        // `popularAliases` (1 of 1912 today), and the fallback deliberately
        // refuses to dump the raw alias list up there. Without this row the
        // other 1557 substances that have aliases would have no way to show
        // them at all, so identity keeps a home at reference depth.
        InfoDisclosureSection(substance: substance, model: model)

        // Inline (Pharma Nerd): render each reference section directly — each is
        // its own collapsed disclosure.
        // Chemistry and Sources are collapsed cards on the page now, not a
        // launcher pushing a screen that holds one collapsed card.
        if placement(.chemistry) != .hidden, hasChemistryData {
            ChemistrySection(substance: substance, showsMechanism: policy.showsMechanism)
        }
        if placement(.sources) != .hidden, hasSourcesData {
            SourcesSection(
                substance: substance,
                showsSources: true,
                contributions: model.sourceContributions,
            )
        }
    }

    /// Light presence check mirroring ``ChemistrySection``'s own gate, so a
    /// "Chemistry" launcher/row never leads to an empty page.
    private var hasChemistryData: Bool {
        substance.formula != nil || substance.cas != nil || substance.inchikey != nil
            || substance.molarMass != nil || substance.smiles != nil || substance.iupacName != nil
            || substance.pubchemCID != nil || (substance.physicochemical?.hasAnyValue ?? false)
    }

    /// Same call the section makes, contributions included — a gate computed
    /// from a narrower set than the section renders would hide a ledger that
    /// does have rows.
    private var hasSourcesData: Bool {
        !SubstanceSourceLinks.mergedLinks(for: substance, contributions: model.sourceContributions).isEmpty
    }
}

/// The detail header — identity above the fold, as a **title block rather than a
/// card**: the name at display size, a byline that says *what kind of thing* this
/// is (category chip · formula), and the curated "also known as" chips with an
/// overflow count for the rest of the search index.
///
/// Deliberately background-less and outside the card rhythm (proto8's `.head`):
/// as its own card the byline burned a full row of vertical space to carry one
/// chip. The screen's real title lives here — the nav bar keeps only the compact
/// one (see ``SubstanceDetailView``).
private struct SubstanceDetailHeader: View {
    let substance: Substance

    /// Popular aliases shown as chips before the overflow count.
    private var shownAliases: [String] {
        Array(substance.popularAliases.prefix(4))
    }

    /// Additional chemical/search names beyond the shown chips — the full alias
    /// index minus the curated ones already displayed.
    private var overflowCount: Int {
        let shown = Set(shownAliases.map { $0.lowercased() })
        let extras = substance.aliases.filter { alias in
            !shown.contains(alias.lowercased())
                && alias.caseInsensitiveCompare(substance.displayTitle) != .orderedSame
        }
        return extras.count
    }

    var body: some View {
        // **A section header, not a row.** In a grouped list every row is clipped
        // to a rounded rect, and at any inset that curve bites into whatever sits
        // in a corner — it was shaving the category chip at the bottom-left, and
        // no amount of slack fixes it because the clip follows the row. Section
        // headers are outside that chrome entirely, which is also what makes this
        // read as a title rather than a card pretending to be one.
        Section {
            EmptyView()
        } header: {
            VStack(alignment: .leading, spacing: 5) {
                Text(substance.displayTitle)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    // `Color.primary`, not `.primary`: a section header carries a
                    // secondary style, and the hierarchical `.primary` resolves to
                    // the primary *level of that style* — which is still gray. The
                    // absolute label color is the only way to get a black title
                    // out of a header.
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: 8) {
                    CategoryChip(category: substance.category)
                    if let formula = substance.formula {
                        Text(formula)
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.secondaryLabel)
                            .lineLimit(1)
                    }
                }

                // Framing marker (prescription / research compound / no human
                // data), on its own line rather than beside the category chip:
                // its titles are phrases, and a third item in that row overflows
                // the header at large text sizes and in Chinese.
                if let kind = SubstanceStatusMarker.Kind.resolve(for: substance) {
                    SubstanceStatusMarker(kind: kind)
                }

                if !shownAliases.isEmpty {
                    FlowLayout(spacing: 7) {
                        ForEach(shownAliases, id: \.self) { alias in
                            Text(alias)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                        if overflowCount > 0 {
                            Text("+ \(overflowCount) chemical names", comment: "Alias overflow count")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(aliasAccessibilityLabel)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Headers arrive uppercased and in the secondary style by default.
            .textCase(nil)
            .listRowInsets(EdgeInsets())
        }
        .listSectionSpacing(8)
    }

    private var aliasAccessibilityLabel: String {
        let names = shownAliases.joined(separator: ", ")
        if overflowCount > 0 {
            return String(localized: "Also known as \(names), and \(overflowCount) other names.")
        }
        return String(localized: "Also known as \(names).")
    }
}

/// A compact category tag — the accent-tinted "what kind of thing is this" chip
/// shown in the detail header (e.g. `EMPATHOGEN`, `STIMULANT`).
struct CategoryChip: View {
    let category: SubstanceCategory

    var body: some View {
        Text(category.displayName)
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(category.labelColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            // 0.10 is the alpha every scale's `text` variant is gated against. At
            // 0.14 this measured 4.40:1 on device — a fill a few percent darker
            // than the one a token was derived for is enough to fail its gate.
            .background(category.color.opacity(0.10), in: Capsule())
            .accessibilityLabel(Text(category.displayName))
    }
}
