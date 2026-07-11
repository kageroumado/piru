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
    /// Deliberately carries **no color** — its hash keys the simulation cache
    /// and the recompute task, and a recolor must not trigger a re-simulate
    /// (dose marks get their color at the render site instead).
    struct DoseInput: Hashable {
        let name: String
        let amount: Double
        let route: RouteOfAdministration
        /// Hours since the session start (the engine's `t = 0`).
        let hours: Double
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

    /// Everything the chart renders for a modeled session (dose marks are
    /// supplied separately by the host, so recolors don't touch this cache).
    struct Result {
        let timeline: EffectTimeline
        /// Keyed by ``EffectLens/rawValue`` (mechanistic lenses only).
        let ranges: [String: AxisRange]
        let tMax: Double
        /// Last hour any mechanistic channel is still meaningfully active. Unlike
        /// ``tMax`` (padded to ≥12h so the curve has room), this is the *real*
        /// content extent — the window and scroller frame it, so a short session
        /// fits fully and shows no scroller.
        let contentSpan: Double

        /// The value of a lens's channel nearest a given hour. `timeline.t` is
        /// monotonically increasing, so binary-search — this runs per lens pill
        /// per render and inside every Canvas pass.
        func value(of lens: EffectLens, atHour hour: Double) -> Double {
            guard let channel = lens.channel else { return 0 }
            let series = timeline[keyPath: channel]
            let t = timeline.t
            guard !series.isEmpty, series.count == t.count else { return 0 }
            var lo = 0
            var hi = t.count - 1
            while lo < hi {
                let mid = (lo + hi) / 2
                if t[mid] < hour { lo = mid + 1 } else { hi = mid }
            }
            // `lo` is the first index with t >= hour; its predecessor may be nearer.
            if lo > 0, abs(t[lo - 1] - hour) <= abs(t[lo] - hour) { lo -= 1 }
            return series[lo]
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

    // MARK: - Params resolution

    /// The engine params for one dose, resolved against the session's pharmacology
    /// map (keyed by normalized name). `nil` ⇒ the substance isn't modelable.
    private static func modelParams(for name: String, in pharmacology: [String: PharmacologyParameters]) -> SubstanceModelParams? {
        SubstanceModelDatabase.params(name: name, pharmacology: pharmacology[SubstanceModelDatabase.normalize(name)])
    }

    // MARK: - Gating

    /// Whether the session contains at least one substance the engine was **calibrated** on —
    /// the trigger for surfacing the mechanistic lenses at all. A stimulant/opioid the engine can
    /// merely *simulate* (methamphetamine, cocaine, kratom, MDMA) is not enough: those shape the
    /// curves as interacting agents once a calibrated substance is present, but their solo precision
    /// is too low to anchor the model. Requires both a calibrated identity and resolvable model
    /// params (defensive — a calibrated substance whose DB row went missing shouldn't trigger).
    static func supportsMechanisticView(_ doses: [DoseInput], pharmacology: [String: PharmacologyParameters]) -> Bool {
        doses.contains { dose in
            guard SubstanceModelDatabase.isCalibratedTrigger(dose.name),
                  let params = modelParams(for: dose.name, in: pharmacology) else { return false }
            return SubstanceModelDatabase.triggersMechanisticView(params)
        }
    }

    // MARK: - Compute (off-main)

    /// Simulate the session. `nil` when nothing in it is modelable — the caller
    /// then shows only the classic Timeline lens. `pharmacology` is the resolved
    /// per-substance PK + binding (keyed by normalized name), resolved on the main
    /// actor by the caller and handed to this off-main compute.
    static func compute(doses: [DoseInput], pharmacology: [String: PharmacologyParameters], tMax: Double) -> Result? {
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
        for key in order {
            guard let members = groups[key], let first = members.first,
                  let params = modelParams(for: first.name, in: pharmacology)
            else { continue }
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

        // Fixed session-wide ranges per mechanistic axis. The axis is anchored to
        // a **semi-absolute** reference (``EffectLens/referenceScale``) rather than
        // to each session's own peak: a mild session reads visually mild, and
        // heights are comparable across sessions and lenses. The anchor only grows
        // when a session genuinely overshoots it (too euphoric / too much strain to
        // fit), so the curve is never clipped. The signed lenses always keep the
        // reference floor, reserving comedown room so the baseline reads clearly
        // horizontal even when nothing dips below it.
        var ranges: [String: AxisRange] = [:]
        for lens in EffectLens.mechanistic {
            guard let channel = lens.channel else { continue }
            let series = timeline[keyPath: channel]
            let anchor = lens.referenceScale
            var hi = anchor.hi
            var lo = anchor.lo
            for value in series {
                if value > hi { hi = value }
                if value < lo { lo = value }
            }
            ranges[lens.rawValue] = AxisRange(hi: hi * 1.06, lo: lens.isSigned ? lo * 1.08 : 0)
        }

        // Real content extent: the last hour any mechanistic channel is still
        // meaningfully active (or the last dose). The window/scroller frame this,
        // not the padded `tMax`, so short sessions fit whole and hide the scroller.
        var contentSpan = doses.map(\.hours).max() ?? 0
        for lens in EffectLens.mechanistic {
            guard let channel = lens.channel else { continue }
            let series = timeline[keyPath: channel]
            guard series.count == timeline.t.count else { continue }
            // Tie the "still meaningfully active" threshold to this channel's own
            // peak, not the (now anchored) axis `hi` — otherwise a mild session,
            // whose peak sits well below the fixed anchor, would have its tail
            // judged inactive too early and get truncated.
            let seriesPeak = series.reduce(0.0) { max($0, abs($1)) }
            let threshold = max(seriesPeak * 0.04, 0.02)
            for i in stride(from: series.count - 1, through: 0, by: -1) where abs(series[i]) > threshold {
                contentSpan = max(contentSpan, timeline.t[i])
                break
            }
        }
        contentSpan = min(max(contentSpan + 0.5, 1), tMax)

        return Result(timeline: timeline, ranges: ranges, tMax: tMax, contentSpan: contentSpan)
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
