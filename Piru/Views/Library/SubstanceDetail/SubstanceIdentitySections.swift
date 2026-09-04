import SwiftUI

/// Name / aliases / route — demoted below dosing and collapsed by default; few
/// users need the chemical identity up front. Chemists who want the full
/// identity follow the PubChem link in the Chemistry disclosure below.
struct InfoDisclosureSection: View {
    let substance: Substance
    let model: SubstanceDetailModel

    @State private var infoExpanded = false
    @State private var aliasesExpanded = false

    var body: some View {
        // `tag`, not `info.circle`: a trailing `info.circle` on this screen is the
        // tap-for-help affordance (``CollapsibleSection/onInfo``), so a *leading*
        // one on a section that has no help sheet was the same glyph meaning two
        // things one row apart. This section is category, route, names and tags.
        CollapsibleSection("Additional Info", isExpanded: $infoExpanded) {
            let extras = infoExtraCells
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                GridRow {
                    GridCell("Category", String(localized: substance.category.displayName))
                    GridCell("Default route", String(localized: substance.defaultRoute.localizedName))
                }
                if !extras.isEmpty {
                    GridRow {
                        GridCell(extras[0].0, extras[0].1)
                        if extras.count > 1 { GridCell(extras[1].0, extras[1].1) } else { Color.clear }
                    }
                }
            }
            .padding(.vertical, Spacing.xs)

            if !substance.displayAliases.isEmpty {
                aliasChips
            }
            // One row per tags+footer — see the layout rationale on
            // `SourceAttributionRow` in SubstanceDetailSupport.swift.
            VStack(alignment: .leading, spacing: 0) {
                if !substance.tags.isEmpty {
                    SubstanceTagFlow(tags: substance.tags, accent: substance.category.color)
                        .padding(.top, Spacing.xs)
                }
                if let slug = model.provenance?.categorySource {
                    SourceAttributionRow(
                        slug: slug,
                        label: "Category",
                        deepLink: SubstanceSourceLinks.deepLink(slug, substance: substance),
                        substanceName: substance.name, field: .category,
                    )
                }
                if let slug = model.provenance?.halfLifeSource, substance.halfLifeMinutes != nil {
                    SourceAttributionRow(
                        slug: slug,
                        label: "Half-life",
                        deepLink: SubstanceSourceLinks.deepLink(slug, substance: substance),
                        substanceName: substance.name, field: .halfLife,
                    )
                }
            }
        }
    }

    /// Optional second-row identity cells — availability and (benzodiazepines
    /// only) the cross-benzo diazepam equivalent. Empty for most compounds.
    private var infoExtraCells: [(LocalizedStringResource, String)] {
        var cells: [(LocalizedStringResource, String)] = []
        if let reg = substance.regulatoryStatus {
            cells.append(("Availability", Self.regulatoryDisplay(reg)))
        }
        if substance.displayClass.showsDoseLadder, let dz = substance.diazepamEquivalent, let text = dz.displayText {
            cells.append(("Diazepam equivalent", text))
        }
        return cells
    }

    /// Aliases as a wrapping chip flow, collapsed to the first few with a
    /// "+N more" chip — a long comma list was a single over-tall row before.
    private var aliasChips: some View {
        let all = substance.displayAliases
        let limit = 5
        let shown = aliasesExpanded ? all : Array(all.prefix(limit))
        let hidden = all.count - shown.count
        return VStack(alignment: .leading, spacing: 7) {
            Text("Also known as")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
                .textCase(.uppercase)
            FlowLayout(spacing: Spacing.sm) {
                ForEach(shown, id: \.self) { alias in
                    aliasChip(Text(alias))
                        .textSelection(.enabled)
                }
                if hidden > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { aliasesExpanded = true }
                    } label: {
                        aliasChip(Text("+\(hidden) more"), accent: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private func aliasChip(_ text: Text, accent: Bool = false) -> some View {
        text
            .font(.caption.weight(.medium))
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.xs)
            .background(
                accent ? Theme.accent.opacity(Theme.Opacity.tint) : Color.platformTertiarySystemFill,
                in: Capsule(),
            )
            .foregroundStyle(accent ? Theme.accent : Theme.secondaryLabel)
    }

    /// Human-readable availability label from the parsed regulatory_status.
    private static func regulatoryDisplay(_ raw: String) -> String {
        switch raw {
        case "otc": return String(localized: "Over-the-counter")
        case "rx": return String(localized: "Prescription only")
        case "rx_otc_dependent": return String(localized: "OTC / Prescription")
        default:
            if raw.hasPrefix("controlled_schedule_"), let n = raw.split(separator: "_").last {
                return String(localized: "Schedule \(String(n)) (controlled)")
            }
            return raw
        }
    }
}

/// Chemical identity (formula / molar mass / CAS / InChIKey) folded into a
/// collapsed disclosure below the identity Info card. Every value is selectable
/// and carries a Copy action — an InChIKey you can't copy is useless.
struct ChemistrySection: View {
    let substance: Substance
    let showsMechanism: Bool

    @State private var chemistryExpanded: Bool
    @State private var moleculeStructure: MoleculeStructure?
    @Environment(\.openURL) private var openURL

    /// `initiallyExpanded` seeds the disclosure open — the deep-data page passes
    /// `true` so a "Show all / Chemistry" tap lands on the numbers, not on a
    /// second collapsed row the user has to open again (the double-collapse void).
    init(substance: Substance, showsMechanism: Bool, initiallyExpanded: Bool = false) {
        self.substance = substance
        self.showsMechanism = showsMechanism
        _chemistryExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        // Gate on data we actually hold. `pubChemURL` cannot be part of this test:
        // it falls back to a name-search URL, so it is non-nil for every substance
        // in the library and would make this card render for all of them — as an
        // empty grid whenever nothing else resolved.
        let hasPubChem = substance.pubchemCID != nil
        let phys = substance.physicochemical
        let hasChem = substance.formula != nil || substance.cas != nil || substance.inchikey != nil
            || substance.molarMass != nil || hasPubChem || substance.smiles != nil
            || substance.iupacName != nil || (phys?.hasAnyValue ?? false)
        if showsMechanism, hasChem {
            CollapsibleSection("Chemistry", isExpanded: $chemistryExpanded) {
                // The molecule hero — omitted entirely when the substance has
                // no generated structure (no SMILES, or obabel couldn't parse
                // it; ~860 substances currently). Loaded lazily via a cheap
                // local SQLite lookup, not baked into `Substance` itself.
                if let moleculeStructure {
                    // The view fits its own aspect ratio, so wide molecules stay
                    // short instead of floating in whitespace; cap the height so a
                    // tall/near-square one doesn't dominate the card.
                    MoleculeStructureView(structure: moleculeStructure, formula: substance.formula)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 150)
                        .padding(.bottom, Spacing.xs)
                }
                let showMW = substance.molarMass != nil && !substance.usesPeptidePresentation
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                    if substance.formula != nil || showMW {
                        GridRow {
                            if let f = substance.formula { GridCell("Formula", f) } else { Color.clear }
                            if showMW, let mw = substance.molarMass {
                                GridCell("Molar mass", "\(mw.doseFormatted) g/mol")
                            } else { Color.clear }
                        }
                    }
                    physicochemicalRows(phys)
                    if let iupac = substance.iupacName {
                        GridRow { GridCell("IUPAC name", iupac).gridCellColumns(2) }
                    }
                    if let smiles = substance.smiles {
                        GridRow { GridCell("SMILES", smiles, mono: true).gridCellColumns(2) }
                    }
                    if let k = substance.inchikey {
                        GridRow { GridCell("InChIKey", k, mono: true).gridCellColumns(2) }
                    }
                    if substance.cas != nil || hasPubChem {
                        GridRow {
                            if let c = substance.cas { GridCell("CAS", c, mono: true) } else { Color.clear }
                            if let cid = substance.pubchemCID, let url = substance.pubChemURL {
                                pubChemCell(cid: cid, url: url)
                            } else { Color.clear }
                        }
                    }
                }
                .padding(.vertical, Spacing.xs)
                if let phys, phys.hasAnyValue {
                    // States where the numbers come from rather than warning the
                    // reader off them. They are computed from the structure, which
                    // is the best available data for most of these compounds — the
                    // old "not measured for this preparation" line implied a defect
                    // that isn't there, and "this preparation" named nothing the
                    // reader could identify.
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Computed from the molecular structure (PubChem, NPS-DataHub) rather than measured in a lab.")
                        if phys.hasLD50 {
                            Text("LD50 is rodent toxicity (order of magnitude) — not a human safe dose.")
                        }
                    }
                    .captionSecondary()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.xxs)
                }
            }
            .task(id: substance.name) {
                moleculeStructure = substance.smiles != nil
                    ? SubstanceStore.shared.moleculeStructure(forSubstanceName: substance.name)
                    : nil
            }
        }
    }

    /// The Stage-1 physicochemical descriptors, laid into the Chemistry grid as
    /// two-column rows. The `if let` guards keep them future-proof — a populated
    /// column just appears.
    @ViewBuilder
    private func physicochemicalRows(_ phys: Physicochemical?) -> some View {
        if let phys {
            if phys.logP != nil || phys.tpsa != nil {
                GridRow {
                    if let v = phys.logP { GridCell("LogP", chem(v)) } else { Color.clear }
                    if let v = phys.tpsa { GridCell("TPSA", "\(chem(v)) Å²") } else { Color.clear }
                }
            }
            if phys.hba != nil || phys.hbd != nil {
                GridRow {
                    if let v = phys.hba { GridCell("H-bond acceptors", "\(v)") } else { Color.clear }
                    if let v = phys.hbd { GridCell("H-bond donors", "\(v)") } else { Color.clear }
                }
            }
            if phys.meltingPointC != nil || phys.boilingPointC != nil {
                GridRow {
                    if let v = phys.meltingPointC { GridCell("Melting point", "\(chem(v)) °C") } else { Color.clear }
                    if let v = phys.boilingPointC { GridCell("Boiling point", "\(chem(v)) °C") } else { Color.clear }
                }
            }
            if phys.ld50OralMgPerKg != nil || phys.ld50DermalMgPerKg != nil {
                GridRow {
                    if let v = phys.ld50OralMgPerKg { GridCell("LD50 (oral, rodent)", "\(chem(v)) mg/kg") } else { Color.clear }
                    if let v = phys.ld50DermalMgPerKg { GridCell("LD50 (dermal, rodent)", "\(chem(v)) mg/kg") } else { Color.clear }
                }
            }
        }
    }

    private func chem(_ value: Double) -> String {
        SubstanceDetailView.chemNumber(value)
    }

    /// PubChem cell — a tappable link out to the curated chemistry record. Lives
    /// in Chemistry (not Info): it's a chemical identifier, same as the rest.
    ///
    /// A borderless `Button` (not a `Link`): a lone `Link` in a Form/List row gets
    /// promoted to a full-row tap target, so the *whole* Chemistry card opened
    /// PubChem. Borderless keeps the hit area to this one cell.
    private func pubChemCell(cid: Int, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("PubChem CID")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
                    .textCase(.uppercase)
                HStack(spacing: 3) {
                    Text(verbatim: "\(cid)").font(.subheadline)
                    Image(systemName: "arrow.up.right").font(.caption2)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Theme.accent)
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderless)
    }
}

/// Unified provenance, as an **accountability ledger rather than a link dump**:
/// the databases that contributed this compound's data (deep-linked to their page
/// for it) and the primary literature, each paired with *what it supplied here* —
/// dose, duration, effects, pharmacology. A raw list of eight site names told the
/// reader nothing about which one is behind the number they were just looking at.
///
/// The pairing is read from the bundled DB's per-row `source_id` / `citation_id`
/// columns (``SubstanceStore/sourceContributions(forSubstanceName:)``), not from
/// a hand-written table — what a source supplies differs per substance.
struct SourcesSection: View {
    let substance: Substance
    let showsSources: Bool
    /// Which source supplied which field. Owned by ``SubstanceDetailModel`` —
    /// a `.task` of this section's own would sit inside a collapsed disclosure
    /// and not run until the reader opened it.
    let contributions: SubstanceStore.SourceContributions

    @State private var isExpanded: Bool

    /// `initiallyExpanded` seeds the disclosure open — the deep-data page passes
    /// `true` so a "Sources" tap lands on the ledger rather than on a second
    /// collapsed row, the same double-collapse void ``ChemistrySection`` avoids.
    init(
        substance: Substance,
        showsSources: Bool,
        contributions: SubstanceStore.SourceContributions,
        initiallyExpanded: Bool = false,
    ) {
        self.substance = substance
        self.showsSources = showsSources
        self.contributions = contributions
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        let links = SubstanceSourceLinks.mergedLinks(for: substance, contributions: contributions)
        if showsSources, !links.isEmpty {
            // Folded, like every other reference card on the page. `DisclosurePolicy`
            // has said so since it was written (`sourcesDefaultExpanded` is `false`
            // at every tier, and the placement matrix says `.inlineCollapsed`) —
            // this section was simply the one that never honored it, and the ledger
            // is one row per source, which made it the longest block on the screen
            // for the reader least likely to want it.
            CollapsibleSection(
                "Sources",
                count: links.count,
                isExpanded: $isExpanded,
            ) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    ForEach(links) { link in
                        if let url = link.url {
                            Link(destination: url) {
                                SourceLedgerRow(link: link, linked: true)
                            }
                            .buttonStyle(.plain)
                        } else {
                            SourceLedgerRow(link: link, linked: false)
                        }
                    }
                    Text("Each row lists what that source supplied here. Links open the source's own page — always verify against the original.")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Spacing.xs)
            }
        }
    }
}

/// One ledger row: **who** on the left, **what they supplied** on the right.
///
/// Two columns, and therefore two ways to break — an accessibility text size, or
/// a source whose facet list is long. Both are handled by *reflowing to a stack*
/// rather than truncating: an attribution that has been clipped to "dose · dur…"
/// is worse than one that took two lines, and for CC BY-SA content it is also a
/// licensing question, not only a legibility one.
private struct SourceLedgerRow: View {
    let link: DetailSourceLink
    let linked: Bool

    /// " · "-joined rather than `Text` concatenation: `Text + Text` is deprecated
    /// in iOS 26, and each facet is independently localized.
    private var providesSummary: String {
        link.provides.map { String(localized: $0.label) }.joined(separator: " · ")
    }

    var body: some View {
        // One column, two lines: the source, then what it supplied beneath it.
        // Keep it this way. Side-by-side columns have to divide a phone's width
        // between a name that can be a six-line paper title and a facet list
        // that can run to six terms, and whichever side loses the split wraps
        // into a ragged stack of one-word lines. Stacked, each gets the full
        // width and the facets read as a caption belonging to the name above.
        Group {
            if link.provides.isEmpty {
                nameColumn
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    nameColumn
                    providesText
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var nameColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            // `.firstTextBaseline`, not the default center: a citation title wraps
            // to five or six lines and a centered glyph then floats in the middle
            // of the block, reading as a bullet rather than a link marker.
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(link.label)
                    .font(.subheadline)
                    .foregroundStyle(linked ? Color.primary : Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                if linked {
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                }
            }
            if let license = link.license {
                // Verbatim: a license identifier is a proper noun and must not be
                // translated or reflowed into another form.
                Text(verbatim: license)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }

    private var providesText: some View {
        Text(providesSummary)
            .captionSecondary()
            .fixedSize(horizontal: false, vertical: true)
    }

    private var accessibilityLabel: Text {
        var parts = [link.label]
        if !link.provides.isEmpty {
            parts.append(String(localized: "supplies \(providesSummary)"))
        }
        if let license = link.license {
            parts.append(String(localized: "licensed \(license)"))
        }
        return Text(parts.joined(separator: ", "))
    }
}
