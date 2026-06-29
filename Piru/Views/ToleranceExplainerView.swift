import SwiftUI

/// Educational explainer behind the **Tolerance** tool — what the numbers *mean* and where they come
/// from (`Specs/pharmacology-axis-meta-plan.md`, Stage 5 follow-up). The tool shows per-target
/// availability/load; this screen explains the three kinds of tolerance, cross-tolerance, and the
/// per-mechanism kinetics — surfacing the curated, citation-graded `ReceptorClasses` data (each class's
/// calibration `sourceNote` + ``ConfidenceTier``) so a curious user can see the basis, not just a bar.
struct ToleranceExplainerView: View {
    var body: some View {
        List {
            Group {
                axesSection
                crossToleranceSection
                mechanismSection
                sourcesSection
            }
            .listRowBackground(Theme.cardBackground)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .appNavigationBar("How tolerance works")
    }

    // MARK: - The three axes

    private var axesSection: some View {
        Section {
            concept(
                icon: "chart.line.downtrend.xyaxis",
                tint: .accentColor,
                title: "Availability — the real tolerance",
                body: "With repeated use a receptor gets less responsive, so the same dose does less. We show it as your predicted response versus rested (≈X%). It recovers when you stop — over days to weeks depending on the receptor. This is the honest \u{201C}tolerance\u{201D} for opioids, psychedelics, benzodiazepines, dissociatives, and cannabis.",
            )
            concept(
                icon: "clock.arrow.circlepath",
                tint: .teal,
                title: "Within-session redose",
                body: "Separately, a second dose the same session often lands weaker — fast desensitization (tachyphylaxis). It recovers overnight, so it's shown apart from the slow tolerance above. Chasing it with more rarely works and stacks risk.",
            )
            concept(
                icon: "gauge.with.dots.needle.33percent",
                tint: .orange,
                title: "Recovery-state load — not a multiplier",
                body: "For stimulants and serotonin releasers there is no honest \u{201C}tolerance %\u{201D} to multiply a dose by. The slow change is a months-long recovery state of the whole system, not a take-more signal. We show that as a bounded load bar instead of a fake number — refusing to imply a dose you should escalate to.",
            )
        } header: {
            Text("Three kinds of tolerance")
        } footer: {
            Text("These are model predictions of how repeated use changes each receptor — never a measurement. Each figure carries a confidence tier.")
        }
    }

    // MARK: - Cross-tolerance

    private var crossToleranceSection: some View {
        Section {
            concept(
                icon: "arrow.triangle.branch",
                tint: .purple,
                title: "Tolerance is shared by receptor, not by name",
                body: "Two different drugs that hit the same receptor share tolerance. Recent LSD lowers a mushroom trip because both work at 5-HT2A; one benzodiazepine carries to another; one opioid to the next. That's why tolerance here is tracked per receptor target, and why a \u{201C}new\u{201D} drug in the same family can still be blunted.",
            )
        } header: {
            Text("Cross-tolerance")
        }
    }

    // MARK: - Per-mechanism reference (the cited data)

    private var mechanismSection: some View {
        Section {
            ForEach(orderedClasses, id: \.self) { cls in
                mechanismRow(cls)
            }
        } header: {
            Text("By mechanism")
        } footer: {
            Text("Recovery timescales and tolerance behaviour are calibrated to the published literature for each receptor class. The note under each is the calibration basis; the badge is how well-established those kinetics are.")
        }
    }

    private func mechanismRow(_ cls: ReceptorClasses.ReceptorClass) -> some View {
        let p = ReceptorClasses.parameters(for: cls)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(cls.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                ConfidenceBadge(tier: p.confidence)
            }
            Label(recoveryDescriptor(p), systemImage: "clock.arrow.circlepath")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
            Text(meaning(cls))
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
            Text(p.sourceNote)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel.opacity(0.8))
        }
        .padding(.vertical, 4)
    }

    private var sourcesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("Where the numbers come from", systemImage: "checkmark.seal")
                    .font(.subheadline.weight(.semibold))
                Text("Binding affinities come from the NIMH PDSP K\u{1D62} database and primary literature; the tolerance kinetics are calibrated to published human recovery studies. Every parameter is graded, and anything resting on a class default is flagged. Nothing here is measured from you — it's predicted from your dose log and these curated values.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Class copy

    /// Classes in a teaching order (multiplier-valid first, then the load classes), `.unknown` omitted.
    private var orderedClasses: [ReceptorClasses.ReceptorClass] {
        [
            .psychedelic5HT2A, .muOpioid, .gaba, .nmdaAntagonist, .cannabinoidCB1, .adenosine,
            .catecholamineStimulant, .serotonergicReleaser, .nicotinic,
        ]
    }

    /// A qualitative recovery timescale from the class's adaptive layer — the days–weeks baseline
    /// shift that dominates how long sensitivity takes to return.
    private func recoveryDescriptor(_ p: ReceptorClasses.Parameters) -> LocalizedStringResource {
        let tauDays = p.tauAdaptiveMinutes / (60 * 24)
        switch tauDays {
        case ..<2: return "Recovers in days"
        case ..<8: return "Recovers over ~a week"
        case ..<20: return "Recovers over weeks"
        case ..<70: return "Recovers over a month+"
        default: return "Recovers over months"
        }
    }

    private func meaning(_ cls: ReceptorClasses.ReceptorClass) -> LocalizedStringResource {
        switch cls {
        case .psychedelic5HT2A:
            "Strong and fast: a second trip soon after is much weaker. Resets within a few days."
        case .muOpioid:
            "Real tolerance that resets after a break — which is exactly what makes returning to an old dose dangerous."
        case .gaba:
            "Tolerance plus physical dependence; stopping abruptly after heavy regular use can be dangerous — taper."
        case .nmdaAntagonist:
            "Builds its own tolerance, and can also blunt opioid tolerance when taken together."
        case .cannabinoidCB1:
            "Fast and real, but recovers fairly quickly once you stop."
        case .adenosine:
            "Clean, predictable tolerance — the caffeine case, the textbook example."
        case .catecholamineStimulant:
            "No single \u{201C}tolerance %\u{201D} fits: a fast within-session fade plus a slow, months-long recovery state — not a signal to take more."
        case .serotonergicReleaser:
            "A reversible-leaning change at the serotonin transporter — a recovery-state indicator, not a dose multiplier."
        case .nicotinic:
            "Mostly fast receptor desensitization that recovers between uses rather than a lasting dose multiplier."
        case .unknown:
            "Generic class-default kinetics at the lowest confidence."
        }
    }

    // MARK: - Concept card

    private func concept(icon: String, tint: Color, title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(body)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .padding(.vertical, 4)
    }
}
