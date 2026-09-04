import SwiftUI

/// The class-signature slot inside the Pharmacology card: one of three renderings, chosen by
/// ``ClassSignature``. A thin dispatcher — each rendering is its own `View` with narrow inputs, so a
/// basis switch in the ternary doesn't invalidate the rest of the card.
struct ClassSignatureView: View {
    let signature: ClassSignature
    let accent: Color

    var body: some View {
        switch signature {
        case let .efficacy(model): EfficacyAxisView(model: model, accent: accent)
        case let .balance(model): TargetBalanceView(model: model, accent: accent)
        case let .ternary(model): TransporterTernaryView(model: model, accent: accent)
        }
    }
}

/// The axis line: what was measured, in what species, and whether the compounds on it were measured
/// together — printed under **every** signature, because "prints its basis" is the acceptance
/// criterion these renderings are held to.
///
/// The gate is a gate, not a badge: when a rendering ranks across studies and could not be gated,
/// this says so in words rather than shading a confidence dot.
struct SignatureCaption: View {
    let provenance: SignatureProvenance
    /// False when the rendering ranks values that were never measured together.
    let isGated: Bool
    /// Extra leading clause the rendering wants first (the ternary's potency shares).
    var leading: String?
    /// Overrides the generic basis wording when the rendering knows something sharper — a releaser's
    /// EC₅₀ is a *release* EC₅₀, and that distinction is the whole reason the ternary has a switch.
    var basisLabel: String?
    /// False when the rendering places the citation itself (the ternary pins it to a plot corner
    /// rather than spending a caption line on it).
    var showsCitationLink = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                // A broken or free-text citation renders as plain text, never a dead link.
                if showsCitationLink, let url = provenance.citationURL {
                    CitationLink(url: url, size: 9)
                }
            }
            if !isGated {
                Label {
                    Text(
                        "These values were not measured together — each is its own study. Ranked here for scale.",
                    )
                } icon: {
                    Image(systemName: "circle.dashed")
                        .accessibilityHidden(true)
                }
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var caption: String {
        var parts: [String] = []
        if let leading { parts.append(leading) }
        parts.append(basisClause)
        if let species = provenance.species, !species.isEmpty, species != "—" {
            parts.append(species.prefix(1).uppercased() + species.dropFirst())
        } else if provenance.species == nil {
            parts.append(String(localized: "mixed species", comment: "Signature axis basis clause"))
        }
        parts.append(gateClause)
        // No publication year. It sets no expectation the reader can act on — what
        // matters is the basis, the species, and whether one experiment produced all
        // the values, and the citation itself carries the date for anyone who opens it.
        return parts.joined(separator: " · ")
    }

    /// "efficacy τ vs DAMGO" / "release EC₅₀" — the measurement, and the yardstick it is expressed
    /// against when there is one.
    private var basisClause: String {
        let basis = basisLabel ?? String(localized: provenance.basis.axisLabel)
        guard let reference = provenance.referenceAgonist, !reference.isEmpty else { return basis }
        return String(localized: "\(basis) vs \(reference)", comment: "Signature basis with reference agonist")
    }

    private var gateClause: String {
        guard isGated else {
            return String(localized: "across studies", comment: "Signature gate clause — ungated")
        }
        if provenance.isDeclaredPanel {
            return String(localized: "one panel", comment: "Signature gate clause — declared comparable set")
        }
        return String(localized: "one study", comment: "Signature gate clause — shared citation")
    }
}
