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
    /// The gated class signature (efficacy axis / 5-HT balance / transporter ternary, or the stated
    /// absence). Independent of the hero: the hero is *this* compound's receptor panel, the signature
    /// is where it sits among the compounds it can legitimately be compared with.
    var signature: ClassSignature?
    var onMonoamineInfo: (() -> Void)?

    private var accent: Color {
        category.color
    }

    /// An absence is an explanation, so it reads as a footnote below the panel. Every drawn signature
    /// is the card's headline claim and leads.
    private var signatureLeads: Bool {
        guard let signature else { return false }
        if case .absent = signature { return false }
        return true
    }

    /// The efficacy axis states the agonist class itself ("Partial μ-opioid agonist"), so the hero's
    /// own character chip would say it twice.
    private var signatureSuppliesCharacter: Bool {
        guard case let .efficacy(model)? = signature else { return false }
        return model.headline != nil
    }

    @ViewBuilder private var signatureView: some View {
        if let signature {
            ClassSignatureView(signature: signature, accent: accent)
        }
    }

    /// The summary is a short *title* ("Monoamine-Releasing Stimulant") — color it as a headline.
    /// Some substances carry a multi-sentence essay in the summary field; render that as calm body
    /// text, not a scary category-colored wall.
    private var summaryIsHeadline: Bool {
        !moa.summary.isEmpty && moa.summary.count <= 90 && !moa.summary.contains(". ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let hero {
                // Class-panel path (opioid/benzo/dissociative): headline, prose, signature, hero.
                summaryText
                descriptionText
                if signatureLeads { signatureView }
                heroSection(hero)
                if !signatureLeads { signatureView }
            } else if let monoamine {
                // Monoamine path — the class name, then the triangle, then the S↔D
                // bar. The headline is what the whole card is an argument for, so it
                // leads. Do not move the bar above the triangle: the bar is the same
                // fact collapsed onto one axis, and a summary of a picture must not
                // precede the picture.
                summaryText
                signatureView
                monoamineHero(monoamine)
                receptorTargets
                descriptionText
                flags(monoamine)
            } else {
                // No monoamine profile, no class hero: headline, prose, signature, targets.
                summaryText
                descriptionText
                signatureView
                receptorTargets
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var summaryText: some View {
        if !moa.summary.isEmpty {
            Text(moa.summary)
                .font(summaryIsHeadline ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(summaryIsHeadline ? accent : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var descriptionText: some View {
        if !moa.description.isEmpty {
            Text(moa.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The receptor targets — full-width pills (replacing the old left-clustered
    /// ``AffinityDots`` grid that wasted ~55% of the row), or the plain
    /// primary-targets line when there are no graded bindings.
    @ViewBuilder private var receptorTargets: some View {
        if !moa.bindings.isEmpty {
            receptorPills
        } else if !moa.primaryTargets.isEmpty {
            HStack(spacing: 0) {
                Text("Primary Targets: ").font(.caption.weight(.medium))
                Text(moa.primaryTargets.joined(separator: " · ")).font(.caption)
            }
            .foregroundStyle(Theme.secondaryLabel)
        }
    }

    // MARK: - Class-specific receptor-panel hero (opioid / benzo / dissociative)

    private func heroSection(_ hero: PharmacologyHero) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let character = hero.character, !signatureSuppliesCharacter {
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
                        .accessibilityAddTraits(.isHeader)
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

    // MARK: - Receptor target pills (full-width)

    /// Each target as a full-width pill — target · action on the left, the graded
    /// ``StrengthMeter`` pinned right (the same segmented glyph the share card
    /// uses) — so the row uses the whole screen instead of clustering the meter at
    /// ~45% and leaving dead space. "Acts on" leads the group.
    private var receptorPills: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Acts on")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.4)
                .foregroundStyle(Theme.secondaryLabel)
                .accessibilityAddTraits(.isHeader)

            ForEach(moa.bindings) { binding in
                HStack(spacing: 10) {
                    Text(binding.target)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(binding.action.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    StrengthMeter(filled: binding.affinity.rawValue, tint: accent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Monoamine slider hero

    private func monoamineHero(_ profile: MonoamineProfile) -> some View {
        // No mechanism-label pill here. The ratio line below says
        // `DAT : SERT release ≈ 30 : 1`, the signature caption says
        // `release EC₅₀`, and every ACTS ON row says "Releasing Agent" — a pill
        // would be a fourth statement of the same word with the most visual
        // weight of the four.
        VStack(alignment: .leading, spacing: 10) {
            if profile.leanPosition != nil {
                spectrum(profile)
            }
        }
    }

    private func spectrum(_ profile: MonoamineProfile) -> some View {
        // The bar already encodes the lean and the ratio line quantifies it, so the
        // restated "Serotonin-leaning (entactogenic)" words are dropped to the a11y
        // value (design review §3.3): show a clean "SERT : DAT release ≈ 13 : 1".
        DopamineSerotoninLeanBar(
            leanPosition: profile.leanPosition,
            leanLabel: profile.leanLabel,
            ratioText: nil,
            showsLeanLabel: false,
            ratioLine: transporterRatioLine(profile),
            onInfo: onMonoamineInfo,
        )
    }

    /// A transporter-selectivity line — "SERT : DAT release ≈ 1 : 30".
    ///
    /// **SERT is always named first, because it is always the left end of the bar
    /// this line labels.** Ordering by which target is more potent instead meant a
    /// dopamine-dominant compound printed "DAT : SERT ≈ 30 : 1" above a track
    /// running serotonin→dopamine, so the first term named the right-hand end.
    /// Reading order follows the axis; the numbers say which side wins.
    /// `nil` when the ratio is missing.
    private func transporterRatioLine(_ profile: MonoamineProfile) -> String? {
        guard let ratio = profile.datSertRatio, ratio > 0 else { return nil }
        let basis = profile.basis == .release
            ? String(localized: "release", comment: "Transporter ratio basis")
            : String(localized: "reuptake", comment: "Transporter ratio basis")
        /// `datSertRatio` = SERT concentration ÷ DAT concentration. Potency is the
        /// inverse of concentration, so ratio > 1 means DAT is the more potent target.
        func clamp(_ v: Double) -> String {
            v >= 100 ? ">100" : String(Int(v.rounded()))
        }
        if ratio >= 1 {
            return "SERT : DAT \(basis) ≈ 1 : \(clamp(ratio))"
        }
        return "SERT : DAT \(basis) ≈ \(clamp(1 / ratio)) : 1"
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
}
