import SwiftUI

/// One mechanism class's card: a family-color dot + tier-aware name with the modeled level beside it,
/// when the class reads near baseline, an optional contributor row, the segmented tolerance bar (or the
/// effect ladder), the recovery chart on the screen's shared frame, and trimmed safety notes. Density
/// scales with `tier`.
struct ToleranceCard: View {
    let row: ToleranceRow
    let tier: UserProfile
    /// The row's line on the shared frame, when the class is plotted.
    let series: ToleranceRecoverySeries?
    let frame: ToleranceChartFrame

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ToleranceCardHeader(
                    color: row.familyColor,
                    name: toleranceClassName(row.snapshot.receptorClass, tier: tier),
                    level: row.snapshot.severity,
                )
                if let outcome = series?.projectionOutcome {
                    Text(toleranceProjectionText(outcome))
                        .captionSecondary()
                    if let minutes = row.minutesToNearBaseline {
                        Text(toleranceNoFurtherText(minutes: minutes))
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                } else if let minutes = row.minutesToNearBaseline {
                    Text(toleranceNearBaselineText(minutes: minutes))
                        .captionSecondary()
                }
            }

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

            if let series {
                ToleranceCurvesChart(series: [series], frame: frame)
                    .frame(height: 110)
                    .chartSummaryAccessibility(
                        label: Text("Modeled tolerance over time"),
                        value: Text("The modeled level from now, fading over the time shown."),
                    )
            }

            ToleranceSafetyNotesView(notes: row.safetyNotes())
        }
        .padding(.vertical, Spacing.sm)
    }
}

struct ToleranceCardHeader: View {
    let color: Color
    let name: LocalizedStringResource
    /// The modeled level now, 0–1, printed beside the name.
    let level: Double

    var body: some View {
        HStack(spacing: Spacing.md) {
            LegendDot(color: color, size: .large)
            Text(name)
                .cardTitle()
            Spacer(minLength: 8)
            Text(tolerancePercentText(level * 100))
                .cardTitle()
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryLabel)
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
                        .capsuleChip(text: color, fill: color, label: .name)
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
