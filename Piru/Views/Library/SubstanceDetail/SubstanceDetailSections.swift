import SwiftUI

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
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(effect.name)
                                    .font(.subheadline)
                                if !effect.description.isEmpty {
                                    Text(effect.description)
                                        .captionSecondary()
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .padding(.vertical, Spacing.xxs)
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
                    HStack(spacing: Spacing.xxs) {
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
