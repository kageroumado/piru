import SwiftUI

/// The calculation behind the effect curves, stage by stage.
///
/// The shipped explainer (``EffectModelExplainerView``) gives the intuition — the
/// dopamine-versus-expectation gap — and stops there. This goes the rest of the
/// way: what is actually integrated, in what order, with the real names for it.
/// Someone opening the tool sees a curve appear out of nowhere; the point of this
/// screen is that they can follow the reasoning from their dose to that line even
/// if they can't evaluate every step.
///
/// Every claim here is checked against `EffectEngine.simulate` and
/// `SubstanceModelDatabase.params` rather than the specs, which have drifted
/// (`homeostatic-effect-model.md` is explicitly unported, and the constants table
/// in `effect-model-system-reference.md` §2.5 no longer matches the code).
struct EffectPipelineExplainerView: View {
    var body: some View {
        List {
            Section {
                Text("Every curve starts as a number you typed and ends as a line on a chart. These are the steps in between.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 8, trailing: 4))
            }

            stage(
                number: 1,
                title: "From dose to concentration",
                symbol: "drop",
                paragraphs: [
                    "Your dose is first expressed as a multiple of that substance's reference dose — the amount the model was tuned around. It then moves through a three-stage absorption chain into a central compartment that clears by first-order elimination, using an absorption rate (ka) and an elimination rate (ke) derived from the measured half-life and time to peak.",
                    "Route changes how steeply the curve rises, and whether the drug redistributes into a peripheral compartment — not how high it peaks. An insufflated and an oral dose of the same size reach the same peak here. What differs is the slope, and the later stages are sensitive to slope.",
                ],
            )

            stage(
                number: 2,
                title: "From concentration to target engagement",
                symbol: "target",
                paragraphs: [
                    "Concentration becomes fractional occupancy of the dopamine, noradrenaline and serotonin transporters. The dopamine transporter gets a time-resolved binding equation — separate association and dissociation rates rather than instant equilibrium — so a drug that lets go slowly holds its occupancy plateau after concentration has begun to fall.",
                    "The DAT:NET:SERT potency ratios are taken from one published assay, chosen by coverage and confidence, never mixed across labs. Only ratios measured in the same experiment are physically comparable.",
                    "Everything present draws on one shared pool of free transporters, so a second substance finds fewer sites open. This is the point where combinations stop being additive.",
                ],
            )

            stage(
                number: 3,
                title: "Releasers and reuptake blockers diverge",
                symbol: "arrow.triangle.branch",
                paragraphs: [
                    "A releaser's output is limited by the vesicular dopamine still in store, and is suppressed further if a reuptake blocker is also on board. A blocker is not store-limited — it raises dopamine by slowing clearance rather than by pushing transmitter out. The two are handled by different code paths, not by one shared knob.",
                ],
            )

            stage(
                number: 4,
                title: "What you feel is a gap, not a level",
                symbol: "arrow.up.and.down",
                paragraphs: [
                    "Two internal compensation signals chase the drug-driven dopamine elevation: a fast one that settles within minutes (autoreceptor feedback, transporter trafficking) and a slow one over hours (synthesis regulation). The felt effect is modeled as the distance between dopamine and those expectations — never the dopamine level itself.",
                    "The fast gap is the rush. Because the fast signal catches up within minutes, that gap is effectively proportional to how quickly dopamine rose. The slow gap is the high while it stays positive; once the slow expectation overshoots the falling dopamine, the same term turns into part of the comedown.",
                ],
            )

            stage(
                number: 5,
                title: "Reward is gated by rate",
                symbol: "speedometer",
                paragraphs: [
                    "Reward is multiplied by a gate that integrates how fast dopamine is rising. A substance can occupy the transporter fully and still register almost no reward if it arrived slowly — the same pharmacology reading as therapeutic or as euphoric depending on speed alone.",
                ],
            )

            stage(
                number: 6,
                title: "Depletion, and where the comedown comes from",
                symbol: "battery.25",
                paragraphs: [
                    "Releasers spend vesicular stores in proportion to concentration, and dopamine elevation itself throttles resynthesis — so the debt deepens while the drug is still on board rather than being repaid in real time.",
                    "Past a threshold that debt switches on a comedown term, which then recovers with accelerating synthesis over hours. Serotonin activity cushions it. That is why an amphetamine crash and a cathinone's calmer return separate so sharply in these curves.",
                    "The comedown here is over-compensation plus a depletion debt — not dopamine falling below baseline.",
                ],
            )

            stage(
                number: 7,
                title: "The four readouts",
                symbol: "chart.xyaxis.line",
                paragraphs: [
                    "Feeling sums reward, serotonin and opioid warmth, and liking, minus the comedown.",
                    "Energy is a noradrenaline-led inverted U set against its own adaptation, minus sedative load. Past a point, more noradrenergic drive lowers functional energy instead of adding to it.",
                    "Compulsion sums a slowly-decaying incentive envelope that charges from the rate of rise, and the gap between the rush you remember and the rush you are getting now.",
                    "Strain sums a noradrenergic cardiovascular term drawing on a depletable vasoconstriction pool, plus an opioid respiratory term. It deliberately follows concentration rather than the felt gap, so it stays elevated after the effect itself has faded.",
                ],
            )

            stage(
                number: 8,
                title: "How it is solved",
                symbol: "function",
                paragraphs: [
                    "All of it is a set of coupled differential equations advanced by forward Euler in half-minute steps across twelve hours or more.",
                    "Every substance shares one set of neural constants. Only the store-depletion susceptibility is fitted per substance, anchored to the observed contrast between an amphetamine crash and a crashless cathinone.",
                ],
            )

            limitationsSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Step by step")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stage(
        number: Int,
        title: LocalizedStringKey,
        symbol: String,
        paragraphs: [LocalizedStringKey],
    ) -> some View {
        Section {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(CardBackground())
        } header: {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .foregroundStyle(Theme.accent)
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text("\(number). \(Text(title))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }
        }
    }

    /// Stated as plainly as the mechanism. A model that lists what it can't see is
    /// easier to trust — and every one of these is a real, checkable absence in
    /// the engine rather than a hedge.
    private var limitationsSection: some View {
        Section {
            Text("No tolerance between sessions. Every simulation starts from a naive baseline; acclimation within the session is modeled, carry-over from yesterday is not.")
            Text("No body weight, bioavailability or volume of distribution. Concentration here is dimensionless and relative to a reference dose, not a measured blood level.")
            Text("No genetics, no metabolizer phenotype, and no drug–drug metabolic interaction. Interactions are pharmacodynamic only: shared transporters, shared stores, shared receptors.")
            Text("No individual variability. The same inputs always give the same curve, and no confidence band is drawn around it.")
            Text("Psychedelics, dissociatives and cannabinoids are out of scope — pharmacokinetics is not what drives their effects.")
        } header: {
            HStack(spacing: 7) {
                Image(systemName: "eye.slash")
                    .foregroundStyle(Theme.accent)
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text("What this does not model")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }
        } footer: {
            Text("A rough guide, not medical advice.")
        }
        .font(.subheadline)
        .listRowBackground(CardBackground())
    }
}
