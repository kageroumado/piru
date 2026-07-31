import SwiftUI

/// Clinical section — indications + contraindications + boxed warnings. Renders
/// only when the compound carries that data (medical/OTC compounds from
/// pyrls/medtap). Factored out of `SubstanceDetailView` as its own invalidation
/// boundary: it re-renders only when the substance or the cautions disclosure
/// changes, not on every unrelated state change in the detail screen.
struct MedicalInfoSection: View {
    let substance: Substance
    @Binding var cautionsExpanded: Bool

    /// How many cautions to list before falling back to a "+N more" row.
    private let cautionDisplayLimit = 6

    /// Whether the label material *leads* the screen or is folded away.
    ///
    /// On the medical spine it is the point of the page — someone opening
    /// sertraline wants the indications. On the recreational spine it is
    /// secondary: a bare "Medical Uses" card sitting between the dose dial and
    /// the pharmacology says "this drug also treats ADHD" to a reader who came
    /// to find out what 30 mg does, and it broke the card rhythm to say it (two
    /// title-only sections wrapping one line of text each).
    private var labelLeads: Bool {
        switch substance.displayClass {
        case .medicalRx, .otc, .nonRecreational: true
        default: false
        }
    }

    /// Prescribing state, folded into one card. Kept `@State` rather than
    /// threaded from the parent: it's a reading affordance, not screen state.
    @State private var prescribingExpanded = false

    var body: some View {
        let boxed = substance.contraindications.filter(\.isBoxedWarning)
        let cautions = substance.contraindications.filter { !$0.isBoxedWarning }

        if labelLeads {
            leadingLabel(boxed: boxed, cautions: cautions)
        } else if !substance.indications.isEmpty || !boxed.isEmpty {
            // One folded card instead of two title-only sections. Boxed warnings
            // still surface in the collapsed header's count, so nothing safety-
            // bearing is hidden behind a fold with no sign it exists.
            CollapsibleSection(
                "Prescribing",
                systemImage: "cross.case",
                count: substance.indications.count + boxed.count,
                isExpanded: $prescribingExpanded,
            ) {
                if !substance.indications.isEmpty {
                    clinicalGroupTitle("Approved uses")
                    ForEach(substance.indications, id: \.self) { clinicalRow($0) }
                }
                if !boxed.isEmpty {
                    clinicalGroupTitle("Boxed warning")
                    ForEach(boxed, id: \.text) { clinicalRow($0.text) }
                }
            }
            cautionsSection(cautions)
        } else {
            cautionsSection(cautions)
        }
    }

    /// The medical spine's layout — indications and boxed warnings inline, as
    /// their own sections, because they are what the reader came for.
    @ViewBuilder
    private func leadingLabel(boxed: [Contraindication], cautions: [Contraindication]) -> some View {
        if !substance.indications.isEmpty {
            Section("Medical Uses") {
                ForEach(substance.indications, id: \.self) { ind in
                    clinicalRow(ind)
                }
            }
        }
        if !boxed.isEmpty {
            // Plain rows. A red octagon per row restated what the section title
            // already says, and a saturated system red reads far heavier here
            // than it does as a glyph on a control — especially on macOS, where
            // the same symbol renders larger against a lighter window chrome.
            Section("Boxed Warning") {
                ForEach(boxed, id: \.text) { c in
                    clinicalRow(c.text)
                }
            }
        }
        cautionsSection(cautions)
    }

    /// Contraindications keep their own collapsible on both spines: they are the
    /// one part of the label that is a safety fact rather than a clinical one.
    @ViewBuilder
    private func cautionsSection(_ cautions: [Contraindication]) -> some View {
        if !cautions.isEmpty {
            // Verbose DailyMed contraindication prose, capped at
            // `cautionDisplayLimit` rows and collapsed by default. Rows are *not*
            // line-clamped: this is a disclosure someone opened on purpose, and a
            // contraindication cut mid-clause ("risk of hypertensive cri…") is
            // worse than a long one. The fold and the row cap already keep the
            // screen from turning into a drug monograph.
            CollapsibleSection(
                "Contraindications & Cautions",
                systemImage: "exclamationmark.triangle",
                count: cautions.count,
                isExpanded: $cautionsExpanded,
            ) {
                // No per-row triangle: the section header carries one, and
                // repeating it down the list marks every row as exceptional
                // when they're all the same kind of thing.
                ForEach(cautions.prefix(cautionDisplayLimit), id: \.text) { c in
                    clinicalRow(c.text)
                }
                if cautions.count > cautionDisplayLimit {
                    Text("+\(cautions.count - cautionDisplayLimit) more")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
    }

    /// The group label inside the folded Prescribing card — the two kinds of
    /// label text still have to be told apart once they share a card.
    private func clinicalGroupTitle(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(Theme.secondaryLabel)
    }

    /// One clinical list row: wrapping text, in full.
    ///
    /// These used to carry a leading symbol — a stethoscope, a red octagon, an
    /// orange triangle — repeated on every row of their section. A symbol that
    /// appears on all of a list's rows says nothing about any one of them; it
    /// just restates the section heading once per row, and the two warning
    /// glyphs additionally read as severity that isn't being claimed. The
    /// heading carries the meaning, so the rows carry the text.
    private func clinicalRow(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Effects — curated subjective effects read as a short summary; the full
/// PsychonautWiki taxonomy lives one tap away on `AllEffectsView`. Its own
/// invalidation boundary keyed on the substance, the disclosure policy, and the
/// "show all" navigation flag.
struct EffectsSection: View {
    let substance: Substance
    let policy: DisclosurePolicy
    @Binding var showAllEffects: Bool

    /// How many curated effects show inline before the rest move to "Show All".
    private let mainEffectsLimit = 6

    /// The drug.community intensity spectrum, loaded lazily. When present it
    /// replaces the flat effect list with the interactive dose-intensity dial —
    /// the engaging surface belongs on the main screen, not hidden behind
    /// "Show All". "Show All" then opens the full effect list.
    @State private var bands: [SpectrumBand] = []
    @State private var bandDoseText: [Int: String] = [:]
    @State private var doseRouteName: String?
    @State private var dcDeepLink: URL?

    private var displayClass: CompoundDisplayClass {
        substance.displayClass
    }

    var body: some View {
        content
            .task(id: substance.name) { loadSpectrum() }
    }

    @ViewBuilder
    private var content: some View {
        let curated = policy.showsRichSubjective ? substance.subjectiveEffects : []
        let hasAllEffects = !substance.effects.isEmpty
        let mainEffects = Array(curated.prefix(mainEffectsLimit))
        let showsMoreEffects = curated.count > mainEffects.count || substance.effects.count > curated.count

        if displayClass != .nonRecreational {
            if !bands.isEmpty {
                // Dial-first: the interactive spectrum is the section body. It
                // was briefly merged into the dose card; that left this section
                // holding a bare source row and stranded the per-band "most
                // reported at this dose" frequencies, which have nowhere else to
                // go. The dose card keeps the grid; the dial keeps the effects.
                Section {
                    DoseIntensityCard(
                        bands: bands,
                        bandDoseText: bandDoseText,
                        citationSlug: "drug.community",
                        citationDeepLink: dcDeepLink,
                        routeName: doseRouteName,
                    )
                } header: {
                    effectsHeader(showsShowAll: hasAllEffects)
                }
            } else if !curated.isEmpty || hasAllEffects {
                // Fallback (no dc coverage): the prior flat curated list.
                Section {
                    if !mainEffects.isEmpty {
                        ForEach(mainEffects, id: \.name) { effect in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(effect.name)
                                    .font(.subheadline)
                                if !effect.description.isEmpty {
                                    Text(effect.description)
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryLabel)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .padding(.vertical, 2)
                        }
                    } else if hasAllEffects {
                        Button { showAllEffects = true } label: {
                            Label("All effects (\(substance.effects.count))", systemImage: "list.bullet.rectangle")
                                .font(.subheadline)
                        }
                    }
                } header: {
                    effectsHeader(showsShowAll: !mainEffects.isEmpty && showsMoreEffects)
                }
            }
        }
    }

    private func effectsHeader(showsShowAll: Bool) -> some View {
        HStack {
            Text("Effects")
            Spacer()
            // A header NavigationLink isn't reliably hittable, so drive a
            // navigationDestination from a Button instead.
            if showsShowAll {
                Button { showAllEffects = true } label: {
                    HStack(spacing: 2) {
                        Text("Show All")
                        Image(systemName: "chevron.right").font(.caption2)
                            .accessibilityHidden(true)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)
                    .textCase(nil)
                }
            }
        }
    }

    private func loadSpectrum() {
        let loaded = SubstanceStore.shared.spectrumBands(forSubstanceName: substance.name)
        guard !loaded.isEmpty else { return }
        bands = loaded
        if let route = substance.routes.first(where: { $0.route == substance.defaultRoute })
            ?? substance.routes.first {
            bandDoseText = EffectsIntensityModel.bandDoseText(from: route.doses, unit: route.unit)
            doseRouteName = route.route.displayName
        }
        dcDeepLink = SubstanceSourceLinks.deepLink("drug.community", substance: substance)
    }
}
