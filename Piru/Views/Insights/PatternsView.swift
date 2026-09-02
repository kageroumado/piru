import Charts
import SwiftData
import SwiftUI

/// Insights → Patterns. The record-and-model view a user can read for themselves
/// or hand a clinician: days used vs off, cumulative exposure (in clinical
/// equivalents where they exist), whether a dose has crept up, and where two
/// substances were active at once. All four are one ``ClinicalReport`` — the same
/// value the PDF clinician report renders, so the app and the print-out agree.
struct PatternsView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]

    @State private var range: UsageTimeRange = .ninetyDays
    @State private var report: ClinicalReport?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                if allEntries.isEmpty {
                    ContentUnavailableView(
                        "No Logged Entries",
                        systemImage: "list.clipboard",
                        description: Text("Log some doses to see your patterns."),
                    )
                    .padding(.top, 40)
                } else if let report, !report.isEmpty {
                    HolidayCard(holidays: report.holidays)
                    if !report.exposure.isEmpty { ExposureCard(report: report) }
                    if !report.escalation.isEmpty { EscalationCard(report: report) }
                    if !report.overlaps.isEmpty { OverlapCard(report: report) }
                    disclaimer
                } else if loaded {
                    ContentUnavailableView(
                        "Nothing to Summarize",
                        systemImage: "list.clipboard",
                        description: Text("Nothing logged in this range."),
                    )
                    .padding(.top, 40)
                } else {
                    ProgressView().padding(.top, 60)
                }
            }
            .padding()
            .padding(.bottom, 40)
        }
        .background(Theme.background)
        .toolbar {
            if !allEntries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { rangeMenu }
            }
        }
        .task(id: token) {
            await SubstanceStore.shared.ensureAllLoaded()
            await load()
        }
    }

    private var token: Int {
        var hasher = Hasher()
        hasher.combine(DoseLogService.shared.revision)
        hasher.combine(ColorsFingerprint.make(substanceColors))
        hasher.combine(range)
        return hasher.finalize()
    }

    private func load() async {
        let now = Date.now
        let start: Date = if let days = range.days {
            now.addingTimeInterval(-Double(days) * 86_400)
        } else {
            allEntries.map(\.timestamp).min() ?? now.addingTimeInterval(-90 * 86_400)
        }
        // Resolve on the main actor (equivalence / ladder lookups), then run the
        // aggregation — the overlap pass is a per-hour body-load sample — off main.
        let (substances, doses) = ClinicalStatsResolver.resolve(
            entries: allEntries, hexMap: substanceColors.hexColorMap, start: start, end: now,
        )
        report = await Task.detached {
            ClinicalStats.report(substances: substances, doses: doses, start: start, end: now, calendar: .current)
        }.value
        loaded = true
    }

    private var rangeMenu: some View {
        Menu {
            Picker("Time Range", selection: $range) {
                ForEach(UsageTimeRange.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
        } label: {
            Text(range.displayName).sectionLabel()
        }
    }

    private var disclaimer: some View {
        Text("A record and a model, not medical advice. Exposure uses clinical equivalents where they're established, and the substance's typical dose otherwise.")
            .font(.caption2)
            .foregroundStyle(Theme.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xs)
    }
}

// MARK: - Days & holidays

private struct HolidayCard: View {
    let holidays: HolidayStats

    var body: some View {
        UsageSectionCard(title: "Days used", subtitle: "How often, across this range") {
            HStack(alignment: .top, spacing: 0) {
                tile("\(holidays.daysUsed)", "of \(holidays.totalDays) days")
                tile(holidays.fractionUsed.formatted(.percent.precision(.fractionLength(0))), "of days")
                tile("\(holidays.longestBreakDays)d", "longest break")
                if holidays.currentBreakDays > 0 {
                    tile("\(holidays.currentBreakDays)d", "since last")
                }
            }
        }
    }

    private func tile(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Exposure

private struct ExposureCard: View {
    let report: ClinicalReport

    var body: some View {
        UsageSectionCard(title: "Cumulative exposure", subtitle: "Total taken this range, in each substance's clinical or common-dose unit") {
            if report.opioidPeakDayMME != nil || report.benzoDiazepamPerDay != nil {
                clinicalCallout
            }
            VStack(spacing: Spacing.lg) {
                ForEach(report.exposure) { stat in
                    ExposureRow(stat: stat, substance: report.substances[stat.substanceIndex])
                }
            }
        }
    }

    private var clinicalCallout: some View {
        VStack(spacing: Spacing.md) {
            if let peak = report.opioidPeakDayMME {
                MMEBand(peakDayMME: peak, dailyMean: report.opioidMMEPerDay ?? 0)
            }
            if let de = report.benzoDiazepamPerDay {
                HStack {
                    Image(systemName: "cross.case")
                        .foregroundStyle(.infoText)
                        .accessibilityHidden(true)
                    Text("Benzodiazepines ≈ \(de.formatted(.number.precision(.fractionLength(0 ... 1)))) mg diazepam-eq/day")
                        .font(.caption)
                    Spacer()
                }
                .padding(Spacing.lg)
                .background(Color.infoAccent.opacity(Theme.Opacity.tint), in: .rect(cornerRadius: Theme.CornerRadius.inner))
            }
        }
        .padding(.bottom, Spacing.xs)
    }
}

/// The opioid total in morphine-milligram equivalents — the reader's own numbers,
/// converted.
///
/// No caution/high-risk band and no traffic-light color. CDC 2022 removed the 90
/// MME/day threshold and reframed 50 as a point to "pause and carefully reassess",
/// stating its dosage recommendations "are not intended to be used as an
/// inflexible, rigid standard of care" — so sorting a day into red/orange/green
/// would assert a rigidity the source withdrew, and hand the reader a verdict
/// where the number was the point. The substantive warnings live in the opioid
/// converter's safety card, where they are advice rather than a grade.
private struct MMEBand: View {
    let peakDayMME: Double
    let dailyMean: Double

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            Image(systemName: "cross.case")
                .foregroundStyle(.infoAccent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Opioids: peak day ≈ \(peakDayMME.formatted(.number.precision(.fractionLength(0)))) MME")
                    .sectionLabel()
                Text("Average \(dailyMean.formatted(.number.precision(.fractionLength(0 ... 1)))) MME/day over the range")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer()
        }
        .padding(Spacing.lg)
    }
}

private struct ExposureRow: View {
    let stat: ExposureStat
    let substance: ClinicalSubstance

    var body: some View {
        HStack(spacing: Spacing.lg) {
            LegendDot(color: Color(hex: substance.colorHex), size: .large)
            VStack(alignment: .leading, spacing: 1) {
                Text(substance.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("\(stat.total.exposureFormatted) \(substance.unit)")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer(minLength: 8)
            sparkline
                .frame(width: 90, height: 30)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(substance.displayName): \(stat.total.exposureFormatted) \(substance.unit) total"))
    }

    private var sparkline: some View {
        Chart(stat.cumulative) { point in
            AreaMark(x: .value("Date", point.date), y: .value("Total", point.total))
                .foregroundStyle(Color(hex: substance.colorHex).opacity(Theme.Opacity.emphasis))
            LineMark(x: .value("Date", point.date), y: .value("Total", point.total))
                .foregroundStyle(Color(hex: substance.colorHex))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityHidden(true)
    }
}

// MARK: - Escalation

private struct EscalationCard: View {
    let report: ClinicalReport

    var body: some View {
        UsageSectionCard(title: "Dose trend", subtitle: "Whether your typical dose has moved over this range") {
            VStack(spacing: Spacing.lg) {
                ForEach(report.escalation) { stat in
                    EscalationRow(stat: stat, substance: report.substances[stat.substanceIndex])
                }
            }
        }
    }
}

private struct EscalationRow: View {
    let stat: EscalationStat
    let substance: ClinicalSubstance

    private var glyph: (name: String, color: Color) {
        switch stat.direction {
        case .rising: ("arrow.up.right", .orange)
        case .falling: ("arrow.down.right", .green)
        case .steady: ("arrow.right", Theme.secondaryLabel)
        }
    }

    var body: some View {
        HStack(spacing: Spacing.lg) {
            LegendDot(color: Color(hex: substance.colorHex), size: .large)
            Text(substance.displayName)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(stat.earlyMedian.exposureFormatted) → \(stat.lateMedian.exposureFormatted)")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
                .monospacedDigit()
            Label {
                Text(changeText)
            } icon: {
                Image(systemName: glyph.name)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(glyph.color)
            .labelStyle(.titleAndIcon)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(substance.displayName): dose \(directionWord), \(changeText)"))
    }

    private var changeText: String {
        stat.direction == .steady ? String(localized: "steady")
            : stat.change.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()))
    }

    private var directionWord: String {
        switch stat.direction {
        case .rising: String(localized: "rising")
        case .falling: String(localized: "falling")
        case .steady: String(localized: "steady")
        }
    }
}

// MARK: - Overlap

private struct OverlapCard: View {
    let report: ClinicalReport

    var body: some View {
        UsageSectionCard(title: "Active together", subtitle: "Hours two substances were both in your body at once") {
            VStack(spacing: Spacing.lg) {
                ForEach(report.overlaps.prefix(6)) { overlap in
                    let a = report.substances[overlap.a]
                    let b = report.substances[overlap.b]
                    HStack(spacing: Spacing.md) {
                        LegendDot(color: Color(hex: a.colorHex))
                        LegendDot(color: Color(hex: b.colorHex))
                        Text("\(a.displayName) · \(b.displayName)")
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(overlap.hoursText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.secondaryLabel)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("\(a.displayName) and \(b.displayName): \(overlap.hoursText) active together"))
                }
            }
        }
    }
}

// MARK: - Formatting

private extension Double {
    /// Exposure numbers span MME (tens), diazepam-mg (tens), common-doses (single
    /// digits) and raw mg (up to thousands) — round to whole units above 10, one
    /// decimal below.
    var exposureFormatted: String {
        self >= 10
            ? formatted(.number.precision(.fractionLength(0)))
            : formatted(.number.precision(.fractionLength(0 ... 1)))
    }
}

private extension OverlapStat {
    var hoursText: String {
        hours >= 24
            ? String(localized: "\((hours / 24).formatted(.number.precision(.fractionLength(0 ... 1)))) days")
            : String(localized: "\(Int(hours.rounded())) h")
    }
}
