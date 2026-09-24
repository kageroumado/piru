import Charts
import SwiftData
import SwiftUI

/// The first-class "Hormone Levels" insight (Specs/injection-levels-v3.md §1–§3):
/// the estimated **serum** hormone (estradiol or testosterone) the user's logged
/// injections release, summed per ester and calibrated to their own labs. Purely
/// retrospective → now → a short projection; the prediction Tool
/// (`Tool.injectionLevels`) keeps the hypothetical "if I start now" reasoning.
///
/// It shows a row per analyte the user actually logs an ester for. It estimates a
/// level; it never suggests a dose or a target — reference lines are the user's own.
struct HormoneLevelsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DoseEntry.timestamp) private var doseEntries: [DoseEntry]
    @Query(sort: \LabMeasurement.date) private var labs: [LabMeasurement]

    @State private var model = HormoneLevelsModel()
    @State private var showingAddLab = false
    @State private var addingCompanion: CompanionMeasurement?

    @AppStorage(InjectionLevelsModel.StorageKey.personalMultiplier) private var storedMultiplier = 1.0
    @AppStorage(InjectionLevelsModel.StorageKey.autoCalibrate) private var storedAutoCalibrate = true
    @AppStorage(InjectionLevelsModel.StorageKey.fitRates) private var storedFitRates = true
    @AppStorage(InjectionLevelsModel.StorageKey.volumeConcentration(.estradiol)) private var storedEstradiolConcentration = 0.0
    @AppStorage(InjectionLevelsModel.StorageKey.volumeConcentration(.testosterone)) private var storedTestosteroneConcentration = 0.0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if loggedAnalytes.isEmpty {
                    HormoneLevelsNoDataCard()
                } else {
                    if loggedAnalytes.count > 1 {
                        Picker("Hormone", selection: $model.analyte) {
                            ForEach(loggedAnalytes) { a in Text(a.displayName).tag(a) }
                        }
                        .pickerStyle(.segmented)
                    }

                    if !cautions.isEmpty {
                        EsterCautionCard(cautions: cautions)
                    }

                    if let result = model.result {
                        SerumCurveCard(model: model, result: result)
                        InjectionLevelsMetricsCard(result: result, analyte: model.analyte)
                        if model.perEster.count > 1 {
                            AssumedDepotLevelsCard(analyte: model.analyte, perEster: model.perEster)
                        }
                    }

                    if !model.catalogMarkers.isEmpty {
                        CatalogEsterNote(markers: model.catalogMarkers)
                    }

                    ForEach(visibleCompanions) { companion in
                        CompanionSeriesCard(
                            measurement: companion,
                            points: companionPoints(companion),
                            onAdd: { addingCompanion = companion },
                        )
                    }

                    HormoneLabCalibrationCard(
                        model: model,
                        labs: analyteLabs,
                        onAdd: { showingAddLab = true },
                        onToggleExclude: toggleExclude,
                        onDelete: deleteLab,
                    )

                    HormoneLevelsProvenanceCard(analyte: model.analyte, esters: model.perEster.map(\.ester))
                    HormoneLevelsExplanationCard(analyte: model.analyte)
                }
            }
            .padding()
        }
        .skinBackdrop()
        .task {
            await SubstanceStore.shared.ensureAllLoaded()
            model.personalMultiplier = storedMultiplier
            model.autoCalibrateFromLabs = storedAutoCalibrate
            model.fitRates = storedFitRates
            if loggedAnalytes.count == 1, let only = loggedAnalytes.first { model.analyte = only }
            syncAndRefresh()
        }
        .onChange(of: model.recomputeKey) { model.refresh() }
        .onChange(of: model.analyte) { syncAndRefresh() }
        .onChange(of: doseEntries.count) { syncAndRefresh() }
        .onChange(of: labs.count) { syncAndRefresh() }
        .onChange(of: model.personalMultiplier) { storedMultiplier = model.personalMultiplier }
        .onChange(of: model.autoCalibrateFromLabs) { storedAutoCalibrate = model.autoCalibrateFromLabs }
        .onChange(of: model.fitRates) { storedFitRates = model.fitRates }
        .sheet(isPresented: $showingAddLab) {
            AddLabResultSheet(analyte: model.analyte, ester: nil) { measurement in
                modelContext.insert(measurement)
                try? modelContext.save()
                syncAndRefresh()
            }
        }
        .sheet(item: $addingCompanion) { companion in
            AddCompanionMeasurementSheet(measurement: companion) { measurement in
                modelContext.insert(measurement)
                try? modelContext.save()
            }
        }
    }

    // MARK: - Companion measured series

    /// The companion axes to show for the active analyte: always the primary ones,
    /// plus hemoglobin only once it has a point (it rides on the same panel as Hct).
    private var visibleCompanions: [CompanionMeasurement] {
        CompanionMeasurement.companions(for: model.analyte).filter { companion in
            companion != .hemoglobin || !companionPoints(companion).isEmpty
        }
    }

    private func companionPoints(_ companion: CompanionMeasurement) -> [(date: Date, value: Double)] {
        labs.filter { $0.analyteKey == companion.analyteKey }
            .sorted { $0.date < $1.date }
            .map { (date: $0.date, value: $0.value) }
    }

    // MARK: - Sync

    /// The analytes the user has logged an injectable ester for — the rows to show.
    private var loggedAnalytes: [Analyte] {
        Analyte.allCases.filter { analyte in
            guard SubstanceStore.shared.analytesWithEsterData().contains(analyte.key) else { return false }
            let grouped = HormoneLevelsLog.grouped(
                from: doseEntries, analyte: analyte,
                volumeConcentrationMgPerML: concentration(for: analyte),
            )
            return grouped.hasModelableInjections || grouped.volumeLoggedCount > 0 || !grouped.catalogOnlyMarkers.isEmpty
        }
    }

    private var analyteLabs: [LabMeasurement] {
        labs.filter { $0.analyteKey == model.analyte.key }
    }

    /// Distinct safety cautions from any ester the user has logged for this analyte.
    private var cautions: [String] {
        let esters = model.perEster.map(\.ester) + model.catalogMarkers.map(\.ester)
        var seen = Set<String>()
        var out: [String] = []
        for ester in esters {
            guard let caution = ester.caution, seen.insert(ester.esterID).inserted else { continue }
            out.append(caution)
        }
        return out
    }

    private func concentration(for analyte: Analyte) -> Double? {
        let stored = switch analyte {
        case .estradiol: storedEstradiolConcentration
        case .testosterone: storedTestosteroneConcentration
        }
        return stored > 0 ? stored : nil
    }

    private func syncAndRefresh() {
        let grouped = HormoneLevelsLog.grouped(
            from: doseEntries, analyte: model.analyte,
            volumeConcentrationMgPerML: concentration(for: model.analyte),
        )
        let measurements = analyteLabs
            .filter { !$0.excludedFromCalibration }
            .map { DepotCalibration.Measurement(date: $0.date, value: $0.value) }
        model.sync(grouped: grouped, measurements: measurements)
        model.refresh()
    }

    private func toggleExclude(_ lab: LabMeasurement) {
        lab.excludedFromCalibration.toggle()
        try? modelContext.save()
        syncAndRefresh()
    }

    private func deleteLab(_ lab: LabMeasurement) {
        modelContext.delete(lab)
        try? modelContext.save()
        syncAndRefresh()
    }
}

// MARK: - Serum curve

private struct SerumCurveCard: View {
    @Bindable var model: HormoneLevelsModel
    let result: DepotCurveResult

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            DepotCurveChart(
                result: result,
                analyte: model.analyte,
                referenceLow: model.referenceLow,
                referenceHigh: model.referenceHigh,
                chartRange: $model.chartRange,
                pinchVisibleDays: $model.pinchVisibleDays,
                title: serumTitle,
                referenceBand: model.analyte.referenceRegion,
            )
            if model.analyte.referenceRegion != nil {
                Text("Shaded: the 300–1000 ng/dL male reference range (FDA label; Wang 2010). A reference, not a target.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .padding()
        .themeCard()
    }

    private var serumTitle: LocalizedStringResource {
        switch model.analyte {
        case .estradiol: "Estimated serum estradiol"
        case .testosterone: "Estimated serum testosterone"
        }
    }
}

// MARK: - Assumed depot levels (per ester)

/// One series per logged ester — the assumed depot contribution each ester makes,
/// distinct from the serum sum above, so a switch or a mix reads honestly instead of
/// being flattened to one dominant ester (Specs/injection-levels-v3.md §3).
private struct AssumedDepotLevelsCard: View {
    let analyte: Analyte
    let perEster: [(ester: EsterPKRecord, points: [DepotCurveResult.Point])]

    static let palette: [Color] = [Theme.accent, .teal, .orange, .purple, .green]

    private struct EsterPoint: Identifiable {
        let id = UUID()
        let ester: String
        let date: Date
        let value: Double
    }

    private var flatPoints: [EsterPoint] {
        perEster.flatMap { series in
            series.points.map { EsterPoint(ester: series.ester.label, date: $0.date, value: $0.level) }
        }
    }

    private var domain: [String] {
        perEster.map(\.ester.label)
    }

    private var range: [Color] {
        perEster.indices.map { Self.palette[$0 % Self.palette.count] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Assumed depot levels")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
            Chart(flatPoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Level", point.value),
                )
                .foregroundStyle(by: .value("Ester", point.ester))
                .interpolationMethod(.catmullRom)
            }
            .chartForegroundStyleScale(domain: domain, range: range)
            .frame(height: 150)
            .chartYAxisLabel(analyte.canonicalUnit)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.dimmed))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(.caption2)
                }
            }
            Text("Each ester's own release, before they sum to the serum estimate above.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .padding()
        .themeCard()
    }
}

// MARK: - Ester caution

private struct EsterCautionCard: View {
    let cautions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(cautions, id: \.self) { caution in
                HStack(alignment: .top, spacing: Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(caution)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .themeCard()
    }
}

// MARK: - Catalog-only ester note

private struct CatalogEsterNote: View {
    let markers: [(ester: EsterPKRecord, date: Date)]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(Array(Set(markers.map(\.ester.esterID))).sorted(), id: \.self) { id in
                if let ester = markers.first(where: { $0.ester.esterID == id })?.ester {
                    let count = markers.filter { $0.ester.esterID == id }.count
                    Text("\(count) \(ester.label) injections logged. No serum curve is drawn for it — no validated release data.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .themeCard()
    }
}

// MARK: - Lab calibration

private struct HormoneLabCalibrationCard: View {
    @Bindable var model: HormoneLevelsModel
    let labs: [LabMeasurement]
    let onAdd: () -> Void
    let onToggleExclude: (LabMeasurement) -> Void
    let onDelete: (LabMeasurement) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                Text("Lab calibration")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                Spacer()
                calibrationChip
            }

            if labs.isEmpty {
                Text("Add a blood test to fit the curve to you. The band narrows.")
                    .captionSecondary()
            } else {
                ForEach(labs) { lab in
                    labRow(lab)
                }
            }

            Button(action: onAdd) {
                Label("Add lab result", systemImage: "plus.circle")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.small)

            Divider()
            CalibrationControl(model: model)
            ReferenceLinesEditor(model: model, unit: model.analyte.canonicalUnit)

            if let goal = model.analyte.labeledGoal {
                Button {
                    model.referenceLow = goal.lowerBound
                    model.referenceHigh = goal.upperBound
                } label: {
                    Text("Add the guideline reference range (\(Int(goal.lowerBound))–\(Int(goal.upperBound)) \(model.analyte.canonicalUnit))")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Theme.accent)
                Text("The Endocrine Society / WPATH SOC8 monitoring range for adults on masculinizing testosterone, drawn as reference lines. The range from your clinician or laboratory report takes precedence.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }

            drawTimingNote
        }
        .padding()
        .themeCard()
    }

    @ViewBuilder
    private var drawTimingNote: some View {
        switch model.analyte {
        case .testosterone:
            Text("A level only means something with its draw time: for cypionate and enanthate, measure midway between injections; for undecanoate, measure at trough, just before the next dose.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
        case .estradiol:
            Text("Note the time since your last injection when you draw — a peak and a trough tell different stories, and the curve reads both against your dose times.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    private var calibrationChip: some View {
        let count = labs.filter { !$0.excludedFromCalibration }.count
        let label = count == 0
            ? String(localized: "Uncalibrated")
            : count == 1 ? String(localized: "1 result") : String(localized: "Calibrated · \(count) results")
        return Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xxs)
            .background(
                (count == 0 ? Theme.secondaryLabel : Theme.accent).opacity(Theme.Opacity.tint),
                in: Capsule(),
            )
            .foregroundStyle(count == 0 ? Theme.secondaryLabel : Theme.accent)
    }

    private func labRow(_ lab: LabMeasurement) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(lab.date, format: .dateTime.year().month(.abbreviated).day())
                    .font(.subheadline)
                Text("\(model.analyte.fromCanonical(lab.value, to: lab.inputUnit).formatted(.number.precision(.fractionLength(1)))) \(lab.inputUnit)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer()
            Button {
                onToggleExclude(lab)
            } label: {
                Image(systemName: lab.excludedFromCalibration ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(lab.excludedFromCalibration ? Theme.secondaryLabel : Theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lab.excludedFromCalibration ? Text("Excluded from calibration") : Text("Included in calibration"))
        }
        .padding(.vertical, Spacing.xs)
        .swipeActions {
            Button(role: .destructive) { onDelete(lab) } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

// MARK: - Provenance

private struct HormoneLevelsProvenanceCard: View {
    let analyte: Analyte
    let esters: [EsterPKRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Sources")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
            ForEach(esters) { ester in
                VStack(alignment: .leading, spacing: 2) {
                    Text(ester.label)
                        .font(.caption.weight(.semibold))
                    Text(ester.provenance)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            Text("Older studies used radioimmunoassay; modern LC-MS/MS reads lower. Calibrating to your own results absorbs the difference.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .themeCard()
    }

    @ViewBuilder
    private var footer: some View {
        switch analyte {
        case .estradiol:
            Link(destination: URL(string: "https://github.com/WHSAH/estrannaise.js")!) {
                Text("Parameters from estrannaise.js (MIT), checked against the literature")
                    .font(.caption2)
            }
            .tint(Theme.accent)
            Link(destination: URL(string: "https://diyhrt.info/transfem/dosing/")!) {
                Text("More on injectable estradiol dosing (diyhrt.info)")
                    .font(.caption2)
            }
            .tint(Theme.accent)
        case .testosterone:
            Text("Testosterone ester curves are fit from label and primary-literature half-lives — there is no community PK simulator for them, so the band stays wide until your lab results calibrate the model.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }
}

// MARK: - Explanation / no-data

private struct HormoneLevelsExplanationCard: View {
    let analyte: Analyte

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("An injected ester releases slowly from the oil depot, splits into the free hormone, and clears. This curve sums your logged esters into an illustrative serum estimate. It is not a laboratory result.")
                .captionSecondary()
            Text("It estimates a level. It never suggests a dose or a target. Your lab results fit the model to your measurements, which doesn't establish accuracy between them. The reference lines are your own.")
                .captionSecondary()
            Text("Levels vary a lot between people, so an uncalibrated curve is a starting point, not a reading. Retest after any change in dose, ester, interval, or site.")
                .captionSecondary()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .themeCard()
    }
}

private struct HormoneLevelsNoDataCard: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "waveform.path.ecg")
                .font(.title2)
                .foregroundStyle(Theme.secondaryLabel)
                .accessibilityHidden(true)
            Text("Log an injectable estradiol or testosterone ester to see your estimated hormone levels here.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .themeCard()
    }
}
