import SwiftUI

/// The tool's reasoning, laid open: how to read the curves, the mechanism story
/// the session screen already tells, and — per substance actually in play — the
/// measured pharmacology and the derived engine inputs built from it.
///
/// Showing the numbers matters even for a reader who can't evaluate them. A curve
/// with no visible provenance is an oracle; the same curve with its half-life,
/// Tmax, transporter weights and confidence grades attached is a claim you can
/// follow, check, and disagree with.
struct SandboxGuideSheet: View {
    let model: EffectSandboxModel

    @Environment(\.dismiss) private var dismiss
    @State private var glossaryTopic: PharmacologyGlossarySheet.Topic?

    /// Distinct (substance, route) pairs currently feeding a curve — the exact set
    /// the engine resolved parameters for.
    private var substancesInPlay: [EffectSandboxModel.Row] {
        var seen = Set<String>()
        return model.rows.filter { row in
            guard let substance = row.substance, row.amount > 0 else { return false }
            return seen.insert("\(substance.name)|\(row.route.rawValue)").inserted
        }
    }

    var body: some View {
        NavigationStack {
            List {
                readingSection
                mechanismSection
                coverageSection
                ForEach(substancesInPlay) { row in
                    ParameterSection(row: row, onGlossary: { glossaryTopic = $0 })
                }
            }
            .themedPage()
            .navigationTitle("How this is estimated")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark").font(.body.weight(.semibold))
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accent)
                    .accessibilityLabel(Text("Done"))
                }
            }
            .sheet(item: $glossaryTopic) { PharmacologyGlossarySheet(topic: $0) }
        }
    }

    private var readingSection: some View {
        Section {
            Text("See how doses might feel over time — compare two meds, preview a stack, or change the timing — without logging anything. This is a scratch surface; nothing here touches your journal.")
            Text("This shows what the model predicts about the shape and sign of an effect — not what you should take. It is an estimate from typical pharmacology, never a recommendation or a safe-dose guide.")
            Text("Compare the shape of a curve more than its exact height.")
            Text("Your own response shifts with tolerance, body chemistry, and the day. Talk to a prescriber about your medication.")
        } header: {
            Text("Reading these estimates")
        } footer: {
            Text("A rough guide, not medical advice.")
        }
        .listRowBackground(CardBackground())
    }

    /// Two depths, in order: the intuition (the session screen's own explainer, so
    /// there is one account of the model rather than two that drift), then the
    /// full pipeline for anyone who wants to check the reasoning.
    private var mechanismSection: some View {
        Section {
            NavigationLink {
                EffectModelExplainerView()
            } label: {
                Label("How this works", systemImage: "function")
            }
            NavigationLink {
                EffectPipelineExplainerView()
            } label: {
                Label("The calculation, step by step", systemImage: "list.number")
            }
        } footer: {
            Text("The idea first, then every stage from your dose to the line on the chart.")
        }
        .listRowBackground(CardBackground())
    }

    private var coverageSection: some View {
        Section {
            Text("The model is calibrated on five stimulants: amphetamine, methylphenidate, mephedrone, 3-MMC, and 2-MMC. Other substances shape the curves through how they interact with these. Opioids are read through their dopamine activity, mostly to show those interactions.")
            Text("Confidence varies by substance. Well-studied ones like amphetamine and methylphenidate rest on firmer data than newer compounds.")
        } header: {
            Text("What these curves cover")
        }
        .listRowBackground(CardBackground())
    }
}

/// One substance's inputs: what was measured, and what the engine derived from it.
struct ParameterSection: View {
    let row: EffectSandboxModel.Row
    let onGlossary: (PharmacologyGlossarySheet.Topic) -> Void

    private var pharmacology: PharmacologyParameters? {
        guard let substance = row.substance else { return nil }
        return SubstanceStore.shared.pharmacologyParameters(forSubstanceName: substance.name)
    }

    private var engineParams: SubstanceModelParams? {
        guard let substance = row.substance else { return nil }
        return SubstanceModelDatabase.params(name: substance.name, pharmacology: pharmacology)
    }

    var body: some View {
        Section {
            if let pharmacology {
                measuredRows(pharmacology)
            }
            if let engineParams {
                derivedRows(engineParams)
            }
            if let targets = pharmacology?.targets, !targets.isEmpty {
                bindingRows(targets)
            }
            if pharmacology == nil, engineParams == nil {
                Text("No resolved pharmacology for this substance.")
                    .foregroundStyle(Theme.secondaryLabel)
            }
        } header: {
            HStack(spacing: Spacing.sm) {
                LegendDot(color: Color(hex: row.colorHex))
                Text(verbatim: row.displayName)
                Text(row.route.localizedName)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .textCase(nil)
        } footer: {
            if let tier = pharmacology?.occupancyConfidence {
                HStack(spacing: Spacing.sm) {
                    Text("Weakest input")
                    ConfidenceBadge(tier: tier)
                }
            }
        }
        .listRowBackground(CardBackground())
    }

    // MARK: Measured

    @ViewBuilder
    private func measuredRows(_ parameters: PharmacologyParameters) -> some View {
        Button {
            onGlossary(.pharmacokinetics)
        } label: {
            LabeledContent {
                Image(systemName: "info.circle")
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            } label: {
                Text("Measured pharmacokinetics")
                    .sectionLabel()
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        if let halfLife = parameters.halfLifeMinutes {
            LabeledContent("Half-life (t½)", value: Self.duration(minutes: halfLife))
        }
        if let tmax = parameters.tmaxMinutes {
            LabeledContent("Time to peak (Tmax)", value: Self.duration(minutes: tmax))
        }
        if let bioavailability = parameters.bioavailabilityFraction {
            LabeledContent("Bioavailability (F)", value: "\(Int((bioavailability * 100).rounded()))%")
        }
        if let vd = parameters.vdLPerKg {
            LabeledContent("Distribution (Vd)", value: "\(vd.doseFormatted) L/kg")
        }
        if let reference = parameters.referenceDoseMg {
            LabeledContent("Reference dose", value: "\(reference.doseFormatted) mg")
        }
        if let species = parameters.pkSpecies, species.lowercased() != "human" {
            LabeledContent("Species", value: species.capitalized)
        }
    }

    // MARK: Derived

    /// The literal values handed to the simulation. `ka` in particular is derived,
    /// not measured — from Tmax when there is one, else a fixed multiple of `ke` —
    /// and saying so is the difference between a figure and a guess.
    @ViewBuilder
    private func derivedRows(_ params: SubstanceModelParams) -> some View {
        Text("What the engine uses")
            .sectionLabel()
        LabeledContent("Elimination rate (ke)", value: "\(params.ke.doseFormatted) /h")
        LabeledContent("Absorption rate (ka)", value: "\(params.ka.doseFormatted) /h")
        // Distinct from the DB's measured reference above: this is the curated
        // anchor the calibrated magnitudes were fitted against.
        LabeledContent("Model anchor dose", value: "\(params.refUnit.doseFormatted) \(row.unit)")
        if params.wDAT > 0 || params.wNET > 0 || params.wSERT > 0 {
            LabeledContent("Transporter weights", value: "DAT \(params.wDAT.doseFormatted) · NET \(params.wNET.doseFormatted) · SERT \(params.wSERT.doseFormatted)")
            LabeledContent("Mechanism", value: params.releaser ? String(localized: "Releaser") : String(localized: "Reuptake blocker"))
        }
        if params.mu > 0 {
            LabeledContent("µ-opioid drive", value: params.mu.doseFormatted)
        }
        if params.gaba > 0 {
            LabeledContent("GABA-A drive", value: params.gaba.doseFormatted)
        }
    }

    // MARK: Binding

    @ViewBuilder
    private func bindingRows(_ targets: [PharmacologyParameters.TargetEngagement]) -> some View {
        Button {
            onGlossary(.receptor)
        } label: {
            LabeledContent {
                Image(systemName: "info.circle")
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            } label: {
                Text("Binding used")
                    .sectionLabel()
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        // The tightest few only: the whole table lives on the substance's own
        // Pharmacology card, and this is the subset that shaped these curves.
        ForEach(targets.prefix(5)) { target in
            LabeledContent {
                Text(verbatim: concentrationLabel(target))
                    .monospacedDigit()
            } label: {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(verbatim: target.target)
                    ProvenanceBadge(
                        confidence: target.confidence,
                        species: target.species,
                        sourceSlug: target.sourceSlug,
                    )
                }
            }
        }
    }

    private func concentrationLabel(_ target: PharmacologyParameters.TargetEngagement) -> String {
        switch target.kind {
        case .ki: concLabel(kiNm: target.halfMaxNanomolar, ec50Nm: nil, ic50Nm: nil)
        case .ec50: concLabel(kiNm: nil, ec50Nm: target.halfMaxNanomolar, ic50Nm: nil)
        case .ic50: concLabel(kiNm: nil, ec50Nm: nil, ic50Nm: target.halfMaxNanomolar)
        }
    }

    private static func duration(minutes: Double) -> String {
        minutes < 90
            ? String(localized: "\(Int(minutes.rounded())) min")
            : String(localized: "\((minutes / 60).doseFormatted) h")
    }
}
