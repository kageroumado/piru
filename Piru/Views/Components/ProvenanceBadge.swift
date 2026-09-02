import SwiftUI

/// A compact pill that conveys **where a pharmacology value came from** — fusing the *method/species*
/// (human vs animal vs in-vitro cell line vs an aggregator) with the *trust grade* (the color, from
/// ``ConfidenceTier``): a glance
/// distinguishes a human-PK number from a rat-synaptosome EC₅₀ or an aggregator transcription, which is
/// exactly the faithful-over-comprehensive distinction the evidence pipeline grades on.
///
/// Method is inferred from the binding's `species` string and `sourceSlug`:
/// - **Human** — a human-derived assay (incl. human transporters / HEK-expressed human receptors).
/// - **Rat / Mouse / Animal** — a named animal preparation (rat-synaptosome release, porcine cortex…).
/// - **In-vitro** — a cell line or recombinant prep with no animal species (HEK/CHO/cell/recombinant).
/// - **Curated** — the `piru-curated` layer: hand-authored against primary literature, but carrying an
///   affinity tier rather than a per-row assay/species, so no method claim can be made.
/// - **Aggregated** — any other source outside the graded `peer-review-primary` layer (a community /
///   wiki transcription); the trailing source slug in the row already names which. In the shipped DB
///   only `peer-review-primary` and `piru-curated` supply binding rows, so this arm is the guard for
///   sources that may gain bindings later — do not fold `piru-curated` into it: curated rows are the
///   app's own graded layer, not an aggregator transcription.
struct ProvenanceBadge: View {
    let confidence: ConfidenceTier
    let species: String?
    let sourceSlug: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: kind.icon)
                .imageScale(.small)
            Text(kind.label)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, Spacing.xxs)
        .background(color.opacity(Theme.Opacity.tint), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Evidence source: \(String(localized: kind.accessibleName)), \(String(localized: confidence.label))")
    }

    /// Color tracks the trust grade so an at-a-glance read combines method *and* how much to trust it —
    /// green → yellow → orange → gray.
    private var color: Color {
        switch confidence {
        case .high: .Confidence.High.text
        case .medium: .Confidence.Medium.text
        case .low: .Confidence.Low.text
        case .unverified: .Confidence.Unverified.text
        }
    }

    private enum Kind {
        case human
        case rat
        case mouse
        case animal
        case inVitro
        case curated
        case aggregated

        var label: LocalizedStringResource {
            switch self {
            case .human: "Human"
            case .rat: "Rat"
            case .mouse: "Mouse"
            case .animal: "Animal"
            case .inVitro: "In-vitro"
            case .curated: "Curated"
            case .aggregated: "Aggregated"
            }
        }

        var accessibleName: LocalizedStringResource {
            switch self {
            case .human: "human assay"
            case .rat: "rat assay"
            case .mouse: "mouse assay"
            case .animal: "animal assay"
            case .inVitro: "in-vitro assay"
            case .curated: "curated entry"
            case .aggregated: "aggregator source"
            }
        }

        var icon: String {
            switch self {
            case .human: "person.fill"
            case .rat, .mouse, .animal: "pawprint.fill"
            case .inVitro: "testtube.2"
            case .curated: "checkmark.seal"
            case .aggregated: "tray.full"
            }
        }
    }

    /// Classify the assay method from `species` + `sourceSlug`. Human-derived transporters (e.g.
    /// "human-HEK293") read as human; a named rodent/animal prep reads as such; an unspecified cell line
    /// reads in-vitro; the hand-curated layer reads curated; anything else outside the graded primary
    /// layer reads aggregated.
    private var kind: Kind {
        guard sourceSlug != "piru-curated" else { return .curated }
        guard sourceSlug == "peer-review-primary" else { return .aggregated }
        let s = (species ?? "").lowercased()
        if s.contains("human") { return .human }
        if s.contains("rat") { return .rat }
        if s.contains("mouse") || s.contains("mice") || s.contains("murine") { return .mouse }
        if s.contains("porcine") || s.contains("pig") || s.contains("bovine")
            || s.contains("guinea") || s.contains("monkey") || s.contains("animal") { return .animal }
        return .inVitro
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.md) {
        ProvenanceBadge(confidence: .high, species: "human", sourceSlug: "peer-review-primary")
        ProvenanceBadge(confidence: .medium, species: "rat brain synaptosomes", sourceSlug: "peer-review-primary")
        ProvenanceBadge(confidence: .high, species: "HEK293", sourceSlug: "peer-review-primary")
        ProvenanceBadge(confidence: .medium, species: nil, sourceSlug: "piru-curated")
        ProvenanceBadge(confidence: .low, species: nil, sourceSlug: "tripsit")
    }
    .padding()
}
