import SwiftUI

/// Educational explainer behind the **Tolerance** tool — what the cards *mean* and where the numbers
/// come from. Frames tolerance as one thing (the brain adapting to a repeated input — an allostatic /
/// predictive view, not the 2000s "receptors used up" picture), explains the three timescales that the
/// engine models, cross-tolerance, and the conditioned/novel-setting danger, then surfaces the curated,
/// citation-graded ``ReceptorClasses`` per-mechanism data (each class's `sourceNote` + ``ConfidenceTier``)
/// so a curious user can see the basis, not just a bar. Copy is mechanism-first and matches the
/// redesigned cards (`Specs/tolerance-faithful-model.md` §6, §8.5).
struct ToleranceExplainerView: View {
    var body: some View {
        List {
            Group {
                frameSection
                timescalesSection
                crossToleranceSection
                effectSelectiveSection
                conditionedSection
                mechanismSection
                sourcesSection
            }
            .listRowBackground(CardBackground())
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .appNavigationBar("How tolerance works")
    }

    // MARK: - The idea

    private var frameSection: some View {
        Section {
            concept(
                icon: "brain.head.profile",
                tint: .accentColor,
                title: "Your brain adapts to what you keep giving it",
                body: "Use a drug repeatedly and your brain learns to expect it, then pushes back to cancel the effect — so the same dose does less. That push-back is tolerance. Stop, and it relaxes back. It's not the drug \u{201C}running out\u{201D}; it's your system re-balancing around it.",
            )
            concept(
                icon: "arrow.uturn.backward",
                tint: .teal,
                title: "Why stopping can feel like the opposite",
                body: "When you stop, that push-back is briefly left unopposed — which is why withdrawal or a comedown often feels like the mirror of the drug's effects (a stimulant's flatness, an opioid's aches).",
            )
        } header: {
            Text("The idea")
        }
    }

    // MARK: - Three timescales

    private var timescalesSection: some View {
        Section {
            concept(
                icon: "clock.arrow.circlepath",
                tint: .teal,
                title: "Within a session",
                body: "A second dose soon after the first lands weaker — the fast-releasing pool runs thin (tachyphylaxis). It refills overnight, so it's separate from the slower tolerance below. Chasing it with more rarely works and stacks the risk.",
            )
            concept(
                icon: "chart.line.downtrend.xyaxis",
                tint: .accentColor,
                title: "Over days to weeks",
                body: "Receptors and enzymes adjust, and your baseline shifts down — this is the tolerance most people mean, and what the bar on each card shows. It returns once you stop, at a pace set by the receptor.",
            )
            concept(
                icon: "gauge.with.dots.needle.33percent",
                tint: .orange,
                title: "With heavy, prolonged use",
                body: "This can entrench a deeper change that takes months to relax. It shows up only well past everyday or therapeutic doses — steady use doesn't reach it.",
            )
        } header: {
            Text("Three timescales")
        } footer: {
            Text("Each card blends these into one reading: how much of your usual dose you'd feel now, and how long until it returns if you stop.")
        }
    }

    // MARK: - Cross-tolerance

    private var crossToleranceSection: some View {
        Section {
            concept(
                icon: "arrow.triangle.branch",
                tint: .purple,
                title: "Tolerance is shared by receptor, not by name",
                body: "Two different drugs that hit the same receptor share tolerance. Recent LSD blunts a mushroom trip because both work at 5-HT2A; one benzodiazepine carries to another; one opioid to the next. That's why tolerance is tracked per receptor here, and why a \u{201C}new\u{201D} drug in the same family can still feel weak.",
            )
        } header: {
            Text("Cross-tolerance")
        }
    }

    // MARK: - Effect-selective tolerance (the ladder's "why")

    private var effectSelectiveSection: some View {
        Section {
            concept(
                icon: "slider.horizontal.below.square.filled.and.square",
                tint: .blue,
                title: "Some effects fade, others don't",
                body: "For most drugs every effect tolerizes together. Benzodiazepines are the exception: sedation fades almost completely in about two weeks, while the anxiety relief, memory impairment and loss of coordination barely change. That's why the benzodiazepine and gabapentinoid cards show an effect ladder instead of one bar.",
            )
            concept(
                icon: "circle.hexagongrid",
                tint: .purple,
                title: "Why — the receptor comes in subtypes",
                body: "GABA-A is built from several \u{03B1}-subtypes that adapt at different rates. \u{03B1}1 carries sedation and desensitizes (it uncouples, then the receptors are pulled from the synapse); \u{03B1}5 is required for that sedative tolerance to develop at all; \u{03B1}2 and \u{03B1}3, which carry the anxiety relief, don't adapt. So the dose that no longer makes you sleepy impairs your memory and coordination exactly as much as it did on day one — which is how tolerance quietly drives the dose up.",
            )
        } header: {
            Text("Effect-selective tolerance")
        } footer: {
            Text("Benzodiazepine effect kinetics: Vinkers & Olivier 2012; Piot & Jovanovic 2026. These are directions from the literature, graded low — not fitted numbers.")
        }
    }

    // MARK: - Conditioned / novel-setting

    private var conditionedSection: some View {
        Section {
            concept(
                icon: "mappin.and.ellipse",
                tint: .orange,
                title: "Where you use it matters",
                body: "Tolerance is partly learned in context: your body braces in a familiar place. In a new setting, or after a change in routine, that bracing doesn't fire — so the same dose hits harder than expected. With opioids especially, a dose that felt fine before can become dangerous after a break or in a new environment.",
            )
        } header: {
            Text("Setting & a break")
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
            Text("Recovery timescales and behavior are calibrated to the published literature for each receptor class. The note under each is the calibration basis; the badge is how well-established those kinetics are.")
        }
    }

    private func mechanismRow(_ cls: ReceptorClasses.ReceptorClass) -> some View {
        let parameters = ReceptorClasses.parameters(for: cls)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(cls.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                ConfidenceBadge(tier: parameters.confidence)
            }
            Label(recoveryDescriptor(parameters), systemImage: "clock.arrow.circlepath")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
            Text(meaning(cls))
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
            Text(parameters.sourceNote)
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
                Text("Binding affinities come from the NIMH PDSP K\u{1D62} database and primary literature; the recovery kinetics are calibrated to published human studies. Every parameter is graded, and anything resting on a class default is flagged. The cards are predicted from your dose log and these curated values — estimates.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Class copy

    /// Classes in a teaching order (the everyday-tolerance ones first, then the rebound-hosting
    /// adrenergics last — they barely tolerize), `.unknown` omitted.
    private var orderedClasses: [ReceptorClasses.ReceptorClass] {
        [
            .psychedelic5HT2A, .muOpioid, .gaba, .nmdaAntagonist, .cannabinoidCB1, .adenosine,
            .catecholamineStimulant, .serotonergicReleaser, .nicotinic, .alpha2Delta, .alpha2Agonist, .betaBlocker,
        ]
    }

    /// A qualitative recovery timescale from the class's adaptive layer — the days–weeks baseline
    /// shift that dominates how long sensitivity takes to return.
    private func recoveryDescriptor(_ parameters: ReceptorClasses.Parameters) -> LocalizedStringResource {
        let tauDays = parameters.tauAdaptiveMinutes / (60 * 24)
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
            "Real tolerance that drops after a break — which is exactly what makes returning to an old dose dangerous."
        case .gaba:
            "Tolerance plus physical dependence; stopping abruptly after heavy regular use can be dangerous — taper."
        case .nmdaAntagonist:
            "Builds its own tolerance, and can also slow opioid tolerance when taken together."
        case .cannabinoidCB1:
            "Fast and real, but recovers fairly quickly once you stop."
        case .adenosine:
            "Clean, predictable tolerance — the caffeine case."
        case .catecholamineStimulant:
            "A fast within-session fade, plus a modest, slower shift with heavy use. A bigger dose still works — but ramps the comedown and the risk, while the effect on your heart barely fades."
        case .serotonergicReleaser:
            "Runs down with use and returns over weeks. MDMA-type use is slower because it dents serotonin supply as well as the receptors."
        case .nicotinic:
            "Mostly fast receptor desensitization that recovers between uses rather than a lasting change."
        case .alpha2Delta:
            "Sedative tolerance builds; dependence can develop within weeks of daily use. Phenibut withdrawal is among the most severe."
        case .alpha2Agonist:
            "Barely builds tolerance — the real risk is stopping suddenly: blood pressure can rebound hard. Taper, don't quit cold."
        case .betaBlocker:
            "Barely builds tolerance — the real risk is stopping suddenly: heart rate and blood pressure can rebound. Taper, don't quit cold."
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
