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
                    modeled: modeled,
                    ignored: ignored,
                )
            } label: {
                HStack(spacing: Spacing.xl) {
                    EffectThumbnail(result: result)
                        .frame(width: 54, height: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: Spacing.sm) {
                            Text("Effect Estimates")
                                .cardTitle()
                            EstimationTag()
                        }
                        Text("Feeling and energy estimated from this session")
                            .captionSecondary()
                    }
                }
                .padding(.vertical, Spacing.xxs)
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
            .foregroundStyle(Theme.secondaryLabel)
            .padding(.horizontal, 7)
            .padding(.vertical, Spacing.xxs)
            .background(Color.platformSecondarySystemFill, in: skinChipShape())
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
        .background(lens.color.opacity(Theme.Opacity.hairline), in: RoundedRectangle(cornerRadius: Theme.CornerRadius.inner, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.inner, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Dedicated screen

/// The full effect-estimates screen: a large title, one short model card, every
/// mechanistic lens as its own tall card, and two detail cards at the bottom for
/// coverage and how to read the estimate. The full methodology lives one push
/// deeper in ``EffectModelExplainerView`` so this screen stays glanceable.
struct EffectEstimatesView: View {
    let result: MechanisticSessionModel.Result
    let startDate: Date
    let nowHours: Double
    let doseMarks: [MechanisticSessionModel.DoseMark]
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
            ForEach(result.activeLenses) { lens in
                lensCard(lens)
            }
            coverageSection
            readingSection
        }
        .insetGroupedListStyle()
        .scrollContentBackground(.hidden)
        .compactListSectionSpacing()
        .skinBackdrop()
        .readableWidth()
        .navigationTitle("Effect Estimates")
        #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.large)
        #endif
    }

    // MARK: Intro — one short model card

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text("Modeled from pharmacology")
                        .sectionLabel()
                    Spacer(minLength: 0)
                    EstimationTag()
                }
                Text("Feeling and energy curves based on the entries this model supports.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink {
                    EffectModelExplainerView()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "function")
                            .imageScale(.small)
                        Text("How this works")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, Spacing.xxs)
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
            HStack(alignment: .top, spacing: Spacing.lg) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.cautionAccent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("A busy session")
                        .sectionLabel()
                    Text("Estimates become less reliable as more entries and substances are combined.")
                        .captionSecondary()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, Spacing.xxs)
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
                interactive: true,
                startFramed: true,
            )
            .frame(height: chartHeight)
            .listRowInsets(EdgeInsets(top: 4, leading: 0.5, bottom: 4, trailing: 0.5))
            .listRowSeparator(.hidden)
            .listRowBackground(CardBackground())

        } header: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: lens.symbol)
                    .foregroundStyle(lens.color)
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text(lens.label)
                    .sectionLabel()
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }
        }
    }

    // MARK: Bottom — coverage

    private var coverageSection: some View {
        detailCard("square.stack.3d.up", "What these curves cover") {
            if !ignored.isEmpty {
                Text(coverageText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("The model is calibrated on five stimulants: amphetamine, methylphenidate, mephedrone, 3-MMC, and 2-MMC. Other substances shape the curves through how they interact with these. Opioids are read through their dopamine activity, mostly to show those interactions.")
                .fixedSize(horizontal: false, vertical: true)
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

    private var readingSection: some View {
        detailCard("checkmark.seal", "Reading the estimate") {
            Text("Model estimates, not measurements of your response.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Compare the shape of a curve more than its exact height.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A labeled card with its body always visible: the label row styled like a
    /// disclosure header, the body in secondary subheadline text beneath it.
    private func detailCard(_ icon: String, _ title: LocalizedStringKey, @ViewBuilder body: () -> some View) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label {
                    Text(title)
                        .sectionLabel()
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: icon)
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    body()
                }
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
            }
            .padding(.vertical, Spacing.xxs)
            .listRowBackground(CardBackground())
        }
    }
}

/// Describes the assumptions behind the two session estimates.
struct EffectModelExplainerView: View {
    var body: some View {
        List {
            Section("Feeling") {
                Text("The model combines estimated stimulant, serotonin and opioid effects with an adaptation term. It uses changes in modeled dopamine activity to approximate the shape of the curve.")
            }
            Section("Energy") {
                Text("The model combines estimated activating and sedating effects over time.")
            }
            Section("Limitations") {
                Text("These curves illustrate model assumptions. They do not measure your feelings, energy, impairment or physical safety. Individual responses and combinations may differ substantially.")
                Text("Use your check-ins to record how you actually felt. Follow prescribed directions and consult a qualified healthcare professional before making medical decisions.")
            }
        }
        .insetGroupedListStyle()
        .skinBackdrop()
        .navigationTitle("How this works")
    }
}
