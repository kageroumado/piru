import SwiftUI

// MARK: - Entry card (session detail → Effect Estimates)

/// The gateway card shown between the Timeline and the dose list when the engine
/// can model a session. A small live preview + a one-line caveat that pushes to
/// the full ``EffectEstimatesView`` — so the timeline stays uncluttered and all
/// the methodology/disclaimer copy has room to live on its own screen.
struct EffectEstimatesCard: View {
    let result: MechanisticSessionModel.Result
    let startDate: Date
    let nowHours: Double
    let doseMarks: [MechanisticSessionModel.DoseMark]
    let vitals: SessionVitals?
    /// Substances in the session the engine models vs. those it can't (display names).
    let modeled: [String]
    let ignored: [String]

    var body: some View {
        Section {
            NavigationLink {
                EffectEstimatesView(
                    result: result,
                    startDate: startDate,
                    nowHours: nowHours,
                    doseMarks: doseMarks,
                    vitals: vitals,
                    modeled: modeled,
                    ignored: ignored,
                )
            } label: {
                HStack(spacing: 12) {
                    EffectThumbnail(result: result)
                        .frame(width: 54, height: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Effect Estimates")
                                .font(.headline)
                            ExperimentalTag()
                        }
                        Text("How this session may feel over time")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

/// A muted "Experimental" pill — the honest-badge idiom, signalling the feature
/// is a model rather than a measurement wherever it's surfaced.
struct ExperimentalTag: View {
    var body: some View {
        Text("Experimental")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color(.secondarySystemFill), in: Capsule())
            .accessibilityHidden(true)
    }
}

/// A tiny non-interactive preview of the session's "Feeling" curve — the live
/// glimpse on the entry card. Draws the shape only (no axes/labels); the real
/// charts live on the pushed screen.
struct EffectThumbnail: View {
    let result: MechanisticSessionModel.Result

    private let lens: EffectLens = .feeling

    var body: some View {
        Canvas { context, size in
            guard let channel = lens.channel else { return }
            let series = result.timeline[keyPath: channel]
            let t = result.timeline.t
            guard t.count > 1, series.count == t.count, let range = result.ranges[lens.rawValue] else { return }
            let span = max(result.contentSpan, 0.5)
            let lo = min(range.lo, 0)
            let denom = max(range.hi - lo, 0.0001)
            func x(_ hour: Double) -> CGFloat {
                CGFloat(min(max(hour / span, 0), 1)) * size.width
            }
            func y(_ value: Double) -> CGFloat {
                size.height - CGFloat((value - lo) / denom) * size.height
            }

            var line = Path()
            var started = false
            for i in 0 ..< t.count where t[i] <= span + 0.001 {
                let point = CGPoint(x: x(t[i]), y: y(series[i]))
                if started { line.addLine(to: point) } else { line.move(to: point); started = true }
            }
            guard started else { return }

            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            context.fill(fill, with: .linearGradient(
                Gradient(colors: [lens.color.opacity(0.32), lens.color.opacity(0.04)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height),
            ))
            context.stroke(line, with: .color(lens.color), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
        .background(lens.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Dedicated screen

/// The full effect-estimates screen: every mechanistic lens as its own card,
/// stacked so they're all visible at once (the whole point of the feature), with
/// the methodology, scale, and per-substance coverage that don't fit inline on
/// the session detail. Reuses ``MechanisticChartView`` per lens.
struct EffectEstimatesView: View {
    let result: MechanisticSessionModel.Result
    let startDate: Date
    let nowHours: Double
    let doseMarks: [MechanisticSessionModel.DoseMark]
    let vitals: SessionVitals?
    let modeled: [String]
    let ignored: [String]

    /// Fixed per-card chart height — tall enough to read the curve, short enough
    /// that all four cards stack in a comfortable scroll.
    private let chartHeight: CGFloat = 150

    private var span: Double {
        result.contentSpan
    }

    var body: some View {
        List {
            introSection
            if !ignored.isEmpty {
                coverageSection
            }
            ForEach(EffectLens.mechanistic) { lens in
                lensCard(lens)
            }
            methodologySection
            modelSection
        }
        .scrollContentBackground(.hidden)
        .listSectionSpacing(16)
        .background(Theme.background)
        .navigationTitle("Effect Estimates")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Intro

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text("A predicted picture, not a measurement")
                        .font(.subheadline.weight(.semibold))
                }
                Text("An experimental model simulates how the substances in this session act in your body, from published pharmacology. It predicts how effects **rise, peak, and fade**, and **how strong they are** — a heavier dose makes a bigger curve. What it can't give you is a real-world unit or a promise about your body on the day.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
            .listRowBackground(CardBackground())
        }
    }

    // MARK: Coverage (only some substances modeled)

    private var coverageSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text("Only some substances are modeled")
                        .font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(Theme.accent)
                }
                Text(coverageText)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
            .listRowBackground(CardBackground())
        }
    }

    private var coverageText: String {
        let included = modeled.formatted(.list(type: .and))
        let excluded = ignored.formatted(.list(type: .and))
        if modeled.isEmpty {
            return String(localized: "\(excluded) isn't modeled yet, so nothing here reflects it.")
        }
        return String(localized: "These curves reflect \(included). \(excluded) isn't modeled yet and doesn't affect them.")
    }

    // MARK: Per-lens card

    private func lensCard(_ lens: EffectLens) -> some View {
        Section {
            MechanisticChartView(
                result: result,
                lens: lens,
                startDate: startDate,
                nowHours: nowHours,
                doseMarks: doseMarks,
                vitals: lens.pairsVitals ? vitals : nil,
                interactive: false,
            )
            .frame(height: chartHeight)
            .listRowInsets(EdgeInsets(top: 4, leading: 0.5, bottom: 4, trailing: 0.5))
            .listRowSeparator(.hidden)
            .listRowBackground(CardBackground())

            if lens.pairsVitals, let vitals, !vitals.isEmpty {
                MechanisticVitalsCards(vitals: vitals, startDate: startDate, nowHours: nowHours)
                    .listRowInsets(EdgeInsets(top: 0, leading: GraphMetrics.cardInset, bottom: 8, trailing: GraphMetrics.cardInset))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: lens.symbol)
                    .foregroundStyle(lens.color)
                    .imageScale(.small)
                Text(lens.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }
        } footer: {
            Text(explanation(for: lens))
        }
    }

    private func explanation(for lens: EffectLens) -> LocalizedStringKey {
        switch lens {
        case .feeling:
            "**Higher is better** — reward and warmth lifting above your baseline. Dipping below the baseline is the comedown."
        case .energy:
            "**Higher is livelier** — stimulation and drive above the baseline; sedation below it."
        case .compulsion:
            "**Lower is better** — the pull to take another dose. The higher it climbs, the harder that pull."
        case .strain:
            "**Lower is better** — estimated load on your body: the higher the curve, the more strain. Pairs with your Apple Health heart rate when it's available."
        case .timeline:
            ""
        }
    }

    // MARK: Methodology

    private var methodologySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                methodologyRow(
                    icon: "ruler",
                    title: "One fixed scale",
                    body: "Every curve shares the same anchored scale, so a taller curve genuinely means a stronger effect — within this session, across your other sessions, and between the four lenses. There's no real-world unit to read off, but the heights are honest.",
                )
                Divider()
                methodologyRow(
                    icon: "arrow.triangle.branch",
                    title: "It won't match other sources",
                    body: "Because this is a simulation, it differs from effect write-ups like PsychonautWiki. Those summarize what people report; this predicts the underlying curve from pharmacology.",
                )
            }
            .padding(.vertical, 2)
            .listRowBackground(CardBackground())
        }
    }

    private func methodologyRow(icon: String, title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(body)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Under the hood (the real model, progressively disclosed)

    /// The honest payoff for the curious: the *actual* mechanism, not a hand-wave.
    /// Collapsed by default (it's dense), it opens to the homeostatic-controller
    /// principle, why rate beats amount, where the comedown comes from, and the
    /// per-lens read-off — with the load-bearing equations shown verbatim.
    private var modelSection: some View {
        Section {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Most effect write-ups describe *what people report*. This does something different — it simulates the underlying neurochemistry and reads the feeling off it.")
                        .fixedSize(horizontal: false, vertical: true)

                    modelPoint(
                        "The core idea",
                        "What you feel is the **error** between the dopamine your dose forces and how far your brain has already compensated — not the dopamine level itself.",
                    )
                    formula(
                        "E  =  D − C",
                        caption: "D = drug-driven dopamine · C = homeostatic push-back (autoreceptors, transporter trafficking, synthesis control)",
                    )

                    modelPoint(
                        "Rate, not amount",
                        "Because C chases D, the error behaves like the **rate** of rise. A fast route (insufflated, IV) outruns the controller and spikes; the same dose taken orally lets C keep up and barely registers a rush.",
                    )
                    modelPoint(
                        "Where the comedown comes from",
                        "C lags on the way down and overshoots. When D falls back to baseline, C is still elevated — so the error goes negative. That's the crash, with **dopamine itself already back to normal**.",
                    )

                    modelPoint(
                        "Dose scaling",
                        "Raw concentration is linear in dose while the dopamine response saturates, so a heavier dose empties the stores proportionally harder — a bigger high **and** a deeper crash.",
                    )
                    formula(
                        "elev = Emax · c / (c + Kd)",
                        caption: "concentration c is linear in dose; the felt elevation saturates (a release/clearance ceiling)",
                    )

                    modelPoint(
                        "Each lens is a different filter on the same drive",
                        "",
                    )
                    formula(
                        """
                        Feeling      = (D − Cₛ) − depletion
                        Energy       = cortical drive − sedation
                        Compulsion   = incentive salience, rate-gated
                        Strain       = cardiovascular + respiratory load
                        """,
                        caption: "Cₛ is the slow controller — as it catches up, the high fades (acclimation).",
                    )
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.top, 4)
            } label: {
                Label {
                    Text("How the model works")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "function")
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.vertical, 2)
            .listRowBackground(CardBackground())
        } footer: {
            Text("Calibrated against published pharmacokinetic and receptor studies (PET occupancy, microdialysis). Still a model — treat it as a rough guide, not medical advice.")
        }
    }

    private func modelPoint(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            if body != "" {
                Text(body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A load-bearing equation, set in mono so it reads as *the math*, with a
    /// plain-language gloss beneath. The horizontal scroll keeps a long line from
    /// forcing the card wider on smaller devices.
    private func formula(_ equation: String, caption: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(equation)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
