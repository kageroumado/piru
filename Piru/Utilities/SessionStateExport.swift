import Foundation
import SwiftData

/// An immutable snapshot of the person's **current state** — the substances still
/// on board, what each feels like right now (phase, subjective intensity, time to
/// the next phase), and how each is clearing.
///
/// Built once on the main actor from live dose data via ``build(from:colors:now:)``,
/// then handed to the off-main renderers: ``markdown(locale:calendar:)`` for the
/// plain-text export and `SessionReportView` for the PDF. Value types with every
/// `@MainActor` lookup pre-resolved, so both renderers run off the main actor.
///
/// Scope is the **active session only** (`build` returns `nil` when nothing is on
/// board). The **subjective** section is per-dose (each dose's phase is distinct
/// and meaningful), while **elimination** groups redoses of the same substance
/// into one combined PK curve — first-order superposes linearly, alcohol runs the
/// zero-order ceiling model.
struct SessionStateExport {
    let generatedAt: Date
    let sessionStart: Date
    /// Per-dose subjective state.
    let substances: [SubstanceState]
    /// Per-substance combined elimination.
    let eliminations: [EliminationGroup]
    let interactions: [InteractionLine]
    /// `true` when the session is currently active (some dose still on board) —
    /// drives the "right now" chrome (current phase/intensity, now-markers,
    /// generated timestamp). `false` for a historical session, which renders the
    /// same report without any now-relative bits.
    let isLive: Bool

    var isEmpty: Bool {
        substances.isEmpty
    }

    /// Subjective effect phase, mirroring ``DosePhaseProgressBar/Phase``.
    enum Phase: String, CaseIterable {
        case onset
        case comeup
        case peak
        case offset
        case after
    }

    /// The next phase the person will enter, and when.
    struct NextPhase {
        let phase: Phase
        let at: Date
    }

    /// How a substance is clearing (combined across its doses).
    enum Elimination {
        /// First-order (Bateman) clearance from a known half-life.
        case firstOrder(
            halfLifeMinutes: Double,
            amountRemaining: Double,
            fractionRemaining: Double,
            t50: Date,
            t90: Date,
            cleared: Date,
        )
        /// Zero-order (capacity-limited) clearance — alcohol.
        case zeroOrder(
            gramsRemaining: Double,
            fractionRemaining: Double,
            t50: Date,
            t90: Date,
            sober: Date,
        )
        /// No half-life data — elimination can't be modelled for this substance.
        case unknown
    }

    struct SubstanceState: Identifiable {
        let id: UUID
        let name: String
        let colorHex: String
        let amount: Double
        let unit: String
        let route: String
        let doseTimestamp: Date

        /// Subjective — right now.
        let phase: Phase
        /// `0…1` of this dose's own peak (not a measure of impairment).
        let intensity: Double
        /// `0…1` through the effect curve.
        let progress: Double
        let totalMinutes: Double
        /// Cumulative phase-end positions as fractions of `totalMinutes`
        /// `[onsetEnd, comeupEnd, peakEnd, offsetEnd]` — drives the PDF timeline bar.
        let phaseBoundaries: [Double]
        /// `nil` once past the offset (at/after baseline).
        let next: NextPhase?
        let baselineAt: Date
        /// Normalized `0…1` subjective effect over `totalMinutes` (PDF chart).
        let effectCurve: [Double]
    }

    /// One substance's combined elimination — all its active doses superposed.
    struct EliminationGroup: Identifiable {
        let id: String
        let name: String
        let doseCount: Int
        let model: Elimination
        /// Absolute amount in body (``unit``) over `horizonMinutes` measured from
        /// `groupStart`. Empty when unmodellable.
        let curve: [Double]
        let unit: String
        let horizonMinutes: Double
        /// Earliest dose in the group — the curve/decay-table time origin.
        let groupStart: Date
    }

    struct InteractionLine: Identifiable {
        let id: UUID
        let severity: InteractionSeverity
        let a: String
        let b: String
        let detail: String
    }
}

// MARK: - Build (main actor)

extension SessionStateExport {
    private static let effectSamples = 80
    private static let elimSamples = 100
    /// A session counts as "live" only if its most recent still-active dose was
    /// taken within this many hours — otherwise it exports as a historical report.
    private static let liveWindowHours: Double = 18

    @MainActor
    static func build(from allEntries: [DoseEntry], colors: [SubstanceColor], now: Date = .now) -> SessionStateExport? {
        // A currently-active session reports only its live doses ("right now");
        // a session with nothing recent on board reports all its doses as a
        // historical record — same layout, without the now-relative chrome.
        //
        // Liveness requires an active dose taken *recently* (within
        // `liveWindowHours`), not merely one still inside its modeled window: a
        // long-acting compound (a vitamin, a depot) can read as "active" for
        // weeks, which must not make a days-old session render as happening now.
        let active = InteractionChecker.activeEntries(from: allEntries)
        let mostRecentActive = active.map(\.timestamp).max()
        let isLive = mostRecentActive.map { now.timeIntervalSince($0) < liveWindowHours * 3_600 } ?? false
        let working = isLive ? active : allEntries
        guard !working.isEmpty else { return nil }
        let hexMap = colors.hexColorMap

        // Per-dose subjective states.
        var states: [SubstanceState] = []
        for entry in working {
            if let state = makeSubjectiveState(entry: entry, hexMap: hexMap, now: now) {
                states.append(state)
            }
        }
        guard !states.isEmpty else { return nil }
        states.sort { $0.doseTimestamp < $1.doseTimestamp }

        // Elimination grouped by canonical substance name.
        var order: [String] = []
        var groups: [String: (name: String, entries: [DoseEntry])] = [:]
        for entry in working {
            let name = SubstanceLibrary.timelineLookup(entry.substance)?.displayTitle ?? entry.substance
            let key = name.lowercased()
            if groups[key] == nil { order.append(key); groups[key] = (name, []) }
            groups[key]?.entries.append(entry)
        }
        let eliminations = order.compactMap { key -> EliminationGroup? in
            guard let group = groups[key] else { return nil }
            return makeEliminationGroup(name: group.name, entries: group.entries, now: now)
        }

        let names = Array(Set(working.map(\.substance)))
        let workingLower = Set(working.map { $0.substance.lowercased() })
        let lines = InteractionChecker.checkBatch(names, against: working, policy: .explore)
            .filter { workingLower.contains($0.substanceA.lowercased()) && workingLower.contains($0.substanceB.lowercased()) }
            .map { result in
                InteractionLine(
                    id: UUID(),
                    severity: result.severity,
                    a: result.substanceA,
                    b: result.substanceB,
                    detail: cleanDescription(result.description),
                )
            }

        let start = states.map(\.doseTimestamp).min() ?? now
        return SessionStateExport(
            generatedAt: now,
            sessionStart: start,
            substances: states,
            eliminations: eliminations,
            interactions: lines,
            isLive: isLive,
        )
    }

    // MARK: Subjective

    @MainActor
    private static func makeSubjectiveState(entry: DoseEntry, hexMap: [String: String], now: Date) -> SubstanceState? {
        let hex = SubstancePalette.hex(for: entry.substance, hexMap: hexMap)
        guard let curve = ActiveSubstanceState.from(entry: entry, colorHex: hex) else { return nil }

        let elapsed = max(0, now.timeIntervalSince(curve.doseTimestamp) / 60)
        let params = TimelineCurveModel.pkParams(for: curve)
        let total = max(curve.totalMinutes, 1)

        var effect: [Double] = []
        effect.reserveCapacity(effectSamples + 1)
        for i in 0 ... effectSamples {
            let m = Double(i) / Double(effectSamples) * total
            effect.append(TimelineCurveModel.intensity(at: m, for: curve, params: params))
        }

        return SubstanceState(
            id: entry.id,
            name: curve.substanceName,
            colorHex: hex,
            amount: entry.amount,
            unit: entry.unit,
            route: curve.route,
            doseTimestamp: curve.doseTimestamp,
            phase: mapPhase(DosePhaseProgressBar.phase(curve, elapsedMinutes: elapsed)),
            intensity: min(1, max(0, TimelineCurveModel.intensity(at: elapsed, for: curve, params: params))),
            progress: min(1, max(0, elapsed / total)),
            totalMinutes: total,
            phaseBoundaries: [curve.onsetEndMinutes, curve.comeupEndMinutes, curve.peakEndMinutes, curve.offsetEndMinutes].map { min(1, max(0, $0 / total)) },
            next: nextPhase(after: elapsed, curve: curve),
            baselineAt: curve.doseTimestamp.addingTimeInterval(total * 60),
            effectCurve: effect,
        )
    }

    private static func mapPhase(_ phase: DosePhaseProgressBar.Phase) -> Phase {
        switch phase {
        case .onset: .onset
        case .comeup: .comeup
        case .peak: .peak
        case .offset: .offset
        case .after: .after
        }
    }

    private static func nextPhase(after elapsed: Double, curve: ActiveSubstanceState) -> NextPhase? {
        let ts = curve.doseTimestamp
        func at(_ minutes: Double) -> Date {
            ts.addingTimeInterval(minutes * 60)
        }
        if elapsed < curve.onsetEndMinutes { return NextPhase(phase: .comeup, at: at(curve.onsetEndMinutes)) }
        if elapsed < curve.comeupEndMinutes { return NextPhase(phase: .peak, at: at(curve.comeupEndMinutes)) }
        if elapsed < curve.peakEndMinutes { return NextPhase(phase: .offset, at: at(curve.peakEndMinutes)) }
        if elapsed < curve.offsetEndMinutes { return NextPhase(phase: .after, at: at(curve.offsetEndMinutes)) }
        return nil
    }

    // MARK: Elimination (combined per substance)

    /// Per-dose first-order kinetics contributing to a substance's combined curve.
    private struct FirstOrderDose { let offsetMinutes, amount, ke, ka: Double }
    /// Per-dose zero-order (alcohol) contribution.
    private struct ZeroOrderDose { let offsetMinutes, doseMg: Double }

    @MainActor
    private static func makeEliminationGroup(name: String, entries: [DoseEntry], now: Date) -> EliminationGroup? {
        guard let earliest = entries.map(\.timestamp).min() else { return nil }
        let substance = SubstanceLibrary.timelineLookup(entries.first?.substance ?? name)
        let isAlcohol = ["alcohol", "ethanol"].contains(name.lowercased())

        func offset(_ entry: DoseEntry) -> Double {
            entry.timestamp.timeIntervalSince(earliest) / 60
        }

        // Zero-order (alcohol) path.
        if isAlcohol {
            let doses = entries.compactMap { entry -> ZeroOrderDose? in
                guard let mg = TimelineCurveModel.zeroOrderDoseMilligrams(amount: entry.amount, unit: entry.unit) else { return nil }
                return ZeroOrderDose(offsetMinutes: offset(entry), doseMg: mg)
            }
            if !doses.isEmpty {
                return zeroOrderGroup(name: name, doses: doses, groupStart: earliest, doseCount: entries.count, now: now)
            }
        }

        // First-order path.
        guard let halfLife = resolveHalfLife(substance: substance, name: name), halfLife > 0 else {
            return EliminationGroup(id: name.lowercased(), name: name, doseCount: entries.count, model: .unknown, curve: [], unit: entries.first?.unit ?? "mg", horizonMinutes: 1, groupStart: earliest)
        }
        let ke = PKModel.ke(fromHalfLifeMinutes: halfLife)
        let doses = entries.map { entry in
            FirstOrderDose(offsetMinutes: offset(entry), amount: entry.amount, ke: ke, ka: resolveKa(substance: substance, route: entry.route, ke: ke))
        }
        return firstOrderGroup(name: name, halfLife: halfLife, doses: doses, unit: entries.first?.unit ?? "mg", groupStart: earliest, doseCount: entries.count, now: now)
    }

    private static func firstOrderGroup(name: String, halfLife: Double, doses: [FirstOrderDose], unit: String, groupStart: Date, doseCount: Int, now: Date) -> EliminationGroup {
        let totalDosed = doses.reduce(0) { $0 + $1.amount }
        func body(_ global: Double) -> Double {
            doses.reduce(0.0) { acc, dose in
                let t = global - dose.offsetMinutes
                return t >= 0 ? acc + dose.amount * PKModel.fractionRemainingInBody(at: t, ke: dose.ke, ka: dose.ka) : acc
            }
        }
        let maxOffset = doses.map(\.offsetMinutes).max() ?? 0
        let cap = maxOffset + halfLife * 20
        let cross = crossings(body: body, total: totalDosed, targets: [0.5, 0.1, 0.03], cap: cap)
        let horizon = max(cross[2], 1)
        let nowGlobal = max(0, now.timeIntervalSince(groupStart) / 60)
        let remaining = body(nowGlobal)

        return EliminationGroup(
            id: name.lowercased(),
            name: name,
            doseCount: doseCount,
            model: .firstOrder(
                halfLifeMinutes: halfLife,
                amountRemaining: remaining,
                fractionRemaining: totalDosed > 0 ? min(1, remaining / totalDosed) : 0,
                t50: groupStart.addingTimeInterval(cross[0] * 60),
                t90: groupStart.addingTimeInterval(cross[1] * 60),
                cleared: groupStart.addingTimeInterval(cross[2] * 60),
            ),
            curve: sampleCurve(body: body, horizon: horizon),
            unit: unit,
            horizonMinutes: horizon,
            groupStart: groupStart,
        )
    }

    private static func zeroOrderGroup(name: String, doses: [ZeroOrderDose], groupStart: Date, doseCount: Int, now: Date) -> EliminationGroup {
        let kinetics = PKModel.ethanolZeroOrder
        let totalGrams = doses.reduce(0.0) { $0 + $1.doseMg } / 1_000
        func body(_ global: Double) -> Double { // grams
            doses.reduce(0.0) { acc, dose in
                let t = global - dose.offsetMinutes
                return t >= 0 ? acc + PKModel.zeroOrderBodyContent(doseMg: dose.doseMg, at: t, kinetics: kinetics) / 1_000 : acc
            }
        }
        let maxOffset = doses.map(\.offsetMinutes).max() ?? 0
        let cap = maxOffset + totalGrams * 1_000 / kinetics.vmaxMgPerMin + 180
        let cross = crossings(body: body, total: totalGrams, targets: [0.5, 0.1, 0.02], cap: cap)
        let horizon = max(cross[2], 1)
        let nowGlobal = max(0, now.timeIntervalSince(groupStart) / 60)
        let remaining = body(nowGlobal)

        return EliminationGroup(
            id: name.lowercased(),
            name: name,
            doseCount: doseCount,
            model: .zeroOrder(
                gramsRemaining: remaining,
                fractionRemaining: totalGrams > 0 ? min(1, remaining / totalGrams) : 0,
                t50: groupStart.addingTimeInterval(cross[0] * 60),
                t90: groupStart.addingTimeInterval(cross[1] * 60),
                sober: groupStart.addingTimeInterval(cross[2] * 60),
            ),
            curve: sampleCurve(body: body, horizon: horizon),
            unit: "g",
            horizonMinutes: horizon,
            groupStart: groupStart,
        )
    }

    /// Global-time crossings: for each `target` fraction of `total`, the first
    /// minute *after the combined peak* at which body-load falls to that level.
    private static func crossings(body: (Double) -> Double, total: Double, targets: [Double], cap: Double) -> [Double] {
        guard total > 0, cap > 0 else { return targets.map { _ in cap } }
        let step = max(1.0, cap / 4_000)
        var peakGlobal = 0.0
        var peakValue = body(0)
        var global = 0.0
        while global <= cap {
            let value = body(global)
            if value > peakValue { peakValue = value; peakGlobal = global }
            global += step
        }
        return targets.map { target in
            let threshold = target * total
            var t = peakGlobal
            while t <= cap {
                if body(t) <= threshold { return t }
                t += step
            }
            return cap
        }
    }

    private static func sampleCurve(body: (Double) -> Double, horizon: Double) -> [Double] {
        var samples: [Double] = []
        samples.reserveCapacity(elimSamples + 1)
        for i in 0 ... elimSamples {
            samples.append(body(Double(i) / Double(elimSamples) * horizon))
        }
        return samples
    }

    // MARK: Resolution helpers (mirror ActiveSubstanceCalculator)

    private static func resolveHalfLife(substance: Substance?, name: String) -> Double? {
        if let substance, let hl = ActiveSubstanceState.resolveHalfLifeMinutes(substance: substance, name: name) {
            return hl
        }
        if let hl = HalfLifeDatabase.halfLife(for: name), hl > 0 { return hl }
        return nil
    }

    private static func resolveKa(substance: Substance?, route: RouteOfAdministration, ke: Double) -> Double {
        if let substance, let duration = substance.resolveDuration(for: route) {
            let timeToPeak = (duration.onset?.midpoint ?? 0) + (duration.comeup?.midpoint ?? 0)
            return timeToPeak > 0 ? PKModel.estimateKa(timeToPeak: timeToPeak, ke: ke) : PKModel.defaultKa(ke: ke)
        }
        return PKModel.defaultKa(ke: ke)
    }

    /// Trim raw CYP/FDA-label fragments from an interaction description, matching
    /// the cleanup the medical PDF does, so exported text stays readable.
    private static func cleanDescription(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let end = trimmed.firstIndex(where: { $0 == "." }) {
            let first = String(trimmed[..<end]).trimmingCharacters(in: .whitespaces)
            if first.count >= 12 { return first + "." }
        }
        return trimmed
    }
}
