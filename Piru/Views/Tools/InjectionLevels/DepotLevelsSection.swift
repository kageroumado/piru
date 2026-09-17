import SwiftData
import SwiftUI

/// Which hormone's serum curve a dose or a substance belongs to — the decision
/// behind showing the Injection Levels chart outside the tool. `nil` for anything
/// the tool cannot draw: a non-depot dose, a depot with no ester curve (an LAI
/// antipsychotic), or a family the bundled DB ships no `ester_pk` rows for.
enum DepotLevels {
    /// The analyte of a **depot** dose (``PKResolver/isDepot(entry:)``) whose
    /// substance family has a modelable ester curve.
    static func analyte(for entry: DoseEntry) -> Analyte? {
        guard PKResolver.isDepot(entry: entry) else { return nil }
        let uid = entry.substanceUID ?? SubstanceStore.shared.substanceUID(forNameOrAlias: entry.substance)
        return analyte(forSubstanceUID: uid)
    }

    /// The analyte whose ester curves belong to substance family `uid` (Estradiol
    /// → `.estradiol`), or `nil` when the DB draws no curve for that family.
    static func analyte(forSubstanceUID uid: String?) -> Analyte? {
        guard let uid else { return nil }
        let esters = SubstanceStore.shared.esters(forParentUID: uid).filter(\.isModelable)
        guard let key = esters.first?.analyte else { return nil }
        return Analyte(rawValue: key)
    }
}

/// The Injection Levels curve where the dose lives: on a depot dose's detail and
/// in the library's history for a hormone with ester curves. It reads the same
/// log, labs and calibration preferences as the tool, so the two never disagree;
/// the tool itself is one tap away for the schedule and calibration controls.
struct DepotLevelsSection: View {
    let analyte: Analyte

    @Environment(\.appNavigator) private var navigator
    @Query(sort: \DoseEntry.timestamp) private var doseEntries: [DoseEntry]
    @Query(sort: \LabMeasurement.date) private var labs: [LabMeasurement]
    @State private var model = InjectionLevelsModel()

    @AppStorage(InjectionLevelsModel.StorageKey.personalMultiplier) private var storedMultiplier = 1.0
    @AppStorage(InjectionLevelsModel.StorageKey.autoCalibrate) private var storedAutoCalibrate = true
    @AppStorage(InjectionLevelsModel.StorageKey.fitRates) private var storedFitRates = true
    /// Vial strength for mL-logged injections (`0` = unset), the tool's per-analyte key.
    @AppStorage private var storedConcentration: Double

    init(analyte: Analyte) {
        self.analyte = analyte
        _storedConcentration = AppStorage(wrappedValue: 0, InjectionLevelsModel.StorageKey.volumeConcentration(analyte))
    }

    var body: some View {
        Section {
            if let result = model.result {
                DepotCurveChart(
                    model: model,
                    result: result,
                    analyte: analyte,
                    referenceLow: model.referenceLow,
                    referenceHigh: model.referenceHigh,
                )
                .padding(.vertical, Spacing.xs)
            } else if model.volumeLoggedInjectionCount > 0 {
                Text("\(model.volumeLoggedInjectionCount) injections are in mL. Enter the vial strength to include them.")
                    .captionSecondary()
            }
            Button {
                navigator.push(.tool(.injectionLevels))
            } label: {
                HStack {
                    Label("Open Injection Levels", systemImage: "syringe")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryLabel)
                        .accessibilityHidden(true)
                }
            }
            .tint(Theme.accent)
        } header: {
            Text("Injection Levels")
        }
        .task {
            await SubstanceStore.shared.ensureAllLoaded()
            model.analyte = analyte
            model.personalMultiplier = storedMultiplier
            model.autoCalibrateFromLabs = storedAutoCalibrate
            model.fitRates = storedFitRates
            model.volumeConcentrationMgPerML = storedConcentration > 0 ? storedConcentration : nil
            sync()
        }
        .onChange(of: model.recomputeKey) { model.refresh() }
        .onChange(of: doseEntries.count) { sync() }
        .onChange(of: labs.count) { sync() }
    }

    /// Feed the model from the log and labs the way the tool does, then draw.
    private func sync() {
        let log = InjectionLevelsView.injections(
            from: doseEntries, analyte: analyte,
            volumeConcentrationMgPerML: model.volumeConcentrationMgPerML,
        )
        let measurements = labs
            .filter { $0.analyteKey == analyte.key && !$0.excludedFromCalibration }
            .map { DepotCalibration.Measurement(date: $0.date, value: $0.value) }
        model.sync(
            injections: log.injections,
            volumeLoggedCount: log.volumeLoggedCount,
            suggestedConcentration: log.latestLoggedConcentration,
            measurements: measurements,
            preferredEsterID: InjectionLevelsView.dominantEsterID(from: doseEntries, analyte: analyte),
        )
        model.selectDefaultsIfNeeded()
        model.refresh()
    }
}
