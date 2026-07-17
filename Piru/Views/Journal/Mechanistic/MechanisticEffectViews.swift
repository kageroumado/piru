import SwiftUI

// MARK: - Vitals cards (Safety lens)

/// Heart-rate & blood-pressure cards paired with the Safety lens — the
/// harm-reduction payoff (real Apple Health readings alongside predicted cost).
struct MechanisticVitalsCards: View {
    let vitals: SessionVitals
    let startDate: Date
    let nowHours: Double

    var body: some View {
        HStack(spacing: 10) {
            if let bpm = nearestHeartRate {
                vitalCard(icon: "heart.fill", tint: EffectLens.crash, title: "Heart rate", value: "\(bpm)", unit: "bpm")
            }
            if let bp = nearestBloodPressure {
                vitalCard(icon: "waveform.path.ecg", tint: .blue, title: "Blood pressure", value: "\(bp.0)/\(bp.1)", unit: "mmHg")
            }
        }
    }

    private func vitalCard(icon: String, tint: Color, title: LocalizedStringKey, value: String, unit: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .tint(tint)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title2.bold())
                Text(unit).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        // One utterance per card ("Heart rate, 72 bpm"), not four fragments.
        .accessibilityElement(children: .combine)
    }

    private var nowDate: Date {
        startDate.addingTimeInterval(nowHours * 3_600)
    }

    private var nearestHeartRate: Int? {
        vitals.heartRate.min { abs($0.date.timeIntervalSince(nowDate)) < abs($1.date.timeIntervalSince(nowDate)) }
            .map { Int($0.bpm.rounded()) }
    }

    private var nearestBloodPressure: (Int, Int)? {
        vitals.bloodPressure.min { abs($0.date.timeIntervalSince(nowDate)) < abs($1.date.timeIntervalSince(nowDate)) }
            .map { (Int($0.systolic.rounded()), Int($0.diastolic.rounded())) }
    }
}
