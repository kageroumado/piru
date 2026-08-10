import SwiftUI

/// The **effect ladder** — the differential-tolerance replacement for the single gauge on an
/// effect-selective class (GABA, α2δ). One row per effect on a shared "% of naïve effect left at your
/// usual dose" axis, sorted most-faded first and grouped Faded / Unchanged. The gap between the top and
/// bottom rows *is* the finding: the dose that no longer sedates impairs you exactly as much as day one.
///
/// Design constraints (from `Specs/prototypes/benzo-tolerance/index.html`): one axis with one meaning, so
/// rows are comparable; color encodes the effect's *kind* (felt vs impairment), never its rank, so
/// re-sorting never repaints a row; grouped by outcome, not valence (Piru doesn't know whether a faded
/// effect is a loss or a relief); and a per-row evidence tier, because "no tolerance detected" and "not
/// measured" must not look alike.
struct EffectLadderView: View {
    let snapshot: ClassTolerance
    let tier: UserProfile

    private var rows: [EffectLadderRow] {
        let params = ReceptorClasses.parameters(for: snapshot.receptorClass)
        var out: [EffectLadderRow] = []
        if let primary = params.primaryEffectAxis, let fraction = snapshot.responseFraction(forEffect: primary) {
            out.append(EffectLadderRow(axis: primary, responseFraction: fraction, evidenceTier: params.confidence))
        }
        for endpoint in params.effectEndpoints {
            if let fraction = snapshot.responseFraction(forEffect: endpoint.axis) {
                out.append(EffectLadderRow(axis: endpoint.axis, responseFraction: fraction, evidenceTier: endpoint.evidenceTier))
            }
        }
        return out.sorted { $0.responseFraction < $1.responseFraction }
    }

    var body: some View {
        let all = rows
        let faded = all.filter(\.faded)
        let intact = all.filter { !$0.faded }
        VStack(alignment: .leading, spacing: 14) {
            if !faded.isEmpty {
                group("Faded", faded)
            }
            if !intact.isEmpty {
                group("Unchanged", intact)
            }
        }
    }

    private func group(_ title: LocalizedStringResource, _ rows: [EffectLadderRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            ForEach(rows) { row in
                EffectLadderRowView(row: row, showsDetail: tier != .casual)
            }
        }
    }
}

/// One ladder row: an effect, how much of it is left at the usual dose, and the confidence in that.
private struct EffectLadderRow: Identifiable {
    let axis: ReceptorClasses.EffectAxis
    let responseFraction: Double
    let evidenceTier: ConfidenceTier
    var id: ReceptorClasses.EffectAxis {
        axis
    }
    /// Below 80% left counts as faded — the grouping threshold.
    var faded: Bool {
        responseFraction < 0.8
    }
    /// Blue for effects you notice, amber for impairments that don't announce themselves.
    var color: Color {
        axis.kind == .impairment ? .orange : .blue
    }
}

private struct EffectLadderRowView: View {
    let row: EffectLadderRow
    let showsDetail: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.axis.displayName)
                    .font(.subheadline)
                Spacer(minLength: 8)
                Text("\(Int((row.responseFraction * 100).rounded()))% left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(row.color)
                    .monospacedDigit()
            }
            track
            if showsDetail {
                HStack(spacing: 8) {
                    Text(tierLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .textCase(.uppercase)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(Theme.secondaryLabel)
                    Text(row.axis.courseNote)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
    }

    private var track: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(row.color)
                    .frame(width: max(2, geo.size.width * row.responseFraction))
            }
        }
        .frame(height: 9)
        .accessibilityElement()
        .accessibilityLabel(row.axis.displayName)
        .accessibilityValue(Text("\(Int((row.responseFraction * 100).rounded())) percent left"))
    }

    private var tierLabel: LocalizedStringResource {
        switch row.evidenceTier {
        case .high: "strong evidence"
        case .medium: "moderate evidence"
        case .low: "low evidence"
        case .unverified: "not measured"
        }
    }
}
