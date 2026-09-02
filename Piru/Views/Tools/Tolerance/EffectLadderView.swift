import SwiftUI

/// The **effect ladder** — the differential-tolerance replacement for the single gauge on an
/// effect-selective class (GABA, α2δ). One row per effect, each a bar of how much tolerance that effect
/// has built at your usual dose, sorted most-toleranced first and grouped Faded / Unchanged. The gap
/// between the top and bottom rows *is* the finding: the dose that no longer sedates impairs you exactly
/// as much as day one.
///
/// Design constraints (from `Specs/prototypes/benzo-tolerance/index.html`): one axis with one meaning, so
/// rows are comparable — and the same meaning as every other tolerance bar in the app, an empty track is
/// no tolerance; color encodes the effect's *kind* (felt vs impairment), never its rank, so re-sorting
/// never repaints a row; grouped by outcome, not valence (Piru doesn't know whether a faded effect is a
/// loss or a relief).
struct EffectLadderView: View {
    let snapshot: ClassTolerance

    private var rows: [EffectLadderRow] {
        let params = ReceptorClasses.parameters(for: snapshot.receptorClass)
        var out: [EffectLadderRow] = []
        if let primary = params.primaryEffectAxis, let fraction = snapshot.responseFraction(forEffect: primary) {
            out.append(EffectLadderRow(axis: primary, responseFraction: fraction))
        }
        for endpoint in params.effectEndpoints {
            if let fraction = snapshot.responseFraction(forEffect: endpoint.axis) {
                out.append(EffectLadderRow(axis: endpoint.axis, responseFraction: fraction))
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
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            ForEach(rows) { row in
                EffectLadderRowView(row: row)
            }
        }
    }
}

/// One ladder row: an effect and how much of it is left at the usual dose.
private struct EffectLadderRow: Identifiable {
    let axis: ReceptorClasses.EffectAxis
    let responseFraction: Double
    var id: ReceptorClasses.EffectAxis {
        axis
    }
    /// Below 80% left counts as faded — the grouping threshold.
    var faded: Bool {
        responseFraction < 0.8
    }
    /// The bar's fill: how much tolerance the effect has built, so an unchanged effect is an empty track.
    var toleranceFraction: Double {
        max(0, min(1, 1 - responseFraction))
    }
    /// Blue for effects you notice, amber for impairments that don't announce themselves.
    var color: Color {
        axis.kind == .impairment ? .orange : .blue
    }
}

private struct EffectLadderRowView: View {
    let row: EffectLadderRow

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(row.axis.displayName)
                .font(.subheadline)
            track
        }
    }

    private var track: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(Theme.Opacity.tintActive))
                Capsule()
                    .fill(row.color.opacity(Theme.Opacity.dimmed))
                    .frame(width: geo.size.width * row.toleranceFraction)
            }
        }
        .frame(height: 9)
        .accessibilityElement()
        .accessibilityLabel(row.axis.displayName)
        .accessibilityValue(Text("\(Int((row.toleranceFraction * 100).rounded())) percent tolerance"))
    }
}
