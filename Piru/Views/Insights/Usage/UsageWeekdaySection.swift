import Charts
import SwiftUI

/// §8 — "which days of the week am I most active?" Seven bars, one per weekday,
/// each the average for that weekday, with the same figure printed underneath.
/// An average, since a 30-day range holds five of some weekdays and four of
/// others, and totals would rank the days by how often they came around.
///
/// Deliberately a single color, not stacked by class: the class split had no
/// legend, so the stack of a dozen category colors read as noise rather than
/// information — and the question this card asks is "which days", which the total
/// answers directly. The per-class detail lives where it has a legend (the
/// Activity heatmap's category pills, Most logged's route colors).
struct UsageWeekdaySection: View {
    let buckets: [UsageWeekdayBucket]
    /// The Entries/Common-doses lens, owned globally by the Usage toolbar filter.
    let metric: UsageRankMetric
    let coverage: UsageCommonDoseCoverage

    var body: some View {
        UsageSectionCard(title: "Day of week") {
            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Day", label(for: bucket.weekday)),
                    y: .value("Amount", average(bucket)),
                )
                .foregroundStyle(Theme.accent)
                .cornerRadius(3)
            }
            .frame(height: 170)
            .chartXScale(domain: buckets.map { label(for: $0.weekday) })
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.dimmed))
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: metric)
            .chartSummaryAccessibility(label: Text("Day of week"), value: Text(summary))

            averagesRow

            UsageCommonDoseCoverageNote(coverage: coverage)
        }
    }

    /// The per-occurrence average of the active metric — divided by how many
    /// times that weekday actually came around inside the range, so a 10-day
    /// window doesn't make two weekdays look artificially busy.
    private func average(_ bucket: UsageWeekdayBucket) -> Double {
        metric == .commonDoses ? (bucket.commonAverage ?? 0) : bucket.average
    }

    private var averagesRow: some View {
        HStack(spacing: 0) {
            ForEach(buckets) { bucket in
                VStack(spacing: Spacing.xxs) {
                    Text(label(for: bucket.weekday))
                        .font(.chartAnnotation)
                        .foregroundStyle(Theme.secondaryLabel)
                    Text(average(bucket).formatted(.number.precision(.fractionLength(0 ... 1))))
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(fullLabel(for: bucket.weekday)))
                .accessibilityValue(Text(average(bucket).formatted(.number.precision(.fractionLength(0 ... 1)))))
            }
        }
        .padding(.top, Spacing.xxs)
    }

    private var summary: String {
        guard let peak = buckets.max(by: { average($0) < average($1) }), average(peak) > 0 else {
            return String(localized: "No entries in this window")
        }
        if metric == .commonDoses {
            return String(localized: "Common-dose units by weekday, most on \(fullLabel(for: peak.weekday))")
        }
        let total = buckets.reduce(0) { $0 + $1.total }
        // The bars rank weekdays by their average, so the peak is named with its average.
        let peakAverage = average(peak).formatted(.number.precision(.fractionLength(0 ... 1)))
        return String(localized: "\(total) entries, busiest on \(fullLabel(for: peak.weekday)), \(peakAverage) on average")
    }

    private func label(for weekday: Int) -> String {
        let symbols = Calendar.current.shortStandaloneWeekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "?"
    }

    private func fullLabel(for weekday: Int) -> String {
        let symbols = Calendar.current.standaloneWeekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "?"
    }
}
