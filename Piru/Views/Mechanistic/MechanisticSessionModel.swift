import Foundation
import SwiftUI

/// Bridges a logged session to the mechanistic ``EffectEngine``: resolves each
/// dose's pharmacology, runs one multi-substance simulation, and packages the
/// felt-effect timeline with the fixed per-axis ranges and dose marks the chart
/// needs. Pure/off-main compute, memoized like `TimelineModelCache`.
///
/// Ports the driver in the `app-timeline` prototype (`gen-app.mjs`): route →
/// (`ka` multiplier, redistribution `kR`), `amt = dose / refUnit`, session-wide
/// axis ranges so scrolling never rescales the curve.
nonisolated enum MechanisticSessionModel {
    /// One dose, reduced to the Sendable facts the engine needs. Built on the
    /// main actor (needs `SubstanceLibrary`), then handed to an off-main compute.
    struct DoseInput: Hashable {
        let name: String
        let category: SubstanceCategory
        let amount: Double
        let route: RouteOfAdministration
        /// Hours since the session start (the engine's `t = 0`).
        let hours: Double
        let colorHex: String
    }

    /// A dose event positioned on the chart's time axis.
    struct DoseMark: Hashable {
        let hours: Double
        let colorHex: String
    }

    /// Fixed hi/lo bounds for one axis over the whole session.
    struct AxisRange: Hashable {
        let hi: Double
        let lo: Double
        var span: Double {
            max(hi - lo, 0.0001)
        }
    }

    /// Everything the chart renders for a modeled session.
    struct Result {
        let timeline: EffectTimeline
        let doseMarks: [DoseMark]
        /// Keyed by ``EffectLens/rawValue`` (mechanistic lenses only).
        let ranges: [String: AxisRange]
        /// At least one substance fell back to a class analogue (flag it in UI).
        let usesAnalogue: Bool
        let tMax: Double
        /// Last hour any mechanistic channel is still meaningfully active. Unlike
        /// ``tMax`` (padded to ≥12h so the curve has room), this is the *real*
        /// content extent — the window and scroller frame it, so a short session
        /// fits fully and shows no scroller.
        let contentSpan: Double

        /// The value of a lens's channel nearest a given hour.
        func value(of lens: EffectLens, atHour hour: Double) -> Double {
            guard let channel = lens.channel else { return 0 }
            let series = timeline[keyPath: channel]
            guard !series.isEmpty else { return 0 }
            var best = 0
            var bestDelta = Double.greatestFiniteMagnitude
            for (i, t) in timeline.t.enumerated() {
                let delta = abs(t - hour)
                if delta < bestDelta { bestDelta = delta; best = i }
            }
            return series[best]
        }
    }

    // MARK: - Route pharmacokinetics

    /// Route → (`ka` absorption multiplier, `kR` two-compartment redistribution).
    /// Faster routes (insufflation, inhalation, IV) spike then redistribute out
    /// of the brain, producing the rush-and-drop the model reads.
    static func roaFactors(_ route: RouteOfAdministration) -> (kaMul: Double, kR: Double) {
        switch route {
        case .oral: (1, 0)
        case .sublingual: (2, 1)
        case .insufflation: (3.5, 2.5)
        case .inhalation: (10, 6)
        case .intravenous: (10, 6)
        case .intramuscular: (4, 2)
        case .subcutaneous: (3, 1.5)
        case .transdermal: (0.5, 0)
        case .rectal: (3, 1.5)
        case .other: (1, 0)
        }
    }

    // MARK: - Gating

    /// Whether these doses contain a stimulant or opioid the engine models —
    /// the trigger for surfacing the mechanistic lenses at all.
    static func supportsMechanisticView(_ doses: [DoseInput]) -> Bool {
        SubstanceModelDatabase.supportsMechanisticView(doses.map { ($0.name, $0.category) })
    }

    // MARK: - Compute (off-main)

    /// Simulate the session. `nil` when nothing in it is modelable — the caller
    /// then shows only the classic Timeline lens.
    static func compute(doses: [DoseInput], tMax: Double) -> Result? {
        // Group by (substance, route): one agent per distinct substance-route,
        // carrying all of its doses — different routes of the same drug become
        // separate agents (different ka/kR), summed inside the simulation.
        struct GroupKey: Hashable { let name: String; let route: RouteOfAdministration }
        var groups: [GroupKey: [DoseInput]] = [:]
        var order: [GroupKey] = []
        for dose in doses {
            let key = GroupKey(name: SubstanceModelDatabase.normalize(dose.name), route: dose.route)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(dose)
        }

        var agents: [EffectAgent] = []
        var usesAnalogue = false
        for key in order {
            guard let members = groups[key], let first = members.first,
                  let resolution = SubstanceModelDatabase.resolve(name: first.name, category: first.category)
            else { continue }
            if case .analogue = resolution.source { usesAnalogue = true }
            let params = resolution.params
            let (kaMul, kR) = roaFactors(key.route)
            let doseTuples = members.map { (t: $0.hours, amt: $0.amount / params.refUnit) }
            agents.append(EffectAgent(
                params: params,
                doses: doseTuples,
                ka: kaMul != 1 ? params.ka * kaMul : nil,
                kR: kR,
            ))
        }
        guard !agents.isEmpty else { return nil }

        let timeline = EffectEngine.simulate(EffectParams(), agents: agents, tMax: tMax)

        // Fixed session-wide ranges per mechanistic axis, so scrolling the
        // window never rescales the curve and magnitudes stay comparable.
        var ranges: [String: AxisRange] = [:]
        for lens in EffectLens.mechanistic {
            guard let channel = lens.channel else { continue }
            let series = timeline[keyPath: channel]
            var hi = 0.25
            var lo = 0.0
            for value in series {
                if value > hi { hi = value }
                if value < lo { lo = value }
            }
            ranges[lens.rawValue] = AxisRange(hi: hi * 1.1, lo: lens.isSigned ? lo * 1.12 : 0)
        }

        let marks = doses.map { DoseMark(hours: $0.hours, colorHex: $0.colorHex) }

        // Real content extent: the last hour any mechanistic channel is still
        // meaningfully active (or the last dose). The window/scroller frame this,
        // not the padded `tMax`, so short sessions fit whole and hide the scroller.
        var contentSpan = doses.map(\.hours).max() ?? 0
        for lens in EffectLens.mechanistic {
            guard let channel = lens.channel else { continue }
            let series = timeline[keyPath: channel]
            guard series.count == timeline.t.count else { continue }
            let threshold = (ranges[lens.rawValue]?.hi ?? 0.25) * 0.04
            for i in stride(from: series.count - 1, through: 0, by: -1) where abs(series[i]) > threshold {
                contentSpan = max(contentSpan, timeline.t[i])
                break
            }
        }
        contentSpan = min(max(contentSpan + 0.5, 1), tMax)

        return Result(timeline: timeline, doseMarks: marks, ranges: ranges, usesAnalogue: usesAnalogue, tMax: tMax, contentSpan: contentSpan)
    }
}

// MARK: - Off-main memoization

/// A small bounded LRU of computed session results, keyed by a dose signature —
/// mirrors `TimelineModelCache` so re-opening a session, toggling lenses, or a
/// parent redraw all hit the cache instead of re-simulating.
@MainActor
final class MechanisticModelCache {
    static let shared = MechanisticModelCache()

    private var store: [Int: MechanisticSessionModel.Result] = [:]
    private var order: [Int] = []
    private let limit = 60

    func cached(_ key: Int) -> MechanisticSessionModel.Result? {
        guard let value = store[key] else { return nil }
        if let idx = order.firstIndex(of: key) {
            order.remove(at: idx)
            order.append(key)
        }
        return value
    }

    func insert(_ key: Int, _ value: MechanisticSessionModel.Result) {
        if store[key] == nil { order.append(key) }
        store[key] = value
        while order.count > limit {
            let evict = order.removeFirst()
            store[evict] = nil
        }
    }
}
