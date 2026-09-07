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
    /// Vial strength for mL-logged injections, per analyte (`0` = unset).
    @AppStorage("injLevelsVolumeConcentration.estradiol") private var storedEstradiolConcentration = 0.0
    @AppStorage("injLevelsVolumeConcentration.testosterone") private var storedTestosteroneConcentration = 0.0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if model.availableEsters.isEmpty {
                    InjectionLevelsNoDataCard()
                } else {
                    InjectionLevelsInputSection(model: model)

                    if let result = model.result, let ester = model.selectedEster {
                        DepotCurveCard(
                            model: model,
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
            model.volumeConcentrationMgPerML = storedConcentration
            model.selectDefaultsIfNeeded()
            syncAndRefresh()
        }
        .onChange(of: model.recomputeKey) { model.refresh() }
        .onChange(of: model.analyte) {
            model.volumeConcentrationMgPerML = storedConcentration
            model.selectDefaultsIfNeeded()
            syncAndRefresh()
        }
        .onChange(of: model.volumeConcentrationMgPerML) {
            storedConcentration = model.volumeConcentrationMgPerML
            syncAndRefresh()
        }
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

    /// The persisted vial concentration for the active analyte; `nil` when unset.
    private var storedConcentration: Double? {
        get {
            let stored = switch model.analyte {
            case .estradiol: storedEstradiolConcentration
            case .testosterone: storedTestosteroneConcentration
            }
            return stored > 0 ? stored : nil
        }
        nonmutating set {
            switch model.analyte {
            case .estradiol: storedEstradiolConcentration = newValue ?? 0
            case .testosterone: storedTestosteroneConcentration = newValue ?? 0
            }
        }
    }

    private func syncAndRefresh() {
        let log = InjectionLevelsView.injections(
            from: doseEntries, analyte: model.analyte,
            volumeConcentrationMgPerML: model.volumeConcentrationMgPerML,
        )
        let measurements = analyteLabs
            .filter { !$0.excludedFromCalibration }
            .map { DepotCalibration.Measurement(date: $0.date, value: $0.value) }
        let preferred = InjectionLevelsView.dominantEsterID(from: doseEntries, analyte: model.analyte)
        model.sync(
            injections: log.injections,
            volumeLoggedCount: log.volumeLoggedCount,
            suggestedConcentration: log.latestLoggedConcentration,
            measurements: measurements,
            preferredEsterID: preferred,
        )
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

    /// What the dose log holds for an analyte: the injections the curve can use, how
    /// many more were logged in mL and await a vial concentration, and the
    /// concentration the user most recently logged a volumetric dose at.
    struct LogInjections {
        var injections: [(date: Date, doseMg: Double)] = []
        var volumeLoggedCount = 0
        var latestLoggedConcentration: Double?
    }

    /// Pull qualifying injections from the dose log for an analyte: IM/SC route and a
    /// substance in the analyte's PSID family. A dose in mg (or µg) joins as is; a
    /// dose logged in mL joins at `volumeConcentrationMgPerML`, and is only counted
    /// while that is unset.
    static func injections(
        from entries: [DoseEntry],
        analyte: Analyte,
        volumeConcentrationMgPerML: Double? = nil,
    ) -> LogInjections {
        let store = SubstanceStore.shared
        let familyUIDs = Set(store.estersForAnalyte(analyte.key).compactMap(\.parentUID))
        guard !familyUIDs.isEmpty else { return LogInjections() }
        var log = LogInjections()
        for entry in entries {
            guard entry.route == .intramuscular || entry.route == .subcutaneous else { continue }
            let uid = entry.substanceUID ?? store.substanceUID(forNameOrAlias: entry.substance)
            guard let uid, familyUIDs.contains(uid) else { continue }
            // A dose logged by volume × concentration keeps its mass in `amount`;
            // its concentration is the best default for the mL-only doses.
            if entry.volumeML != nil, let concentration = entry.abv, concentration > 0 {
                log.latestLoggedConcentration = concentration
            }
            let mg: Double
            if let scale = DoseEquivalent.milligramScale(ofDoseUnit: entry.unit) {
                mg = entry.amount * scale
            } else if Self.isVolumeUnit(entry.unit) {
                log.volumeLoggedCount += 1
                guard let concentration = volumeConcentrationMgPerML, concentration > 0 else { continue }
                mg = entry.amount * concentration
            } else {
                continue
            }
            guard mg > 0 else { continue }
            log.injections.append((entry.timestamp, mg))
        }
        return log
    }

    private static func isVolumeUnit(_ unit: String) -> Bool {
        let normalized = unit.trimmingCharacters(in: .whitespaces).lowercased()
        return normalized == "ml" || normalized == "cc"
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
            // A dose logged before esters moved onto `saltForm` names its ester in
            // the substance string ("Estradiol Enanthate").
            let label = entry.saltForm ?? store.saltForm(forNameOrAlias: entry.substance)
            guard let uid, familyUIDs.contains(uid), let label else { continue }
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

            if model.volumeLoggedInjectionCount > 0 {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    labeledField(String(localized: "Vial concentration"), value: $model.volumeConcentrationMgPerML, unit: "mg/mL")
                    if model.volumeConcentrationMgPerML ?? 0 > 0 {
                        Text("\(model.volumeLoggedInjectionCount) mL injections converted at this strength")
                            .captionSecondary()
                    } else {
                        Text("\(model.volumeLoggedInjectionCount) injections are in mL. Enter the vial strength to include them.")
                            .captionSecondary()
                    }
                }
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
                if model.hasLogHistory {
                    Toggle(isOn: $model.startFromLog) {
                        Text("Start from your log")
                            .font(.subheadline)
                    }
                    .tint(Theme.accent)
                }
                if model.continuesFromLog {
                    Text("Starts at today's level from your log. Next dose one interval after your last.")
                        .captionSecondary()
                } else {
                    labeledField(String(localized: "Starting level"), value: $model.startingLevel, unit: model.analyte.canonicalUnit)
                    Text("The level in your body today, if any. First dose today.")
                        .captionSecondary()
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
    @Bindable var model: InjectionLevelsModel
    let result: DepotCurveResult
    let analyte: Analyte
    let referenceLow: Double?
    let referenceHigh: Double?

    /// The visible days at the start of a pinch, so the gesture scales from there.
    @State private var pinchBaseDays: Double?

    /// The whole logged span in days — the pinch's zoomed-out limit.
    private var totalSpanDays: Double {
        result.range.upperBound.timeIntervalSince(result.range.lowerBound) / PKModel.secondsPerDay
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Estimated \(String(localized: analyte.displayName)) level")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                Spacer()
                rangeMenu
            }
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
            .gesture(pinchZoom)
        }
        .padding()
        .themeCard()
    }

    /// The zoom presets — a compact menu (the toolbar affordance), matching the
    /// insights charts. Picking one clears any pinch override.
    private var rangeMenu: some View {
        Menu {
            Picker("Range", selection: $model.chartRange) {
                ForEach(InjectionLevelsModel.ChartRange.allCases) { range in
                    Text(range.label).tag(range)
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(model.chartRange.label)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.accent)
        }
        .onChange(of: model.chartRange) { model.pinchVisibleDays = nil }
    }

    /// Pinch to zoom the visible window continuously between one week and the whole
    /// span, overriding the preset until one is tapped again.
    private var pinchZoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = pinchBaseDays ?? (model.effectiveVisibleDays ?? totalSpanDays)
                if pinchBaseDays == nil { pinchBaseDays = base }
                let next = (base / value.magnification).clamped(to: 7 ... max(7, totalSpanDays))
                model.pinchVisibleDays = next
            }
            .onEnded { _ in pinchBaseDays = nil }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
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
            Text("An injected ester releases slowly from the oil depot, splits into the free hormone, and clears. The curve models that from your doses.")
                .captionSecondary()
            Text("It estimates a level. It never suggests a dose or a target. Lab results calibrate it to you.")
                .captionSecondary()
            Text("Levels vary a lot between people, so an uncalibrated curve is a starting point, not a reading. One blood test sets the height. Two on different days set the shape too. Retest after any change in dose, ester, interval, or site.")
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
            Text("No injectable ester data in this build.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .themeCard()
    }
}
