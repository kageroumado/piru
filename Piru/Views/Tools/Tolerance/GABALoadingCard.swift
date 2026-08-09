import Charts
import SwiftData
import SwiftUI

/// The receptor-loading insight for the GABA card: a single **relative GABA-A load** curve over a few
/// recent days through forward clearance, summed across every active GABAergic (competitive drive,
/// metabolite tails included), expressed as a fraction of the user's recent peak. It shows the thing the
/// per-session and interaction views can't — that several benzodiazepines (plus alcohol, plus a
/// lingering metabolite) load *one* receptor, and how loaded it is right now. Relative, not absolute
/// occupancy: benzodiazepine occupancy saturates, so an absolute curve would be a flat ~100% plateau.
/// Reads ``ToleranceStore/loadTrail(for:from:now:pastHorizon:horizon:step:)``; renders nothing when
/// there is no meaningful current or recent load.
struct GABALoadingCard: View {
    let entries: [DoseEntry]
    /// The GABA card's (already relevance-filtered) contributors — used only to note when alcohol, which
    /// loads GABA-A at a different site, is part of the summed curve.
    let contributors: [String]
    let color: Color

    @State private var trail: [LoadPoint] = []

    private struct LoadPoint: Identifiable {
        let date: Date
        let load: Double
        var id: Date {
            date
        }
    }

    /// Past window shown before "now", so the recent doses loading the receptor are visible (not just the
    /// decay tail), and the forward window over which it clears.
    private static let pastHorizon: TimeInterval = 4 * 86_400
    private static let horizon: TimeInterval = 14 * 86_400
    private static let step: TimeInterval = 2 * 3_600
    /// Below this peak load there's nothing worth a chart — the card hides itself.
    private static let visibilityFloor = 0.05

    private var peakLoad: Double {
        trail.map(\.load).max() ?? 0
    }

    /// The sample nearest "now" — the current load readout, kept consistent with the plotted curve.
    private var loadNow: Double {
        let now = Date.now
        return trail.min { abs($0.date.timeIntervalSince(now)) < abs($1.date.timeIntervalSince(now)) }?.load ?? 0
    }

    private var includesAlcohol: Bool {
        contributors.contains { $0.range(of: "alcohol", options: .caseInsensitive) != nil || $0.range(of: "ethanol", options: .caseInsensitive) != nil }
    }

    var body: some View {
        Group {
            if peakLoad >= Self.visibilityFloor {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Receptor load")
                            .font(.headline)
                        Spacer()
                        PredictionCapsule()
                    }
                    Text("About \(Int((loadNow * 100).rounded()))% of your recent peak GABA-A load right now, summed across everything active.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)

                    chart

                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                .padding(.vertical, 6)
            }
        }
        .task(id: entries.count) {
            let raw = await ToleranceStore.shared.loadTrail(
                for: .gaba, from: entries, pastHorizon: Self.pastHorizon, horizon: Self.horizon, step: Self.step,
            )
            trail = raw.map { LoadPoint(date: $0.date, load: $0.load) }
        }
    }

    private var caption: LocalizedStringResource {
        includesAlcohol
            ? "Combined load across your active GABAergics, relative to your recent peak. Alcohol is included; it loads the receptor at a different site."
            : "Combined load across your active GABAergics, relative to your recent peak."
    }

    private var chart: some View {
        Chart(trail) { point in
            AreaMark(
                x: .value("Time", point.date),
                y: .value("Load", point.load * 100),
            )
            .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Time", point.date),
                y: .value("Load", point.load * 100),
            )
            .foregroundStyle(color)
            .interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0 ... 100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let percent = value.as(Int.self) {
                        Text("\(percent)%")
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let x = proxy.position(forX: Date.now), let plot = proxy.plotFrame.map({ geo[$0] }) {
                    Rectangle()
                        .fill(Theme.secondaryLabel.opacity(0.45))
                        .frame(width: 1, height: plot.height)
                        .position(x: plot.minX + x, y: plot.midY)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(height: 150)
        .chartSummaryAccessibility(
            label: Text("GABA-A receptor load over time"),
            value: Text("Combined load relative to your recent peak, currently about \(Int((loadNow * 100).rounded())) percent, clearing over the following days."),
        )
    }
}
