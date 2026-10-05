import SwiftUI

/// Reference windows and study statistics stay distinct from the session model.
struct WikiTimingSection: View {
    let records: [WikiTimingRecord]
    @State private var isExpanded = false

    var body: some View {
        if !records.isEmpty {
            CollapsibleSection("substance.wiki timelines", count: records.count, isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(records) { record in
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            HStack {
                                Text(verbatim: record.route ?? String(localized: "Route unknown"))
                                    .font(.headline)
                                Spacer()
                                Text("Reference \(record.entryIndex + 1)")
                                    .font(.caption)
                            }
                            if let formulation = record.formulation {
                                Text(verbatim: formulation).captionSecondary()
                            }
                            if record.hasSourceException {
                                Text("This source entry has a recorded timing or route concern.").captionSecondary()
                            }
                            if let curve = record.curve {
                                legacy(curve, partial: record.kind == "partial_duration_curve")
                            }
                            if let study = record.study {
                                studyContent(study, timingText: record.timingText)
                            }
                            if let url = record.sourceURL {
                                Link("Read source context", destination: url).font(.caption)
                            }
                        }
                        if record.id != records.last?.id { Divider() }
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
        }
    }

    private func legacy(_ curve: WikiTimingCurve, partial: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if partial { Text("Partial timing data").font(.subheadline.bold()) }
            Text("Published timing illustration. Phase clock origins are unverified. Unknown timings are not estimated or used to predict your session.")
                .captionSecondary()
            WikiTimingWindowRow("Onset", window: curve.onset, units: curve.units, maximum: curve.plotMaximum)
            WikiTimingWindowRow("Peak", window: curve.peak, units: curve.units, maximum: curve.plotMaximum)
            WikiTimingWindowRow("Offset", window: curve.offset, units: curve.units, maximum: curve.plotMaximum)
            WikiTimingWindowRow("After-effects", window: curve.afterEffects, units: curve.units, maximum: curve.plotMaximum)
            if let total = curve.total {
                HStack {
                    Text("Reported total")
                    Spacer()
                    Text(verbatim: "\(wikiTimingNumber(total.min)) – \(wikiTimingNumber(total.max)) \(curve.units ?? String(localized: "Units unknown"))")
                }
                .font(.caption)
                if let note = total.note { Text(verbatim: note).captionSecondary() }
            }
            if let reference = curve.reference {
                Text(verbatim: reference).captionSecondary()
            }
        }
    }

    private func studyContent(_ study: WikiTimingStudy, timingText: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Study timeline").font(.subheadline.bold())
            Text("Study statistics describe this condition, not a prediction of your session. The maximum response is a time point, not a peak plateau.")
                .captionSecondary()
            HStack {
                Text("Study dose (µg base)")
                Spacer()
                Text(verbatim: wikiTimingNumber(study.nominalStudyDoseMicrogramsBase))
            }
            .font(.caption)
            Text(verbatim: study.context.studyDesign).captionSecondary()
            Text(verbatim: study.context.population).captionSecondary()
            Text("Participants: \(study.context.participantCount)").font(.caption)
            Text(verbatim: study.context.condition).captionSecondary()
            Text(verbatim: study.context.endpoint).captionSecondary()
            HStack {
                Text("Clock origin")
                Spacer()
                Text(verbatim: study.context.clockOrigin)
            }
            .font(.caption)
            HStack {
                Text("Response threshold (% of individual maximum)")
                Spacer()
                Text(verbatim: wikiTimingNumber(study.context.onsetOffsetThresholdFraction * 100))
            }
            .font(.caption)
            ForEach(study.points) { point in
                WikiStudyStatisticRow(
                    statistic: point, units: study.units,
                    maximum: study.points.map(\.participantRange.max).max(),
                )
            }
            Text("Active duration: onset to offset").font(.subheadline)
            WikiStudyStatisticRow(statistic: study.activeDuration, units: study.units)
            ForEach(["onset", "peak", "offset", "total_duration", "after_effects"], id: \.self) { key in
                if let text = timingText[key] { Text(verbatim: text).captionSecondary() }
            }
            Text(verbatim: study.source.locator).captionSecondary()
            if let url = URL(string: study.source.articleUrl) {
                Link("Study article", destination: url).font(.caption)
            }
            if let url = URL(string: study.source.tableUrl) {
                Link("Study data table", destination: url).font(.caption)
            }
        }
    }
}

private func wikiTimingNumber(_ value: Double?) -> String {
    guard let value, value.isFinite else { return String(localized: "Unknown") }
    return String(format: "%.6g", value)
}

/// Independent bars retain the published windows; no line bridges phases or
/// missing boundaries, and no inferred start at zero is drawn.
private struct WikiTimingWindowRow: View {
    let title: LocalizedStringKey
    let window: WikiTimingWindow?
    let units: String?
    let maximum: Double?

    init(_ title: LocalizedStringKey, window: WikiTimingWindow?, units: String?, maximum: Double?) {
        self.title = title
        self.window = window
        self.units = units
        self.maximum = maximum
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text(verbatim: "\(wikiTimingNumber(window?.start)) – \(wikiTimingNumber(window?.end)) \(units ?? String(localized: "Units unknown"))")
                    .monospacedDigit()
            }
            .font(.caption)
            if let start = window?.start, let end = window?.end,
               start.isFinite, end.isFinite, start >= 0, end >= start,
               let maximum, maximum > 0 {
                GeometryReader { geometry in
                    Capsule()
                        .fill(Theme.accent.opacity(0.5))
                        .frame(width: max(CGFloat((end - start) / maximum) * geometry.size.width, 2), height: 4)
                        .offset(x: CGFloat(start / maximum) * geometry.size.width)
                }
                .frame(height: 4)
                .accessibilityHidden(true)
            }
        }
    }
}

private struct WikiStudyStatisticRow: View {
    let statistic: WikiTimingStudy.Statistic
    let units: String
    var maximum: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let label = statistic.label { Text(verbatim: label).font(.caption.bold()) }
            HStack {
                Text("Mean ± SD")
                Spacer()
                Text(verbatim: "\(wikiTimingNumber(statistic.mean)) ± \(wikiTimingNumber(statistic.standardDeviation)) \(units)")
            }
            HStack {
                Text("Participant range")
                Spacer()
                Text(verbatim: "\(wikiTimingNumber(statistic.participantRange.min)) – \(wikiTimingNumber(statistic.participantRange.max)) \(units)")
            }
            if let maximum, maximum > 0,
               statistic.participantRange.min >= 0,
               statistic.participantRange.max >= statistic.participantRange.min,
               statistic.mean >= statistic.participantRange.min,
               statistic.mean <= statistic.participantRange.max {
                GeometryReader { geometry in
                    let width = geometry.size.width
                    let lower = statistic.participantRange.min / maximum
                    let upper = statistic.participantRange.max / maximum
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.accent.opacity(0.35))
                            .frame(width: max(CGFloat(upper - lower) * width, 2), height: 4)
                            .offset(x: CGFloat(lower) * width)
                        Circle().fill(Theme.accent)
                            .frame(width: 7, height: 7)
                            .offset(x: CGFloat(statistic.mean / maximum) * width - 3.5)
                    }
                }
                .frame(height: 7)
                .accessibilityHidden(true)
                Text("Bar: participant range; dot: mean.").captionSecondary()
            }
        }
        .font(.caption)
    }
}
