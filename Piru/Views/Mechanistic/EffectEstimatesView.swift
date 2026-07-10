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

/// A muted "Experimental" pill — the honest-badge idiom, signaling the feature
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

/// The full effect-estimates screen: a large title, one short model card, every
/// mechanistic lens as its own tall card, and two collapsed detail groups at the
/// bottom for coverage and how to read the estimate. The full methodology lives
/// one push deeper in ``EffectModelExplainerView`` so this screen stays glanceable.
struct EffectEstimatesView: View {
    let result: MechanisticSessionModel.Result
    let startDate: Date
    let nowHours: Double
    let doseMarks: [MechanisticSessionModel.DoseMark]
    let vitals: SessionVitals?
    let modeled: [String]
    let ignored: [String]

    /// Fixed per-card chart height. Taller than the inline session-detail graph —
    /// this is the dedicated screen, so each curve gets room to read.
    private let chartHeight: CGFloat = 200

    var body: some View {
        List {
            introSection
            if isBusySession {
                complexityNote
            }
            ForEach(EffectLens.mechanistic) { lens in
                lensCard(lens)
            }
            coverageGroup
            readingGroup
        }
        .scrollContentBackground(.hidden)
        .listSectionSpacing(16)
        .background(Theme.background)
        .navigationTitle("Effect Estimates")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Intro — one short model card

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text("Modeled from pharmacology")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    ExperimentalTag()
                }
                Text("These curves estimate how this session may feel over time — how effects rise, peak, and fade, and how strong they get. Redoses and each substance's full duration are included, so a bigger dose lifts the curve higher.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink {
                    EffectModelExplainerView()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "function")
                            .imageScale(.small)
                        Text("How this works")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
            .listRowBackground(CardBackground())
        }
    }

    // MARK: Busy-session honesty note

    /// The engine is calibrated on single-substance, single-dose lab data. A
    /// session that stacks many intakes and substances multiplies the parameters
    /// it has to juggle, so we flag it. Threshold: more than five modeled intakes.
    private var isBusySession: Bool {
        doseMarks.count > 5
    }

    private var complexityNote: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("A busy session")
                        .font(.subheadline.weight(.semibold))
                    Text("The model is calibrated on a single substance taken once, in lab conditions. The interactions here stay mechanistic, but each extra dose and substance adds parameters and widens the margin of error.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 2)
            .listRowBackground(CardBackground())
        }
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
                interactive: true,
                startFramed: true,
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
            Text(footer(for: lens))
        }
    }

    private func footer(for lens: EffectLens) -> LocalizedStringKey {
        switch lens {
        case .feeling:
            "Higher is better. Pleasure and warmth rise above the line; the comedown dips below."
        case .energy:
            "Higher is livelier. Drive rises above the line, sedation sits below."
        case .compulsion:
            "Lower is better. The pull to take another dose."
        case .strain:
            "Lower is better. Load on the body, shown with your heart rate when it's available."
        case .timeline:
            ""
        }
    }

    // MARK: Bottom — coverage

    private var coverageGroup: some View {
        Section {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    if !ignored.isEmpty {
                        Text(coverageText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("The model is calibrated on five stimulants: amphetamine, methylphenidate, mephedrone, 3-MMC, and 2-MMC. Other substances shape the curves through how they interact with these. Opioids are read through their dopamine activity, mostly to show those interactions.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.top, 6)
            } label: {
                detailLabel("square.stack.3d.up", "What these curves cover")
            }
            .padding(.vertical, 2)
            .listRowBackground(CardBackground())
        }
    }

    private var coverageText: String {
        let included = modeled.formatted(.list(type: .and))
        let excluded = ignored.formatted(.list(type: .and))
        if modeled.isEmpty {
            return String(localized: "This session logs \(excluded), which sit outside the model, so these curves stay empty.")
        }
        return String(localized: "These curves are built from \(included). \(excluded) sit outside the model.")
    }

    // MARK: Bottom — reading the estimate

    private var readingGroup: some View {
        Section {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Text("This is a picture of typical pharmacology. Your own response shifts with tolerance, body chemistry, and the day.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Confidence varies by substance. Well-studied ones like amphetamine and methylphenidate rest on firmer data than newer compounds.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Compare the shape of a curve more than its exact height.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.top, 6)
            } label: {
                detailLabel("checkmark.seal", "Reading the estimate")
            }
            .padding(.vertical, 2)
            .listRowBackground(CardBackground())
        } footer: {
            Text("A rough guide, not medical advice.")
        }
    }

    private func detailLabel(_ icon: String, _ title: LocalizedStringKey) -> some View {
        Label {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(Theme.accent)
        }
    }
}

// MARK: - How this works

/// The methodology screen, one push below Effect Estimates: the homeostatic idea
/// told in plain language and anchored by a schematic ``DopamineErrorDiagram`` —
/// dopamine against the brain's slower-moving expectation, with the gap between
/// them shaded as the felt effect. Room to breathe, readable body text; the dense
/// equations from the old inline disclosure are retired in favor of the picture.
struct EffectModelExplainerView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text("What you feel tracks a gap inside your dopamine system — the distance between the dopamine you have and the steady level your brain expects.")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    DopamineErrorDiagram()
                        .frame(height: 172)
                        .padding(.vertical, 2)

                    DiagramLegend()

                    Text("As a stimulant takes hold, dopamine climbs quickly. Your brain expects a steady baseline and adjusts toward the new level, but it catches up slowly. The gap between the two — dopamine now versus what your brain expects — is what reaches you.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                .listRowBackground(CardBackground())
            }

            Section {
                VStack(alignment: .leading, spacing: 16) {
                    point(
                        "Rate over amount",
                        "A fast route, like insufflation, outruns that adjustment and spikes. The same dose taken slowly lets the brain keep pace, so it barely registers as a rush.",
                    )
                    Divider()
                    point(
                        "The comedown",
                        "On the way down the expectation lags again. Dopamine returns to baseline while the expectation stays high, and that gap below the line is the comedown.",
                    )
                    Divider()
                    point(
                        "Heavier doses",
                        "A larger dose draws dopamine stores down harder: a bigger rise, and a deeper dip once it clears.",
                    )
                }
                .padding(.vertical, 4)
                .listRowBackground(CardBackground())
            }
        }
        .scrollContentBackground(.hidden)
        .listSectionSpacing(16)
        .background(Theme.background)
        .navigationTitle("How this works")
        .navigationBarTitleDisplayMode(.large)
    }

    private func point(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A schematic — not a live simulation — of the homeostatic idea: a fast dopamine
/// bell against a slow first-order "expectation" that chases it. The region where
/// dopamine leads is shaded as the felt lift; the tail where expectation lags above
/// a falling dopamine is shaded as the comedown.
private struct DopamineErrorDiagram: View {
    private let dopamineColor = EffectLens.feeling.color
    private let expectationColor = Color(.systemGray)

    private struct Sample {
        let time: Double
        let dopamine: Double
        let expectation: Double
    }

    private let samples: [Sample] = DopamineErrorDiagram.makeSamples()

    /// Difference-of-exponentials dopamine curve (peak-normalized) with a slow
    /// first-order lag for the expectation, integrated by explicit Euler.
    private static func makeSamples() -> [Sample] {
        let absorptionRate = 5.0
        let eliminationRate = 0.9
        let lagTau = 0.8
        let step = 0.02
        let horizon = 7.0

        var forcing: [(time: Double, level: Double)] = []
        var peak = 0.0001
        var time = 0.0
        while time <= horizon {
            let level = max(exp(-eliminationRate * time) - exp(-absorptionRate * time), 0)
            peak = max(peak, level)
            forcing.append((time, level))
            time += step
        }

        var expectation = 0.0
        var out: [Sample] = []
        out.reserveCapacity(forcing.count)
        for sample in forcing {
            let dopamine = sample.level / peak
            expectation += (dopamine - expectation) * (step / lagTau)
            out.append(Sample(time: sample.time, dopamine: dopamine, expectation: expectation))
        }
        return out
    }

    var body: some View {
        Canvas { context, size in
            guard let last = samples.last, samples.count > 1 else { return }
            let inset: CGFloat = 6
            let topPad: CGFloat = 10
            let bottomPad: CGFloat = 6
            let plot = CGRect(
                x: inset, y: topPad,
                width: max(1, size.width - inset * 2),
                height: max(1, size.height - topPad - bottomPad),
            )
            let horizon = max(last.time, 0.001)
            func point(_ t: Double, _ value: Double) -> CGPoint {
                CGPoint(
                    x: plot.minX + CGFloat(t / horizon) * plot.width,
                    y: plot.maxY - CGFloat(min(max(value, 0), 1.05)) * plot.height,
                )
            }

            // Shade the vertical gap between the two curves, trapezoid by trapezoid,
            // colored by which curve leads — accent while dopamine leads (the lift),
            // red where the expectation sits above a falling dopamine (the comedown).
            for i in 0 ..< samples.count - 1 {
                let a = samples[i], b = samples[i + 1]
                var quad = Path()
                quad.move(to: point(a.time, a.dopamine))
                quad.addLine(to: point(b.time, b.dopamine))
                quad.addLine(to: point(b.time, b.expectation))
                quad.addLine(to: point(a.time, a.expectation))
                quad.closeSubpath()
                let dopamineLeads = (a.dopamine + b.dopamine) >= (a.expectation + b.expectation)
                let fill = dopamineLeads ? dopamineColor.opacity(0.22) : EffectLens.crash.opacity(0.16)
                context.fill(quad, with: .color(fill))
            }

            var expectationPath = Path()
            var dopaminePath = Path()
            for (i, sample) in samples.enumerated() {
                let de = point(sample.time, sample.expectation)
                let dp = point(sample.time, sample.dopamine)
                if i == 0 {
                    expectationPath.move(to: de)
                    dopaminePath.move(to: dp)
                } else {
                    expectationPath.addLine(to: de)
                    dopaminePath.addLine(to: dp)
                }
            }
            context.stroke(expectationPath, with: .color(expectationColor), style: StrokeStyle(lineWidth: 2, lineJoin: .round, dash: [4, 3]))
            context.stroke(dopaminePath, with: .color(dopamineColor), style: StrokeStyle(lineWidth: 2.6, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// The two-curve legend for ``DopamineErrorDiagram`` — kept in SwiftUI (crisper
/// text than in-canvas) and glossing what the two shaded zones mean.
private struct DiagramLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                swatch(EffectLens.feeling.color, dashed: false, "Dopamine")
                swatch(Color(.systemGray), dashed: true, "Expected level")
            }
            Text("The shaded gap is what you feel. As dopamine fades and the expectation lags above it, that gap turns into the comedown.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func swatch(_ color: Color, dashed: Bool, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Canvas { context, size in
                var line = Path()
                line.move(to: CGPoint(x: 0, y: size.height / 2))
                line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2.4, dash: dashed ? [3, 2] : []))
            }
            .frame(width: 18, height: 6)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }
}
