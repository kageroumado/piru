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

    private var displayClass: CompoundDisplayClass {
        substance.displayClass
    }

    var body: some View {
        let curated = policy.showsRichSubjective ? substance.subjectiveEffects : []
        let hasAllEffects = !substance.effects.isEmpty
        // Only the first few curated effects read as the "main effects" summary;
        // a long list (e.g. MPH) belongs behind "Show All", not dumped inline.
        let mainEffects = Array(curated.prefix(mainEffectsLimit))
        // Offer "Show All" when there are more curated effects than we show, or
        // when the full taxonomy adds rows beyond the curated set (not Melatonin,
        // where it would reveal *fewer*).
        let showsMoreEffects = curated.count > mainEffects.count || substance.effects.count > curated.count
        if displayClass != .nonRecreational, !curated.isEmpty || hasAllEffects {
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
                HStack {
                    Text("Effects")
                    Spacer()
                    // Health-style "Show All" → the full PsychonautWiki taxonomy
                    // (and Erowid reports), grouped by category, one tap away.
                    // A header NavigationLink isn't reliably hittable, so drive a
                    // navigationDestination from a Button instead.
                    if !mainEffects.isEmpty, showsMoreEffects {
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
        }
    }
}
