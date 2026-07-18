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
                    clinicalRow(ind, icon: "stethoscope", tint: Theme.accent)
                }
            }
        }
        let boxed = substance.contraindications.filter(\.isBoxedWarning)
        let cautions = substance.contraindications.filter { !$0.isBoxedWarning }
        if !boxed.isEmpty {
            Section("Boxed Warning") {
                ForEach(boxed, id: \.text) { c in
                    clinicalRow(c.text, icon: "exclamationmark.octagon.fill", tint: .red, lineLimit: nil)
                }
            }
        }
        if !cautions.isEmpty {
            // Verbose DailyMed contraindication prose — collapsed by default,
            // each row clamped to a few lines, and capped to keep the screen
            // from turning into a drug monograph. Full text lives at the source.
            CollapsibleSection(
                "Contraindications & Cautions",
                systemImage: "exclamationmark.triangle",
                count: cautions.count,
                isExpanded: $cautionsExpanded,
            ) {
                ForEach(cautions.prefix(cautionDisplayLimit), id: \.text) { c in
                    clinicalRow(c.text, icon: "exclamationmark.triangle", tint: .orange, lineLimit: 4)
                }
                if cautions.count > cautionDisplayLimit {
                    Text("+\(cautions.count - cautionDisplayLimit) more")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
    }

    /// One clinical list row — a readable leading symbol (the old style forced a
    /// 5pt icon that vanished) plus wrapping text clamped to `lineLimit`.
    private func clinicalRow(_ text: String, icon: String, tint: Color, lineLimit: Int? = 2) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
        }
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
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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
