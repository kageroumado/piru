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

        // 2. What it is, in prose. The design review cut this from mid-flow when
        //    the layout was MDMA-only — there the header, dose card and dial
        //    already answer "what is this". Across the whole library they often
        //    don't: 375 substances carry an overview and most of them carry
        //    little else, so cutting it would leave their screen saying nothing.
        //    Self-hides for the ~80% with no overview, which is why it can sit
        //    here unconditionally rather than behind a sparseness heuristic.
        OverviewSection(substance: substance)

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

        // 4. Effects — the intensity gauge: "what will I feel, by dose."
        if placement(.effects) == .inline {
            EffectsSection(substance: substance, policy: policy, showAllEffects: showAllEffects)
        }

        // 5–6. What makes it different / In the body — mechanism · receptor · PK ·
        //      metabolism, one inline block or one deep-page target.
        pharmacologyInline

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
        if placement(.mechanism).isInline {
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
        if placement(.chemistry).isInline, hasChemistryData {
            ChemistrySection(substance: substance, showsMechanism: policy.showsMechanism)
        }
        if placement(.sources).isInline {
            SourcesSection(substance: substance, showsSources: true)
        }

        // Deep-page targets — pharmacology (Curious), chemistry, sources — grouped
        // under one quiet "For the curious" launcher at Casual, individual rows otherwise.
        let targets = showAllTargets
        if !targets.isEmpty {
            if profile == .casual {
                Section("For the curious") { showAllRows(targets) }
            } else {
                Section { showAllRows(targets) }
            }
        }
    }

    private func showAllRows(_ targets: [ShowAllTarget]) -> some View {
        ForEach(targets) { target in
            ShowAllRow(target: target, substanceName: substance.name)
        }
    }

    /// Reference sections whose content lives on a deep page at this tier. Gated
    /// on content presence so a "Show all" never links to a blank page (S3).
    private var showAllTargets: [ShowAllTarget] {
        var out: [ShowAllTarget] = []
        if placement(.mechanism) == .showAll, hasPharmacologyData {
            out.append(.pharmacology)
        }
        if placement(.chemistry) == .showAll, hasChemistryData {
            out.append(.chemistry)
        }
        if placement(.sources) == .showAll, hasSourcesData {
            out.append(.sources)
        }
        return out
    }

    /// Light presence check mirroring ``ChemistrySection``'s own gate, so a
    /// "Chemistry" launcher/row never leads to an empty page.
    private var hasChemistryData: Bool {
        substance.formula != nil || substance.cas != nil || substance.inchikey != nil
            || substance.molarMass != nil || substance.smiles != nil || substance.iupacName != nil
            || substance.pubChemURL != nil || (substance.physicochemical?.hasAnyValue ?? false)
    }

    /// True when the pharmacology cluster has anything to show — so its "Show
    /// all" launcher never pushes an empty page (the model fields fill in as the
    /// `.task` resolves, so the row appears once there's content).
    private var hasPharmacologyData: Bool {
        substance.mechanismOfAction != nil
            || model.monoamineProfile != nil
            || !model.literatureBindings.isEmpty
            || !model.pkRoutes.isEmpty
            || !model.metabolismRows.isEmpty
            || !model.activeMetabolites.isEmpty
    }

    private var hasSourcesData: Bool {
        !SubstanceSourceLinks.mergedLinks(for: substance).isEmpty
    }
}

// MARK: - Show-all target

/// A reference section reachable via a deep page. Backed by ``DataSection`` for
/// routing; carries its own label + icon for the launcher row.
private enum ShowAllTarget: Identifiable {
    case pharmacology
    case chemistry
    case sources

    var id: Self {
        self
    }

    var dataSection: DataSection {
        switch self {
        case .pharmacology: .pharmacology
        case .chemistry: .chemistry
        case .sources: .sources
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .pharmacology: "Pharmacology"
        case .chemistry: "Chemistry"
        case .sources: "Sources"
        }
    }

    var systemImage: String {
        switch self {
        case .pharmacology: "atom"
        case .chemistry: "flask"
        case .sources: "book"
        }
    }
}

/// The screen's primary action: open quick-log with this substance already
/// staged and its dose editor expanded, so "I'm taking this" is one tap from
/// reading about it rather than a trip back through search.
///
/// Deliberately a **content-sized** capsule in the header block rather than the
/// app's full-width `GlassPillButton`: this screen is dense reference material
/// and already sits under the global "Log a dose" dock, so a full-bleed banner
/// would both out-shout the dose card and re-spend the vertical space the
/// header byline just saved.
private struct LogNowButton: View {
    let substanceName: String

    @Environment(\.appNavigator) private var navigator

    var body: some View {
        Button {
            navigator.present(.quickLog(routine: nil, prefillSubstance: substanceName))
        } label: {
            // Text-only: with `.glassProminent` the symbol picks up the same
            // tint as the capsule and disappears into it.
            Text("Log Now")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 4)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.accent)
    }
}

/// A row that pushes a substance's deep-data page.
private struct ShowAllRow: View {
    let target: ShowAllTarget
    let substanceName: String

    @Environment(\.appNavigator) private var navigator

    var body: some View {
        Button {
            navigator.push(.substanceData(name: substanceName, section: target.dataSection))
        } label: {
            HStack {
                Label(target.title, systemImage: target.systemImage)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        Section {
            VStack(alignment: .leading, spacing: 11) {
                Text(substance.displayTitle)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
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

                LogNowButton(substanceName: substance.name)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 2)
            // A title block, not a card: clear the shared `CardBackground()` the
            // list applies to every other row (innermost wins) and pull the
            // insets in so the name sits on the screen's left margin.
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 6, trailing: 20))
        }
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
            .foregroundStyle(category.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(category.color.opacity(0.14), in: Capsule())
            .accessibilityLabel(Text(category.displayName))
    }
}
