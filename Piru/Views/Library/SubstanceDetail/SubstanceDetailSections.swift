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

    var body: some View {
        if !substance.indications.isEmpty {
            Section("Medical Uses") {
                ForEach(substance.indications, id: \.self) { ind in
                    clinicalRow(ind)
                }
            }
        }
        let boxed = substance.contraindications.filter(\.isBoxedWarning)
        let cautions = substance.contraindications.filter { !$0.isBoxedWarning }
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
                // Dial-first: the interactive spectrum is the section body.
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
