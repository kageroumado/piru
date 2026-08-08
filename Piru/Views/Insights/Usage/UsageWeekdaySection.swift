import Charts
import SwiftUI

/// §8 — "which days of the week am I most active?" Seven bars, one per weekday,
/// with the per-weekday average underneath.
///
/// Deliberately a single color, not stacked by class: the class split had no
/// legend, so the stack of a dozen category colors read as noise rather than
/// information — and the question this card asks is "which days", which the total
/// answers directly. The per-class detail lives where it has a legend (the
/// Activity heatmap's category pills, Most logged's route colors).
///
/// This replaces the old four-bucket "Time of Day" chart. That detail is not
/// lost: it moved to the 24-bin hour histogram in §2.
struct UsageWeekdaySection: View {
    let buckets: [UsageWeekdayBucket]

    var body: some View {
        UsageSectionCard(title: "Day of week", subtitle: "Which weekdays you log on most") {
            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Day", label(for: bucket.weekday)),
                    y: .value("Entries", bucket.total),
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
                        .foregroundStyle(Theme.secondaryLabel.opacity(0.5))
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .chartSummaryAccessibility(label: Text("Entries by weekday"), value: Text(summary))

            averagesRow
        }
    }

    /// Average entries on each weekday — divided by how many times that weekday
    /// actually came around inside the range, so a 10-day window doesn't make
    /// two weekdays look artificially busy.
    private var averagesRow: some View {
        HStack(spacing: 0) {
            ForEach(buckets) { bucket in
                VStack(spacing: 2) {
                    Text(label(for: bucket.weekday))
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.secondaryLabel)
                    Text(bucket.average.formatted(.number.precision(.fractionLength(0 ... 1))))
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(fullLabel(for: bucket.weekday)))
                .accessibilityValue(Text("\(bucket.average.formatted(.number.precision(.fractionLength(0 ... 1)))) entries per day on average"))
            }
        }
        .padding(.top, 2)
    }

    private var summary: String {
        let total = buckets.reduce(0) { $0 + $1.total }
        guard total > 0, let peak = buckets.max(by: { $0.total < $1.total }) else {
            return String(localized: "No entries in this window")
        }
        return String(localized: "\(total) entries, busiest on \(fullLabel(for: peak.weekday)) with \(peak.total)")
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
