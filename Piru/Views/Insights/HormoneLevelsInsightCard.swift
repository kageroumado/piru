import SwiftData
import SwiftUI

/// The first-class "Hormone Levels" card on the Insights landing — a legend-less
/// 3-month serum preview that pushes to ``HormoneLevelsView``
/// (Specs/injection-levels-v3.md §1). It appears only for someone who logs an
/// injectable estradiol or testosterone ester; otherwise it renders nothing.
struct HormoneLevelsInsightCard: View {
    @Query(sort: \DoseEntry.timestamp) private var doseEntries: [DoseEntry]
    @Query(sort: \LabMeasurement.date) private var labs: [LabMeasurement]

    @State private var model = HormoneLevelsModel()

    @AppStorage(InjectionLevelsModel.StorageKey.personalMultiplier) private var storedMultiplier = 1.0
    @AppStorage(InjectionLevelsModel.StorageKey.autoCalibrate) private var storedAutoCalibrate = true
    @AppStorage(InjectionLevelsModel.StorageKey.fitRates) private var storedFitRates = true
    @AppStorage(InjectionLevelsModel.StorageKey.volumeConcentration(.estradiol)) private var storedEstradiolConcentration = 0.0
    @AppStorage(InjectionLevelsModel.StorageKey.volumeConcentration(.testosterone)) private var storedTestosteroneConcentration = 0.0

    private static let tint = Color.pink

    /// The card always renders the `GlanceCard` shell so its `.task` runs reliably —
    /// a `.task` on an *empty* `Group` never fires (Group modifiers propagate to its
    /// children, of which an empty group has none). Presence is gated by the parent,
    /// which mounts it only when an injectable hormone is logged, so a non-HRT user
    /// never sees an empty card.
    var body: some View {
        GlanceCard(
            icon: "waveform.path.ecg",
            tint: Self.tint,
            titleColor: Self.tint,
            title: Text("Hormone Levels"),
            route: .insight(.hormoneLevels),
        ) {
            if let result = model.result {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text(rangeText(result))
                            .font(.piru(.title3, design: .rounded, weight: .bold))
                        Text(model.analyte.canonicalUnit)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                        Spacer()
                        Text(model.analyte.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    DepotCurveMiniChart(
                        result: result,
                        analyte: model.analyte,
                        tint: Self.tint,
                        referenceLow: model.referenceLow,
                        referenceHigh: model.referenceHigh,
                        referenceBand: model.analyte.referenceRegion,
                    )
                }
            } else {
                Color.clear.frame(height: 76)
            }
        }
        .task {
            await SubstanceStore.shared.ensureAllLoaded()
            model.personalMultiplier = storedMultiplier
            model.autoCalibrateFromLabs = storedAutoCalibrate
            model.fitRates = storedFitRates
            recompute()
        }
        .onChange(of: doseEntries.count) { recompute() }
        .onChange(of: labs.count) { recompute() }
    }

    private func rangeText(_ result: DepotCurveResult) -> String {
        let low = Int(result.trough.rounded())
        let high = Int(result.peak.rounded())
        return "\(low)–\(high)"
    }

    private func concentration(for analyte: Analyte) -> Double? {
        let stored = switch analyte {
        case .estradiol: storedEstradiolConcentration
        case .testosterone: storedTestosteroneConcentration
        }
        return stored > 0 ? stored : nil
    }

    /// Preview the analyte whose log has the most recent injection — the one the
    /// person is actively on — falling back to any analyte that has a curve.
    private func recompute() {
        let candidates = Analyte.allCases
            .filter { SubstanceStore.shared.analytesWithEsterData().contains($0.key) }
            .map { analyte in
                (analyte, HormoneLevelsLog.grouped(from: doseEntries, analyte: analyte, volumeConcentrationMgPerML: concentration(for: analyte)))
            }
            .filter(\.1.hasModelableInjections)

        let chosen = candidates.max { lhs, rhs in
            (lhs.1.allInjections.last?.date ?? .distantPast) < (rhs.1.allInjections.last?.date ?? .distantPast)
        }

        guard let (analyte, grouped) = chosen else { model.sync(grouped: .init(), measurements: []); model.refresh(); return }
        model.analyte = analyte
        let measurements = labs
            .filter { $0.analyteKey == analyte.key && !$0.excludedFromCalibration }
            .map { DepotCalibration.Measurement(date: $0.date, value: $0.value) }
        model.sync(grouped: grouped, measurements: measurements)
        model.refresh()
    }
}
