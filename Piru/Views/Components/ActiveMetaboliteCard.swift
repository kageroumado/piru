import Charts
import SwiftUI

// The "Also Active" surface: what your body turns a substance into, when that
// byproduct is doing some of the work. Distinct from the Metabolism disclosure,
// which answers "how does my body clear this" — enzymes, clearance shares,
// citations — and stays pharma-nerd. This answers "is something other than what
// I took producing the effect", which is a fact about the user's experience
// rather than reference data, and so is surfaced a tier earlier.

// MARK: - Card

/// One metabolite, led by what it means for the reader rather than by its
/// chemistry. The name is the subject; the statement beneath it is the payload.
///
/// A number never out-ranks the sentence explaining it: claims sit at
/// `.subheadline`/`.primary`, every hedge and secondary measurement at
/// `.caption`/`Theme.secondaryLabel`.
struct ActiveMetaboliteCard: View {
    let metabolite: ActiveMetabolite
    let parentName: String
    let parentHalfLifeMinutes: Double?
    let accent: Color
    /// The total duration displayed above this card, which the duration claim is
    /// measured against. Nil for substances with no acute duration profile —
    /// chronic medications, where there is no "duration above" to outlast.
    let parentDurationMinutes: Double?
    /// Push the metabolite's own detail. Absent when it isn't in the library,
    /// which is the card's only degradation — every other band is identical, so
    /// a missing link never reads as missing information.
    var onOpenSubstance: ((String) -> Void)?

    private var statement: MetaboliteStatement {
        metabolite.statement(
            parentName: parentName,
            parentHalfLifeMinutes: parentHalfLifeMinutes,
            parentDurationMinutes: parentDurationMinutes,
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            nameRow
            VStack(alignment: .leading, spacing: Spacing.sm) {
                primaryLine
                secondaryLines
            }
            chips
            sourceLine(
                slug: metabolite.sourceSlug, detail: nil,
                citation: metabolite.citation, accent: accent,
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // No `.padding(14).themeCard()`. Both call sites are List rows that
        // already carry the screen's card background, so drawing another one
        // here nested a 22pt-radius card inside the row's card at a different
        // inset — the one card on the screen that didn't match its siblings.
        .padding(.vertical, Spacing.xxs)
    }

    // MARK: Bands

    @ViewBuilder
    private var nameRow: some View {
        if let target = metabolite.substanceName, let onOpenSubstance {
            Button { onOpenSubstance(target) } label: {
                HStack(spacing: Spacing.sm) {
                    Text(verbatim: metabolite.displayName)
                        .sectionLabel()
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.tertiaryLabel)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens this substance in the library."))
        } else {
            Text(verbatim: metabolite.displayName)
                .sectionLabel()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var primaryLine: some View {
        Text(primaryText)
            .font(.subheadline)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The hedge (when the claim needs one), any second measurement, and the
    /// note that a figure was withheld. All caption-weight — none may compete
    /// with the headline.
    @ViewBuilder
    private var secondaryLines: some View {
        if case let .qualified(_, _, basis, _) = statement {
            caption(hedge(for: basis))
        }
        if let extra = metabolite.secondaryPotency(for: statement) {
            caption(measurementText(extra, prefix: hasHeadlineClaim))
        }
        if metabolite.conversionVariesByGenetics {
            MetabolizerVariationChart(
                metaboliteName: metabolite.displayName,
                halfLifeMinutes: metabolite.halfLifeMinutes ?? 180,
            )
        }
        if metabolite.hasSuppressedMagnitude {
            caption(String(localized: "How strong it is compared to \(parentName) hasn't been established."))
        }
    }

    /// `Made by`, the half-life pair, and the share of the dose that becomes
    /// this metabolite. The half-life pair is the answer to "why is this still
    /// going" as a *layout* rather than a sentence — nothing to translate.
    @ViewBuilder
    private var chips: some View {
        let halfLives = halfLifePair
        if !metabolite.enzymes.isEmpty || halfLives != nil || metabolite.formationFractionPct != nil {
            HStack(alignment: .top, spacing: Spacing.md) {
                if !metabolite.enzymes.isEmpty {
                    PKMetricChip(
                        label: "Made by",
                        value: metabolite.enzymes.joined(separator: ", "),
                    )
                }
                if let halfLives {
                    PKMetricChip(verbatimLabel: metabolite.displayName, value: halfLives.metabolite)
                    PKMetricChip(verbatimLabel: parentName, value: halfLives.parent)
                }
                if let fraction = metabolite.formationFractionPct {
                    PKMetricChip(
                        label: "Share of dose",
                        value: "~\(SubstanceDetailView.chemNumber(fraction))%",
                    )
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Copy

    private var hasHeadlineClaim: Bool {
        switch statement {
        case .comparable, .strongerMolecule: true
        case .outlastsDuration, .persistsBeyondParent, .qualified, .divergent, .relationshipOnly: false
        }
    }

    /// Both half-lives, or neither — a lone number invites the reader to compare
    /// it against something they don't have.
    private var halfLifePair: (metabolite: String, parent: String)? {
        guard let mine = metabolite.halfLifeMinutes, let parent = parentHalfLifeMinutes else { return nil }
        return (pkMinutes(mine), pkMinutes(parent))
    }

    private var primaryText: String {
        switch statement {
        case let .outlastsDuration(metabolite, parent):
            // Say only what the gate proves. It tests
            // `metaboliteHalfLife >= parentDuration` — the metabolite is still
            // around when the stated duration runs out. Never phrase this as a
            // comparison of clearance *rates* ("clears more slowly than"): that
            // claim needs half-life vs half-life, and for methamphetamine →
            // amphetamine both are ~10 h, so it would be false exactly where
            // this case fires.
            String(localized: "Effects can outlast the duration above. \(metabolite) is still present when \(parent)'s listed duration ends.")
        case let .persistsBeyondParent(metabolite, parent):
            String(localized: "\(metabolite) stays active in your body long after \(parent) itself is gone.")
        case let .comparable(ratio, parent):
            if ratio == 1 {
                String(localized: "About as strong as \(parent), dose for dose.")
            } else {
                String(localized: "About \(SubstanceDetailView.chemNumber(ratio))× as strong as \(parent), dose for dose.")
            }
        case let .strongerMolecule(ratio, parent, metabolite, convertedPct):
            // A prodrug converting one-for-one lands here whenever its formation
            // fraction was never recorded (psilocybin → psilocin). "About 1× as
            // strong" is not a sentence, so parity gets its own wording.
            if ratio == 1 {
                String(localized: "Molecule for molecule, \(metabolite) is about as strong as \(parent).")
            } else if let convertedPct {
                // The useful sentence, and the one oxycodone can actually make:
                // the ratio is only half the story, and the other half is on the
                // row. Naming it is what stops "10× as strong" being read as a
                // dose claim.
                String(localized: "Molecule for molecule, \(metabolite) is about \(SubstanceDetailView.chemNumber(ratio))× as strong as \(parent), but only about \(SubstanceDetailView.chemNumber(convertedPct))% of a dose becomes it.")
            } else {
                String(localized: "Molecule for molecule, \(metabolite) is about \(SubstanceDetailView.chemNumber(ratio))× as strong as \(parent), but how much of a dose converts isn't recorded here.")
            }
        case let .qualified(ratio, parent, _, target):
            if let target = metaboliteTargetName(target), ratio == 1 {
                String(localized: "About as strong as \(parent) at the \(target).")
            } else if let target = metaboliteTargetName(target) {
                String(localized: "About \(SubstanceDetailView.chemNumber(ratio))× \(parent)'s activity at the \(target).")
            } else {
                String(localized: "About \(SubstanceDetailView.chemNumber(ratio))× \(parent)'s activity, by one measurement.")
            }
        case let .divergent(parent):
            String(localized: "Acts differently from \(parent), not simply stronger or weaker.")
        case let .relationshipOnly(parent, metabolite):
            String(localized: "Your body turns \(parent) into \(metabolite), which is active too.")
        }
    }

    private func hedge(for basis: SubstanceStore.MetabolitePotencyBasis) -> String {
        switch basis {
        case .receptorAffinity: String(localized: "A binding-affinity measurement, not clinical potency.")
        case .inVitro, .clinical, .unknown: String(localized: "A lab measurement, not clinical potency.")
        }
    }

    /// A measurement rendered as a full sentence carrying its own basis and
    /// target, so it can be read on its own without the headline above it.
    ///
    /// A **clinical** measurement takes the plain comparative and no hedge —
    /// describing it as "a lab measurement, not clinical potency" would be
    /// flatly untrue, and that is exactly what a single shared phrasing did to
    /// diazepam → nordazepam. Only affinity/in-vitro figures get hedged.
    private func measurementText(_ potency: ActiveMetabolite.Potency, prefix: Bool) -> String {
        let ratio = SubstanceDetailView.chemNumber(potency.pct / 100)
        if potency.basis == .clinical {
            // Same rule as the headline: "dose for dose" needs the share of the
            // dose that converts, or it is a molecule ratio wearing a dose
            // ratio's clothes.
            guard let fraction = metabolite.formationFractionPct,
                  fraction >= ActiveMetabolite.Threshold.doseEquivalentFormationPct
            else {
                return String(localized: "Molecule for molecule, about \(ratio)× as strong as \(parentName).")
            }
            return potency.pct == 100
                ? String(localized: "About as strong as \(parentName), dose for dose.")
                : String(localized: "About \(ratio)× as strong as \(parentName), dose for dose.")
        }
        let kind = potency.basis == .receptorAffinity
            ? String(localized: "binding affinity")
            : String(localized: "activity")
        guard let target = metaboliteTargetName(potency.target) else {
            return prefix
                ? String(localized: "Also measured at \(ratio)× \(parentName)'s \(kind). A lab measurement, not clinical potency.")
                : String(localized: "Measured at \(ratio)× \(parentName)'s \(kind). A lab measurement, not clinical potency.")
        }
        return prefix
            ? String(localized: "Also measured at \(ratio)× \(parentName)'s \(kind) at the \(target). A lab measurement, not clinical potency.")
            : String(localized: "Measured at \(ratio)× \(parentName)'s \(kind) at the \(target). A lab measurement, not clinical potency.")
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .captionSecondary()
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Metabolizer Variation Chart

/// A compact inline chart showing how a polymorphic enzyme (CYP2D6/CYP2C19)
/// creates different metabolite levels in fast vs slow metabolizers. Replaces a
/// text description with a visual that communicates the concept at a glance.
private struct MetabolizerVariationChart: View {
    let metaboliteName: String
    let halfLifeMinutes: Double

    private struct CurvePoint: Identifiable {
        let id: Int
        let hours: Double
        let level: Double
        let phenotype: String
    }

    private var curves: [CurvePoint] {
        let ke = log(2) / (halfLifeMinutes / 60)
        let ka = max(ke * 4, 2.0)
        let steps = 24
        let maxHours = min(max(halfLifeMinutes / 60 * 3.5, 4), 12)
        let dt = maxHours / Double(steps)

        var points: [CurvePoint] = []
        let fast = String(localized: "Fast metabolizer")
        let slow = String(localized: "Slow metabolizer")

        var peakFast: Double = 0
        for i in 0 ... steps {
            let t = Double(i) * dt
            let c = 3.0 * ka / (ka - ke) * (exp(-ke * t) - exp(-ka * t))
            peakFast = max(peakFast, c)
        }
        let norm = peakFast > 0 ? peakFast : 1

        for i in 0 ... steps {
            let t = Double(i) * dt
            let cFast = 3.0 * ka / (ka - ke) * (exp(-ke * t) - exp(-ka * t)) / norm
            let cSlow = 0.5 * ka / (ka - ke) * (exp(-ke * t) - exp(-ka * t)) / norm
            points.append(CurvePoint(id: i, hours: t, level: max(0, cFast), phenotype: fast))
            points.append(CurvePoint(id: steps + 1 + i, hours: t, level: max(0, cSlow), phenotype: slow))
        }
        return points
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Genetic variation in \(metaboliteName) formation")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.secondaryLabel)
            Chart(curves) { point in
                LineMark(
                    x: .value("Hours", point.hours),
                    y: .value("Level", point.level),
                    series: .value("Phenotype", point.phenotype),
                )
                .foregroundStyle(by: .value("Phenotype", point.phenotype))
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .interpolationMethod(.catmullRom)
            }
            .chartForegroundStyleScale([
                String(localized: "Fast metabolizer"): Color.orange,
                String(localized: "Slow metabolizer"): Color.blue.opacity(0.6),
            ])
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisValueLabel {
                        if let hours = value.as(Double.self) {
                            Text("\(hours.formatted(.number.precision(.fractionLength(0))))h")
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartLegend(position: .bottom, alignment: .leading, spacing: Spacing.xs)
            .frame(height: 80)
            Text("Same dose, different conversion. The effect varies by genotype.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }
}
