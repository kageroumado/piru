import Charts
import SwiftData
import SwiftUI

/// Tools-tab screen projecting serum hormone levels from injectable ester doses,
/// calibrated to the user's own lab results (Specs/injection-levels-tool.md).
/// Reachable via `PushRoute.tool(.injectionLevels)`.
///
/// Log-first: it reads qualifying IM/SC estradiol/testosterone doses from the dose
/// log and draws immediately, falling back to a manual schedule when the log has
/// none. It predicts a concentration — never a dose or a level to aim for.
struct InjectionLevelsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DoseEntry.timestamp) private var doseEntries: [DoseEntry]
    @Query(sort: \LabMeasurement.date) private var labs: [LabMeasurement]

    @State private var model = InjectionLevelsModel()
    @State private var showingAddLab = false

    // Durable calibration preferences, mirrored into the model each session (the
    // model is the live source during a session; these persist it across launches).
    @AppStorage("injLevelsPersonalMultiplier") private var storedMultiplier = 1.0
    @AppStorage("injLevelsAutoCalibrate") private var storedAutoCalibrate = true
    @AppStorage("injLevelsFitRates") private var storedFitRates = true

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if model.availableEsters.isEmpty {
                    InjectionLevelsNoDataCard()
                } else {
                    InjectionLevelsInputSection(model: model)

                    if let result = model.result, let ester = model.selectedEster {
                        DepotCurveCard(
                            result: result,
                            analyte: model.analyte,
                            referenceLow: model.referenceLow,
                            referenceHigh: model.referenceHigh,
                        )
                        InjectionLevelsMetricsCard(result: result, analyte: model.analyte)
                        LabCalibrationSection(
                            model: model, labs: analyteLabs, ester: ester,
                            onAdd: { showingAddLab = true },
                            onToggleExclude: toggleExclude, onDelete: deleteLab,
                        )
                        InjectionLevelsProvenanceCard(ester: ester, analyte: model.analyte)
                    }
                    InjectionLevelsExplanationCard()
                }
            }
            .padding()
        }
        .background(Theme.background)
        .task {
            await SubstanceStore.shared.ensureAllLoaded()
            model.personalMultiplier = storedMultiplier
            model.autoCalibrateFromLabs = storedAutoCalibrate
            model.fitRates = storedFitRates
            model.selectDefaultsIfNeeded()
            syncAndRefresh()
        }
        .onChange(of: model.recomputeKey) { model.refresh() }
        .onChange(of: model.analyte) { model.selectDefaultsIfNeeded(); syncAndRefresh() }
        .onChange(of: doseEntries.count) { syncAndRefresh() }
        .onChange(of: labs.count) { syncAndRefresh() }
        .onChange(of: model.personalMultiplier) { storedMultiplier = model.personalMultiplier }
        .onChange(of: model.autoCalibrateFromLabs) { storedAutoCalibrate = model.autoCalibrateFromLabs }
        .onChange(of: model.fitRates) { storedFitRates = model.fitRates }
        .sheet(isPresented: $showingAddLab) {
            AddLabResultSheet(analyte: model.analyte, ester: model.selectedEster) { measurement in
                modelContext.insert(measurement)
                try? modelContext.save()
                syncAndRefresh()
            }
        }
    }

    // MARK: - Sync

    private var analyteLabs: [LabMeasurement] {
        labs.filter { $0.analyteKey == model.analyte.key }
    }

    private func syncAndRefresh() {
        let injections = InjectionLevelsView.injections(from: doseEntries, analyte: model.analyte)
        let measurements = analyteLabs
            .filter { !$0.excludedFromCalibration }
            .map { DepotCalibration.Measurement(date: $0.date, value: $0.value) }
        let preferred = InjectionLevelsView.dominantEsterID(from: doseEntries, analyte: model.analyte)
        model.sync(injections: injections, measurements: measurements, preferredEsterID: preferred)
        model.selectDefaultsIfNeeded()
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

    /// Pull qualifying injections from the dose log for an analyte: IM/SC route, a
    /// substance in the analyte's PSID family, and a mg-convertible dose unit.
    static func injections(from entries: [DoseEntry], analyte: Analyte) -> [(date: Date, doseMg: Double)] {
        let store = SubstanceStore.shared
        let familyUIDs = Set(store.estersForAnalyte(analyte.key).compactMap(\.parentUID))
        guard !familyUIDs.isEmpty else { return [] }
        var out: [(date: Date, doseMg: Double)] = []
        for entry in entries {
            guard entry.route == .intramuscular || entry.route == .subcutaneous else { continue }
            let uid = entry.substanceUID ?? store.substanceUID(forNameOrAlias: entry.substance)
            guard let uid, familyUIDs.contains(uid) else { continue }
            guard let scale = DoseEquivalent.milligramScale(ofDoseUnit: entry.unit) else { continue }
            let mg = entry.amount * scale
            guard mg > 0 else { continue }
            out.append((entry.timestamp, mg))
        }
        return out
    }

    /// The modelable ester the user logs most for `analyte`, from the ester named on
    /// their qualifying doses' `saltForm` — the log-first default ester. `nil` when
    /// no logged dose names a modelable ester (→ fall back to the first ester).
    static func dominantEsterID(from entries: [DoseEntry], analyte: Analyte) -> String? {
        let store = SubstanceStore.shared
        let esters = store.estersForAnalyte(analyte.key) // modelable only
        let familyUIDs = Set(esters.compactMap(\.parentUID))
        guard !familyUIDs.isEmpty else { return nil }
        var counts: [String: Int] = [:] // esterID → times logged
        for entry in entries {
            guard entry.route == .intramuscular || entry.route == .subcutaneous else { continue }
            let uid = entry.substanceUID ?? store.substanceUID(forNameOrAlias: entry.substance)
            guard let uid, familyUIDs.contains(uid), let label = entry.saltForm else { continue }
            guard let esterID = esters.first(where: { $0.label == label && $0.parentUID == uid })?.esterID else { continue }
            counts[esterID, default: 0] += 1
        }
        // Most-logged wins; ties break on esterID for a stable default.
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.first?.key
    }
}

// MARK: - Input

private struct InjectionLevelsInputSection: View {
    @Bindable var model: InjectionLevelsModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            if model.availableEsters.count > 0, SubstanceStore.shared.analytesWithEsterData().count > 1 {
                Picker("Hormone", selection: $model.analyte) {
                    ForEach(analytes) { a in Text(a.displayName).tag(a) }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Ester")
                    .captionSecondary()
                Picker("Ester", selection: $model.selectedEsterID) {
                    ForEach(model.availableEsters) { ester in
                        Text(ester.label).tag(Optional(ester.esterID))
                    }
                }
                .pickerStyle(.segmented)
            }

            if model.hasLogHistory {
                Picker("Source", selection: $model.useLogHistory) {
                    Text("From your log").tag(true)
                    Text("Manual schedule").tag(false)
                }
                .pickerStyle(.segmented)
            }

            if model.useLogHistory, model.hasLogHistory {
                Text("\(model.loggedInjections.count) injections from your log")
                    .captionSecondary()
            } else {
                HStack(spacing: Spacing.xl) {
                    labeledField(String(localized: "Dose each time"), value: $model.doseMg, unit: "mg")
                    labeledField(String(localized: "Every"), value: $model.intervalDays, unit: String(localized: "days"))
                }
            }
        }
        .padding()
        .themeCard()
    }

    private var analytes: [Analyte] {
        Analyte.allCases.filter { SubstanceStore.shared.analytesWithEsterData().contains($0.key) }
    }

    private func labeledField(_ label: String, value: Binding<Double?>, unit: String) -> some View {
        VStack(alignment: .leading) {
            Text(label).captionSecondary()
            HStack(spacing: 0) {
                TextField(label, value: value, format: .number)
                    .decimalKeyboard()
                    .padding(Spacing.md)
                Divider().frame(height: 20)
                Text(unit)
                    .foregroundStyle(Theme.secondaryLabel)
                    .padding(Spacing.md)
            }
            .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.input))
        }
    }
}

// MARK: - Chart

private struct DepotCurveCard: View {
    let result: DepotCurveResult
    let analyte: Analyte
    let referenceLow: Double?
    let referenceHigh: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Estimated \(String(localized: analyte.displayName)) level")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
            Chart {
                ForEach(Array(result.points.enumerated()), id: \.offset) { _, point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Low", point.bandLow),
                        yEnd: .value("High", point.bandHigh),
                    )
                    .foregroundStyle(Theme.accent.opacity(Theme.Opacity.tint))
                    .interpolationMethod(.catmullRom)
                }
                ForEach(Array(result.points.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Date", point.date), y: .value("Level", point.level))
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                }
                ForEach(Array(result.injectionDates.enumerated()), id: \.offset) { _, date in
                    RuleMark(x: .value("Injection", date))
                        .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.dimmed))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
                if let low = referenceLow {
                    RuleMark(y: .value("Reference low", low))
                        .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.muted))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
                if let high = referenceHigh {
                    RuleMark(y: .value("Reference high", high))
                        .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.muted))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
                RuleMark(x: .value("Now", Date.now))
                    .foregroundStyle(Theme.accent.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .frame(height: 220)
            .chartYAxisLabel(analyte.canonicalUnit)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.dimmed))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(.caption2)
                }
            }
            .chartSummaryAccessibility(
                label: Text("Estimated level over time"),
                value: Text(String(localized: "Ranges from about \(Int(result.trough.rounded())) to \(Int(result.peak.rounded())) \(analyte.canonicalUnit) across the cycle")),
            )
        }
        .padding()
        .themeCard()
    }
}

// MARK: - Metrics

private struct InjectionLevelsMetricsCard: View {
    let result: DepotCurveResult
    let analyte: Analyte

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.xl) {
            metricTile(
                key: String(localized: "Estimated trough"),
                value: format(result.trough),
                sub: String(localized: "\(format(result.troughLow))–\(format(result.troughHigh)) \(analyte.canonicalUnit)"),
            )
            metricTile(
                key: String(localized: "Estimated peak"),
                value: format(result.peak),
                sub: String(localized: "\(format(result.peakLow))–\(format(result.peakHigh)) \(analyte.canonicalUnit)"),
            )
            if let tir = result.timeInRange {
                metricTile(
                    key: String(localized: "Time in range"),
                    value: "\(Int((tir * 100).rounded()))%",
                    sub: String(localized: "of the cycle, between your lines"),
                )
            }
        }
        .padding()
        .themeCard()
    }

    private func format(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(v < 10 ? 1 : 0)))
    }

    private func metricTile(key: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(key)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
                .textCase(.uppercase)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text(sub)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.xl)
        .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
    }
}

// MARK: - Explanation / no-data

private struct InjectionLevelsExplanationCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("An injected ester releases slowly from an oil depot, is cleaved to the free hormone, then cleared. This curve models that from your doses.")
                .captionSecondary()
            Text("It estimates a level from doses you enter — it never recommends a dose or a level to aim for. Add lab results to calibrate it to you.")
                .captionSecondary()
            Text("Population curves scatter widely between people, so uncalibrated numbers are a starting point, not a reading. A blood test pins the height to you; two on different days pin the shape as well. Retesting after any change — dose, ester, interval, injection site — keeps the fit honest, because one measurement can't tell a high peak from a slow decline.")
                .captionSecondary()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .themeCard()
    }
}

private struct InjectionLevelsNoDataCard: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "syringe")
                .font(.title2)
                .foregroundStyle(Theme.secondaryLabel)
                .accessibilityHidden(true)
            Text("Injectable ester data isn't available in this build.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .themeCard()
    }
}
