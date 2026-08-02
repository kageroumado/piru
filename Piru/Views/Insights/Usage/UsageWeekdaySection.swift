import Charts
import SwiftUI

/// §8 — "which days of the week am I most active, and what do I use on each?"
/// Seven bars stacked by substance category, with the per-weekday average
/// underneath.
///
/// This replaces the old four-bucket "Time of Day" chart. That detail is not
/// lost: it moved to the 24-bin hour histogram in §2.
struct UsageWeekdaySection: View {
    let buckets: [UsageWeekdayBucket]

    private struct Segment: Identifiable {
        let weekday: Int
        let categoryIndex: Int
        let count: Int
        var id: String {
            "\(weekday)-\(categoryIndex)"
        }
    }

    var body: some View {
        UsageSectionCard(title: "Day of week", subtitle: "Entries by weekday, split by class") {
            Chart(segments) { segment in
                BarMark(
                    x: .value("Day", label(for: segment.weekday)),
                    y: .value("Entries", segment.count),
                )
                .foregroundStyle(UsageAxes.category(segment.categoryIndex).labelColor)
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

    private var segments: [Segment] {
        buckets.flatMap { bucket in
            bucket.byCategory
                .sorted { $0.key < $1.key }
                .map { Segment(weekday: bucket.weekday, categoryIndex: $0.key, count: $0.value) }
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
