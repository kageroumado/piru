import Charts
import SwiftUI

/// One mechanism class's card: a family-color dot + tier-aware name + "Predicted" capsule, an optional
/// contributor row, the segmented tolerance bar, an optional lede, the recovery chart, trimmed safety
/// notes, and — at the Pharma Nerd tier — a confidence/shift footer. Density scales with `tier`.
struct ToleranceCard: View {
    let row: ToleranceRow
    let tier: UserProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToleranceCardHeader(
                color: row.familyColor,
                name: toleranceClassName(row.snapshot.receptorClass, tier: tier),
            )

            if tier != .casual, !row.snapshot.contributors.isEmpty {
                ToleranceContributorChips(contributors: row.snapshot.contributors, color: row.familyColor)
            }

            ToleranceBar(
                bands: row.bands,
                word: ToleranceBucket(responseFraction: row.snapshot.responseFraction).word,
                color: row.familyColor,
                showsLegend: tier != .casual,
            )

            if let lede = row.lede {
                Text(lede)
                    .font(.subheadline)
            }

            ToleranceRecoveryChart(row: row)

            ToleranceSafetyNotesView(notes: row.safetyNotes(tier: tier))

            if tier == .pharmaNerd {
                ToleranceNerdFooter(confidenceAndShift: row.confidenceAndShift, engagedLayers: row.engagedLayers)
            }
        }
        .padding(.vertical, 6)
    }
}

struct ToleranceCardHeader: View {
    let color: Color
    let name: LocalizedStringResource

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(name)
                .font(.headline)
            Spacer(minLength: 8)
            Text("Predicted")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.14), in: Capsule())
                .foregroundStyle(Theme.secondaryLabel)
        }
    }
}

struct ToleranceContributorChips: View {
    let contributors: [String]
    let color: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(contributors, id: \.self) { name in
                    Text(CustomSubstanceStore.shared.displayName(for: name))
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(color.opacity(0.10), in: Capsule())
                        .foregroundStyle(color)
                }
            }
        }
    }
}

/// The segmented, part-to-whole tolerance bar: how toleranced you are, split by which recovery layer.
struct ToleranceBar: View {
    let bands: [ToleranceBand]
    let word: LocalizedStringResource
    let color: Color
    let showsLegend: Bool

    private var multiBand: Bool {
        bands.count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    HStack(spacing: multiBand ? 1.5 : 0) {
                        ForEach(bands) { band in
                            Rectangle()
                                .fill(band.color)
                                .frame(width: max(0, geo.size.width * band.widthFraction))
                        }
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 10)

            if showsLegend {
                HStack(spacing: 10) {
                    if multiBand {
                        ForEach(bands) { band in
                            HStack(spacing: 4) {
                                Circle().fill(band.color).frame(width: 7, height: 7)
                                Text(band.label)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Text(word)
                        .foregroundStyle(color)
                }
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(word))
    }
}

/// The per-card recovery chart (linear, gridded, starts at the current level, days). Skipped when
/// essentially rested (nothing to plot) or when the recovery window is under a couple of hours — too
/// short to plot without a degenerate, repeated-tick axis.
struct ToleranceRecoveryChart: View {
    let row: ToleranceRow

    var body: some View {
        if row.snapshot.severity > 0.03, row.recoveryWindowMinutes >= 120 {
            let points = row.recoveryCurve(overMinutes: row.recoveryWindowMinutes)
            VStack(alignment: .leading, spacing: 6) {
                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value("Days", point.day),
                            y: .value("Tolerance", point.percent),
                        )
                        .foregroundStyle(row.familyColor)
                        .interpolationMethod(.monotone)
                    }
                    if let start = points.first {
                        PointMark(
                            x: .value("Days", start.day),
                            y: .value("Tolerance", start.percent),
                        )
                        .foregroundStyle(row.familyColor)
                        .symbolSize(45)
                    }
                }
                .chartYScale(domain: 0 ... 100)
                .chartYAxis {
                    AxisMarks(values: [0, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let percent = value.as(Int.self) {
                                Text(percent >= 100 ? "high" : "low")
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: row.xAxisDays) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let days = value.as(Double.self) {
                                Text(axisDayLabel(days: days))
                            }
                        }
                    }
                }
                .frame(height: 92)
                .chartSummaryAccessibility(
                    label: Text("Tolerance recovery"),
                    value: Text("Starts at \(String(localized: ToleranceBucket(responseFraction: row.snapshot.responseFraction).word)), fading toward none."),
                )

                Text(row.chartCaption)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }
}

/// The trimmed one-sentence safety notes for a class (one label each).
struct ToleranceSafetyNotesView: View {
    let notes: [ToleranceSafetyNote]

    var body: some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(notes) { note in
                    Label {
                        Text(note.text)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    } icon: {
                        Image(systemName: note.systemImage)
                            .foregroundStyle(note.tint)
                    }
                }
            }
        }
    }
}

/// The Pharma Nerd footer: confidence + shift factor, and the engaged recovery layers.
struct ToleranceNerdFooter: View {
    let confidenceAndShift: LocalizedStringResource
    let engagedLayers: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(confidenceAndShift)
            Text(engagedLayers)
        }
        .font(.caption2)
        .foregroundStyle(Theme.secondaryLabel)
    }
}
