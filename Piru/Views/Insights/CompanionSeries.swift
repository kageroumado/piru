import Charts
import SwiftData
import SwiftUI

/// A companion lab series shown alongside the modeled serum hormone — **measured
/// points, never a model** (Specs/injection-levels-v3.md §3, §5). Each side models
/// its injected hormone and plots the other axis as measured points, because the
/// relationships (aromatization, HPG suppression) are person-specific with no
/// citable conversion to hard-code.
enum CompanionMeasurement: String, Identifiable, CaseIterable {
    /// Testosterone suppression on the estradiol (transfem) detail.
    case testosterone
    /// Aromatized estradiol on the testosterone (transmasc) detail.
    case estradiol
    /// Hematocrit — the T-specific monitoring axis estradiol has no analogue for.
    case hematocrit
    /// Hemoglobin — the other red-cell readout, monitored on the same panel.
    case hemoglobin

    var id: String { rawValue }

    /// The `LabMeasurement.analyteKey` these points are stored under.
    var analyteKey: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .testosterone: "Testosterone (suppression)"
        case .estradiol: "Aromatized estradiol"
        case .hematocrit: "Hematocrit"
        case .hemoglobin: "Hemoglobin"
        }
    }

    /// The unit these points are entered and shown in.
    var unit: String {
        switch self {
        case .testosterone: "ng/dL"
        case .estradiol: "pg/mL"
        case .hematocrit: "%"
        case .hemoglobin: "g/dL"
        }
    }

    /// The framing line — states what the series *is* (measured, monitored), never a
    /// scare and never a modeled prediction.
    var framing: LocalizedStringResource {
        switch self {
        case .testosterone:
            "Your measured testosterone. On estradiol, T usually falls; Piru plots your points rather than modeling suppression."
        case .estradiol:
            "Testosterone aromatizes to estradiol, so E2 often rises on T. Piru plots your measured points — the conversion is person-specific, not modeled."
        case .hematocrit:
            "Testosterone raises red-cell production, so hematocrit is monitored on T (largest rise in the first year). These are your measured points, plotted, not a prediction."
        case .hemoglobin:
            "Monitored alongside hematocrit on T. Your measured points, plotted."
        }
    }

    var tint: Color {
        switch self {
        case .testosterone: .indigo
        case .estradiol: .pink
        case .hematocrit: .red
        case .hemoglobin: .orange
        }
    }

    /// Whether this is a hormone measurement (entered in the hormone's own units)
    /// versus a fixed-unit blood count.
    var isHormone: Bool {
        self == .testosterone || self == .estradiol
    }

    /// The depot analyte whose detail shows this companion.
    static func companions(for analyte: Analyte) -> [CompanionMeasurement] {
        switch analyte {
        case .estradiol: [.testosterone]
        case .testosterone: [.estradiol, .hematocrit, .hemoglobin]
        }
    }
}

// MARK: - Card

/// One companion series: its measured points connected over time, a plain
/// increased/flat/decreased trend, and its framing line. Renders nothing when the
/// user has no points for it (an empty monitoring axis needs no card).
struct CompanionSeriesCard: View {
    let measurement: CompanionMeasurement
    let points: [(date: Date, value: Double)]
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text(measurement.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                Spacer()
                if let trend = trendLabel {
                    Text(trend)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(measurement.tint)
                }
            }

            if points.count >= 2 {
                Chart {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Date", point.date), y: .value("Level", point.value))
                            .foregroundStyle(measurement.tint.opacity(Theme.Opacity.strong))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Date", point.date), y: .value("Level", point.value))
                            .foregroundStyle(measurement.tint)
                    }
                }
                .frame(height: 120)
                .chartYAxisLabel(measurement.unit)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(.caption2)
                    }
                }
            } else if let only = points.first {
                Text("\(only.value.formatted(.number.precision(.fractionLength(1)))) \(measurement.unit) on \(only.date, format: .dateTime.year().month(.abbreviated).day())")
                    .font(.subheadline)
            }

            Text(measurement.framing)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)

            Button(action: onAdd) {
                Label("Add \(String(localized: measurement.title))", systemImage: "plus.circle")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(measurement.tint)
        }
        .padding()
        .themeCard()
    }

    /// Plain first→last trend, the only claim that's honest off a few points.
    private var trendLabel: String? {
        guard let first = points.first?.value, let last = points.last?.value, first > 0, points.count >= 2 else { return nil }
        let change = (last - first) / first
        if change > 0.05 { return String(localized: "Increased") }
        if change < -0.05 { return String(localized: "Decreased") }
        return String(localized: "Flat")
    }
}

// MARK: - Entry

/// Enter one companion measurement — a hormone level (in its own units) or a fixed-
/// unit blood count. Stored as a ``LabMeasurement`` under the companion's analyte key;
/// blood counts are excluded from depot calibration by their key not being a modeled
/// analyte, and hormone companions calibrate only if that hormone's ester is logged.
struct AddCompanionMeasurementSheet: View {
    @Environment(\.dismiss) private var dismiss
    let measurement: CompanionMeasurement
    let onSave: (LabMeasurement) -> Void

    @State private var date = Date.now
    @State private var value: Double?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                    HStack {
                        TextField(String(localized: measurement.title), value: $value, format: .number)
                            .decimalKeyboard()
                        Text(measurement.unit)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                } footer: {
                    Text(measurement.framing)
                }
            }
            .navigationTitle(Text(measurement.title))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { save() }.disabled((value ?? 0) <= 0)
                }
            }
        }
    }

    private func save() {
        guard let raw = value, raw > 0 else { return }
        onSave(LabMeasurement(
            date: date, analyteKey: measurement.analyteKey, value: raw,
            inputUnit: measurement.unit,
            // A blood count never calibrates a depot curve; keep it out of any fit.
            excludedFromCalibration: !measurement.isHormone,
        ))
        dismiss()
    }
}
