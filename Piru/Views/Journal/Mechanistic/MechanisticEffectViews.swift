import SwiftUI

// MARK: - Vitals cards (Safety lens)

/// Heart-rate & blood-pressure cards paired with the Safety lens — the
/// harm-reduction payoff (real Apple Health readings alongside predicted cost).
struct MechanisticVitalsCards: View {
    let vitals: SessionVitals
    let startDate: Date
    let nowHours: Double

    /// How many earlier readings the caption names before it starts counting.
    private let earlierReadingLimit = 2

    var body: some View {
        HStack(spacing: Spacing.lg) {
            if let bpm = nearestHeartRate {
                vitalCard(icon: "heart.fill", tint: EffectLens.crash, title: "Heart rate", value: "\(bpm)", unit: "bpm")
            }
            if let bp = nearestBloodPressure {
                vitalCard(
                    icon: "waveform.path.ecg",
                    tint: .blue,
                    title: "Blood pressure",
                    value: "\(bp.0)/\(bp.1)",
                    unit: "mmHg",
                    caption: otherBloodPressureCaption,
                )
            }
        }
    }

    private func vitalCard(
        icon: String,
        tint: Color,
        title: LocalizedStringKey,
        value: String,
        unit: LocalizedStringKey,
        caption: String? = nil,
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
                .labelStyle(.titleAndIcon)
                .tint(tint)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title2.bold())
                Text(unit).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryLabel)
            }
            // The card headlines the reading nearest the playhead, so a day's
            // earlier measurements used to vanish behind it entirely. They keep
            // a line of their own rather than a second card — one glance still
            // answers "what is it now", but "and what was it before" is there.
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.xl)
        .themeCard()
        // One utterance per card ("Heart rate, 72 bpm"), not four fragments.
        .accessibilityElement(children: .combine)
    }

    /// The other readings in the window, oldest first — "08:12 107/71 · 09:40
    /// 110/69", trailing off into "+N more" past ``earlierReadingLimit``.
    /// `nil` when this is the only reading, so the caption line disappears
    /// entirely rather than rendering an empty row.
    private var otherBloodPressureCaption: String? {
        guard let shown = nearestBloodPressureReading else { return nil }
        let others = vitals.bloodPressure
            .filter { $0.date != shown.date }
            .sorted { $0.date < $1.date }
        guard !others.isEmpty else { return nil }
        let named = others.prefix(earlierReadingLimit).map {
            "\($0.date.formatted(date: .omitted, time: .shortened)) \(Int($0.systolic.rounded()))/\(Int($0.diastolic.rounded()))"
        }
        let remainder = others.count - named.count
        guard remainder > 0 else { return named.joined(separator: " · ") }
        let more = String(localized: "+\(remainder) more", comment: "Count of additional blood-pressure readings not listed")
        return (named + [more]).joined(separator: " · ")
    }

    private var nowDate: Date {
        startDate.addingTimeInterval(nowHours * 3_600)
    }

    private var nearestHeartRate: Int? {
        vitals.heartRate.min { abs($0.date.timeIntervalSince(nowDate)) < abs($1.date.timeIntervalSince(nowDate)) }
            .map { Int($0.bpm.rounded()) }
    }

    /// The reading nearest the playhead — shared by the headline value and the
    /// "other readings" caption so the two can never disagree about which one
    /// is being shown.
    private var nearestBloodPressureReading: BloodPressureReading? {
        vitals.bloodPressure.min { abs($0.date.timeIntervalSince(nowDate)) < abs($1.date.timeIntervalSince(nowDate)) }
    }

    private var nearestBloodPressure: (Int, Int)? {
        nearestBloodPressureReading.map { (Int($0.systolic.rounded()), Int($0.diastolic.rounded())) }
    }
}
