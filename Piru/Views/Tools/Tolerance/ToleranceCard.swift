import Charts
import SwiftUI

/// One mechanism class's card: a family-color dot + tier-aware name + "Modeled" capsule, an optional
/// contributor row, the segmented tolerance bar, the recovery chart, and trimmed safety notes.
/// Density scales with `tier`. The level has no word: the bar is the whole readout.
struct ToleranceCard: View {
    let row: ToleranceRow
    let tier: UserProfile

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            ToleranceCardHeader(
                color: row.familyColor,
                name: toleranceClassName(row.snapshot.receptorClass, tier: tier),
            )

            if tier != .casual, !row.snapshot.contributors.isEmpty {
                ToleranceContributorChips(contributors: row.snapshot.contributors, color: row.familyColor)
            }

            // Effect-selective classes (GABA, α2δ) split into the effect ladder instead of one gauge:
            // sedation fades while memory and coordination do not, which one bar cannot say.
            if row.snapshot.effectShifts.isEmpty {
                ToleranceBar(
                    bands: row.bands,
                    level: row.snapshot.severity,
                    showsLegend: tier != .casual,
                )
            } else {
                EffectLadderView(snapshot: row.snapshot)
            }

            ToleranceRecoveryChart(row: row)

            ToleranceSafetyNotesView(notes: row.safetyNotes())
        }
        .padding(.vertical, Spacing.sm)
    }
}

struct ToleranceCardHeader: View {
    let color: Color
    let name: LocalizedStringResource

    var body: some View {
        HStack(spacing: Spacing.md) {
            LegendDot(color: color, size: .large)
            Text(name)
                .cardTitle()
            Spacer(minLength: 8)
            Text("Modeled")
                .capsuleChip(text: Theme.secondaryLabel, fill: .secondary, size: .regular)
                .textCase(.uppercase)
        }
    }
}

struct ToleranceContributorChips: View {
    let contributors: [String]
    let color: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(contributors, id: \.self) { name in
                    Text(CustomSubstanceStore.shared.displayName(for: name))
                        .capsuleChip(text: color, fill: color)
                }
            }
        }
    }
}

/// The segmented, part-to-whole tolerance bar: how toleranced you are, split by which recovery layer.
struct ToleranceBar: View {
    let bands: [ToleranceBand]
    /// Overall fill, 0–1 — spoken to VoiceOver as a share of the bar.
    let level: Double
    let showsLegend: Bool

    private var multiBand: Bool {
        bands.count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(Theme.Opacity.tintActive))
                    HStack(spacing: multiBand ? 1.5 : 0) {
                        ForEach(bands) { band in
                            Rectangle()
                                .fill(band.color)
                                .frame(width: max(0, geo.size.width * band.widthFraction))
                        }
                    }
                    .clipShape(skinChipShape())
                }
            }
            .frame(height: 10)

            if showsLegend, multiBand {
                HStack(spacing: Spacing.lg) {
                    ForEach(bands) { band in
                        HStack(spacing: Spacing.xs) {
                            LegendDot(color: band.color, size: .compact)
                            Text(band.label)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Modeled tolerance"))
        .accessibilityValue(Text(min(1, max(0, level)), format: .percent.precision(.fractionLength(0))))
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
            VStack(alignment: .leading, spacing: Spacing.sm) {
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
                    label: Text("Modeled tolerance over time"),
                    value: Text("The modeled level from now, fading over the days shown."),
                )
            }
        }
    }
}

/// The trimmed one-sentence safety notes for a class (one label each).
struct ToleranceSafetyNotesView: View {
    let notes: [ToleranceSafetyNote]

    var body: some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(notes) { note in
                    Label {
                        Text(note.text)
                            .captionSecondary()
                    } icon: {
                        Image(systemName: note.systemImage)
                            .foregroundStyle(note.tint)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }
}
