import SwiftUI

/// The unified **Pharmacology** card — one progressive surface that merges what used to be the
/// separate *Mechanism of Action* and *Monoamine Profile* cards (the redesign's "A container").
/// Order: a one-line headline, the prose description, a class hero (the dopamine↔serotonin slider for
/// monoamine drugs), the target/strength grid, and any harm-reduction flag. Receptor evidence,
/// pharmacokinetics, and metabolism stay in their own sections.
///
/// Step 2 of the hybrid redesign handles the monoamine slider hero; the opioid/benzo/dissociative
/// receptor-panel heroes arrive in step 3 (see `Specs/pharmacology-card-hybrid.md`).
struct PharmacologyCard: View {
    let moa: MechanismOfAction
    let monoamine: MonoamineProfile?
    let category: SubstanceCategory
    /// Class-specific receptor-panel hero (opioid/benzo/dissociative). When present it replaces the
    /// monoamine slider + target grid, and the separate Receptor Literature section is suppressed.
    var hero: PharmacologyHero?

    private var accent: Color {
        category.color
    }
    private var serotoninColor: Color {
        SubstanceCategory.empathogen.color
    }
    private var dopamineColor: Color {
        SubstanceCategory.stimulant.color
    }

    /// The summary is a short *title* ("Monoamine-Releasing Stimulant") — colour it as a headline.
    /// Some substances carry a multi-sentence essay in the summary field; render that as calm body
    /// text, not a scary category-coloured wall.
    private var summaryIsHeadline: Bool {
        !moa.summary.isEmpty && moa.summary.count <= 90 && !moa.summary.contains(". ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !moa.summary.isEmpty {
                Text(moa.summary)
                    .font(summaryIsHeadline ? .subheadline.weight(.semibold) : .subheadline)
                    .foregroundStyle(summaryIsHeadline ? accent : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !moa.description.isEmpty {
                Text(moa.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let hero {
                heroSection(hero)
            } else {
                if let monoamine { monoamineHero(monoamine) }
                if !moa.bindings.isEmpty {
                    targetGrid
                } else if !moa.primaryTargets.isEmpty {
                    HStack(spacing: 0) {
                        Text("Primary Targets: ").font(.caption.weight(.medium))
                        Text(moa.primaryTargets.joined(separator: " · ")).font(.caption)
                    }
                    .foregroundStyle(Theme.secondaryLabel)
                }
                if let monoamine { flags(monoamine) }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Class-specific receptor-panel hero (opioid / benzo / dissociative)

    private func heroSection(_ hero: PharmacologyHero) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let character = hero.character {
                Text(character)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(accent.opacity(0.14)))
            }
            switch hero.kind {
            case .opioid, .benzo: ReceptorPanel(rows: hero.rows, accent: accent)
            case .dissociative: PotencyBars(bars: hero.bars, accent: accent)
            }
            if let note = hero.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let minor = hero.minor {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Minor / off-targets")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryLabel)
                    Text(minor).font(.caption).foregroundStyle(Theme.secondaryLabel)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.secondaryLabel.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Target / strength grid (the "model" layer)

    private var targetGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Text("Target")
                Text("Action")
                Text(verbatim: "")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.secondaryLabel)

            ForEach(moa.bindings) { binding in
                GridRow {
                    Text(binding.target).fontWeight(.medium)
                    Text(binding.action.displayName).foregroundStyle(.secondary)
                    AffinityDots(filled: binding.affinity.rawValue, tint: accent)
                }
            }
        }
        .font(.caption)
    }

    // MARK: - Monoamine slider hero

    private func monoamineHero(_ profile: MonoamineProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(profile.mechanismLabel)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Theme.secondaryLabel.opacity(0.12)))
                .overlay(Capsule().strokeBorder(Theme.secondaryLabel.opacity(0.18), lineWidth: 0.5))

            if profile.leanPosition != nil {
                spectrum(profile)
            }
        }
        .padding(.top, 2)
    }

    private func spectrum(_ profile: MonoamineProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [serotoninColor, dopamineColor], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 8)
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .offset(x: geo.size.width * (profile.leanPosition ?? 0.5) - 8)
                }
                .frame(height: 16)
            }
            .frame(height: 16)

            HStack {
                Text("Serotonin").font(.caption2.weight(.medium)).foregroundStyle(serotoninColor)
                Spacer()
                Text("Dopamine").font(.caption2.weight(.medium)).foregroundStyle(dopamineColor)
            }

            // Two lines: the lean label, then the ratio beneath it — keeps a long label from colliding
            // with the ratio on one row.
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.leanLabel).font(.caption.weight(.semibold))
                if let r = profile.datSertRatio {
                    Text("DAT:SERT \(ratioText(r))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
    }

    @ViewBuilder
    private func flags(_ profile: MonoamineProfile) -> some View {
        if profile.engages5HT2B {
            flag(
                icon: "heart.text.square",
                tint: .orange,
                text: "Activates 5-HT2B, which is linked to heart-valve damage (valvulopathy) with chronic or heavy use.",
            )
        }
        if profile.misSoldAsMDMA {
            flag(
                icon: "exclamationmark.triangle.fill",
                tint: .red,
                text: "Often mis-sold as MDMA / \u{201C}molly,\u{201D} but it is pharmacologically a reuptake blocker — longer, more stimulant and anxiogenic, and more dangerous on an empathogen-style redose.",
            )
        }
    }

    private func flag(icon: String, tint: Color, text: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundStyle(tint)
            Text(text).font(.caption).foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    /// A DAT:SERT ratio reads meaningfully only within a band; past ~100:1 the lean label carries the
    /// signal and a raw "21797" is noise.
    private func ratioText(_ r: Double) -> String {
        if r >= 100 { return ">100" }
        if r >= 10 { return String(format: "%.0f", r) }
        if r >= 1 { return String(format: "%.1f", r) }
        if r >= 0.01 { return String(format: "%.2f", r) }
        return "<0.01"
    }
}
