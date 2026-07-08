import SwiftUI

// MARK: - Lens bar (the one pill row, below the graph)

/// The horizontally-scrolling lens selector shown *below* the session graph.
/// Reuses the Journal tag-pill look (tinted capsule), upgraded to a per-lens
/// icon that reflects the current state (happy vs flat face, full vs slashed
/// bolt, …) plus a label. Tapping switches the graph above.
struct LensBar: View {
    @Binding var lens: EffectLens
    let lenses: [EffectLens]
    /// Simulated timeline, for the state icons. `nil` until computed.
    let result: MechanisticSessionModel.Result?
    let nowHours: Double

    var body: some View {
        // Pinned above the graph, edge-to-edge like the Journal tag bar: a plain
        // horizontal ScrollView (NOT a grouped-list row, which would inset it
        // ~20pt and clip the pills to rounded corners). The 16pt inner padding
        // lands the first pill on the list's leading edge; the scroll view clips
        // flat at the screen edges as the pills run off.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(lenses) { candidate in
                    pill(candidate)
                }
            }
            // 20pt matches the grouped-list content margin, so the first pill
            // lines up with the dose rows below.
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private func pill(_ candidate: EffectLens) -> some View {
        let value: Double? = candidate.channel != nil ? result.map { $0.value(of: candidate, atHour: min(nowHours, $0.tMax)) } : nil
        let state = candidate.state(value: value)
        let iconColor = state.isNegative ? EffectLens.crash : candidate.color
        let isSelected = candidate == lens
        return Button {
            withAnimation(.snappy(duration: 0.25)) { lens = candidate }
        } label: {
            // Coloured icon + neutral label — the one case the design checklist
            // permits an HStack over Label (per-element styling differs).
            HStack(spacing: 5) {
                Image(systemName: state.symbol)
                    .foregroundStyle(iconColor)
                    .imageScale(.small)
                Text(candidate.label)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background {
                Capsule().fill(isSelected ? candidate.color.opacity(0.16) : Color(.secondarySystemFill))
            }
            .overlay {
                if isSelected {
                    Capsule().strokeBorder(candidate.color.opacity(0.5), lineWidth: 1.2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(candidate.label))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

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
