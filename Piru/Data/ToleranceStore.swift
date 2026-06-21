import Foundation
import SwiftData

/// A snapshot of tolerance state at one receptor target, derived by replaying the dose log. The
/// value type the UI reads (Stage 2); the SwiftData ``ToleranceState`` row is its cached persistence.
struct TargetTolerance: Hashable, Identifiable {
    let target: String
    let receptorClass: ReceptorClasses.ReceptorClass
    /// Slow availability `A_R` ∈ [0, 1] — 1 = naïve/rested.
    let availability: Double
    /// Within-session acute (redose) pool ∈ [0, 1].
    let acute: Double
    /// Allostatic load (ordinal recovery-state indicator; never an effect multiplier).
    let load: Double
    /// Weakest-link confidence across the contributing substances' occupancy inputs and the class
    /// kinetics — the house "predicted (model, confidence)" tier.
    let confidence: ConfidenceTier

    var id: String {
        target
    }
}

/// Owns the user's **per-target tolerance state**, recomputed by replaying the dose log through
/// ``PDModel`` — the lead thread of `Specs/pharmacology-axis-meta-plan.md` (Stage 1).
///
/// ## Why replay, not increment
/// Tolerance is computed by *integrating the whole dose log* on demand (like
/// ``ActiveSubstanceCalculator``), not by mutating a running value per dose. That makes it
/// deterministic and trivially testable (the gate is literally a replay of a synthetic log), immune
/// to out-of-order edits/back-dated doses, and free of drift. The persisted ``ToleranceState`` rows
/// are a *cache* of the latest replay so the UI/widget can read a current number without re-walking
/// history.
///
/// ## SwiftData isolation gotchas (carried over from `UserProfileStore`)
/// The `ModelContainer`/`ModelContext` are held ``ObservationIgnored`` — storing a SwiftData type as
/// an observation-tracked property of an `@Observable` drags in `_SwiftData_SwiftUI` and traps on
/// mutate. Views observe the plain ``states`` dictionary instead. The store also **retains its
/// container** (a `ModelContext` does not), or inserts trap on an orphaned container.
@Observable
@MainActor
final class ToleranceStore {
    static let shared = ToleranceStore()

    /// Default integration timestep (minutes). The closed-form ``PDModel/stepAvailability`` is exact
    /// for piecewise-constant occupancy, so a coarse grid stays accurate; 30 min balances fidelity
    /// against the cost of replaying a long history.
    static let defaultTimestepMinutes = 30.0

    /// How far back the replay reaches. Beyond the longest recovery/decay τ (a few months) a dose's
    /// contribution has decayed to nothing, so older history is dropped to bound the work.
    static let defaultLookbackDays = 547.0 // ~18 months

    /// Current per-target tolerance snapshot, keyed by target. Observation-tracked; views read this.
    private(set) var states: [String: TargetTolerance] = [:]

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var context: ModelContext?

    /// Public for the test seam; production uses ``shared``.
    init() {}

    // MARK: - Lifecycle

    /// Bind to the app's shared container and load the last cached snapshot. Call once at launch.
    func configure(container: ModelContainer) {
        self.container = container
        context = ModelContext(container)
        loadCachedSnapshot()
    }

    /// Recompute every target's tolerance from the dose log and refresh the cache. Call after the
    /// dose log changes (and at launch). `now` is injectable for deterministic tests.
    func recompute(from entries: [DoseEntry], now: Date = .now) {
        let weightKg = UserProfileStore.shared.effectiveWeightKg
        let computed = Self.simulate(entries: entries, now: now, weightKg: weightKg) {
            SubstanceStore.shared.pharmacologyParameters(forSubstanceName: $0)
        }
        states = computed
        persist(computed, now: now)
    }

    /// Current availability at a target, or `nil` if untracked (treated as naïve `1` by callers).
    func tolerance(forTarget target: String) -> TargetTolerance? {
        states[target]
    }

    // MARK: - Pure replay (the testable core)

    /// Replay a dose log into per-target tolerance state. Pure aside from the injected `resolve`
    /// closure (production passes `SubstanceStore`), so the gate runs without a container or singleton.
    ///
    /// Each substance contributes a time-resolved occupancy curve at every target it engages
    /// (absolute molar concentration → Hill occupancy, Foundation A); contributions at a *shared*
    /// target combine via ``PDModel/combinedOccupancy(_:)``, and that combined occupancy drives the
    /// per-target availability/acute/load ODEs with the class's ``ReceptorClasses/Parameters``.
    static func simulate(
        entries: [DoseEntry],
        now: Date,
        weightKg: Double,
        timestepMinutes: Double = defaultTimestepMinutes,
        lookbackDays: Double = defaultLookbackDays,
        resolve: (String) -> PharmacologyParameters?,
    ) -> [String: TargetTolerance] {
        let relevant = entries
            .filter { $0.timestamp <= now && $0.timestamp >= now.addingTimeInterval(-lookbackDays * 86_400) }
            .sorted { $0.timestamp < $1.timestamp }
        guard let start = relevant.first?.timestamp, weightKg > 0 else { return [:] }

        var contributorsByTarget: [String: [Contributor]] = [:]
        var classByTarget: [String: ReceptorClasses.ReceptorClass] = [:]

        for entry in relevant {
            guard let p = resolve(entry.substance), p.canComputeOccupancy,
                  let vdPerKg = p.vdLPerKg, let mw = p.molarMassGramsPerMole,
                  let f = p.bioavailabilityFraction, let halfLife = p.halfLifeMinutes,
                  let doseMg = DoseUnit.convert(entry.amount, from: entry.unit, to: "mg")
            else { continue }
            let vd = vdPerKg * weightKg
            guard vd > 0, mw > 0, halfLife > 0 else { continue }
            let ke = PKModel.ke(fromHalfLifeMinutes: halfLife)
            let ka = PKModel.defaultKa(ke: ke)
            // molar = (F·dose/Vd)·shape /1000 /MW ; ×1e9 → nM (fu = 1, Stage 1). One concentration()
            // call per contributor per step then multiplies this prefactor.
            let prefactorNanomolar = (f * doseMg / vd) / 1_000 / mw * 1e9
            let offsetMinutes = entry.timestamp.timeIntervalSince(start) / 60

            for engagement in p.targets {
                contributorsByTarget[engagement.target, default: []].append(
                    Contributor(
                        offsetMinutes: offsetMinutes, ke: ke, ka: ka,
                        prefactorNanomolar: prefactorNanomolar,
                        halfMaxNanomolar: engagement.halfMaxNanomolar,
                        confidence: Swift.min(p.vdConfidence, engagement.confidence),
                    ),
                )
                classByTarget[engagement.target] = ReceptorClasses.classify(
                    target: engagement.target, action: engagement.action,
                )
            }
        }
        guard !contributorsByTarget.isEmpty else { return [:] }

        let totalMinutes = now.timeIntervalSince(start) / 60
        var result: [String: TargetTolerance] = [:]

        for (target, contributors) in contributorsByTarget {
            let receptorClass = classByTarget[target] ?? .unknown
            let params = ReceptorClasses.parameters(for: receptorClass)

            var availability = 1.0
            var acute = 1.0
            var load = 0.0
            var elapsed = 0.0
            while elapsed < totalMinutes {
                let step = Swift.min(timestepMinutes, totalMinutes - elapsed)
                let occ = combinedOccupancy(atMinute: elapsed + step / 2, contributors: contributors)
                availability = PDModel.stepAvailability(
                    availability: availability, occupancy: occ, dtMinutes: step,
                    kappa: params.kappaSlow, tauMinutes: params.tauSlowMinutes,
                )
                if params.hasAcutePool {
                    acute = PDModel.stepAvailability(
                        availability: acute, occupancy: occ, dtMinutes: step,
                        kappa: params.kappaAcute, tauMinutes: params.tauAcuteMinutes,
                    )
                }
                if params.loadGain > 0 {
                    load = PDModel.stepLoad(
                        load: load, occupancy: occ, dtMinutes: step,
                        tauMinutes: params.tauLoadMinutes, gain: params.loadGain,
                    )
                }
                elapsed += step
            }

            let inputConfidence = contributors.map(\.confidence).min() ?? .unverified
            result[target] = TargetTolerance(
                target: target, receptorClass: receptorClass,
                availability: availability, acute: acute, load: load,
                confidence: Swift.min(inputConfidence, params.confidence),
            )
        }
        return result
    }

    // MARK: - Private

    /// One substance-dose's contribution to one target: PK shape + the nM prefactor + that target's
    /// half-saturation constant.
    private struct Contributor {
        let offsetMinutes: Double
        let ke: Double
        let ka: Double
        let prefactorNanomolar: Double
        let halfMaxNanomolar: Double
        let confidence: ConfidenceTier
    }

    /// Combined fractional occupancy at one grid minute from all contributors active by then.
    private static func combinedOccupancy(atMinute minute: Double, contributors: [Contributor]) -> Double {
        var occupancies: [Double] = []
        occupancies.reserveCapacity(contributors.count)
        for c in contributors {
            let dtSinceDose = minute - c.offsetMinutes
            guard dtSinceDose >= 0 else { continue }
            let freeNanomolar = c.prefactorNanomolar * PKModel.concentration(at: dtSinceDose, ke: c.ke, ka: c.ka)
            let o = PKModel.occupancy(concentration: freeNanomolar, halfMax: c.halfMaxNanomolar)
            if o > 0 { occupancies.append(o) }
        }
        return PDModel.combinedOccupancy(occupancies)
    }

    // MARK: - Persistence (cache)

    private func loadCachedSnapshot() {
        guard let context else { return }
        guard let rows = try? context.fetch(FetchDescriptor<ToleranceState>()) else { return }
        var loaded: [String: TargetTolerance] = [:]
        for row in rows {
            loaded[row.target] = TargetTolerance(
                target: row.target,
                receptorClass: ReceptorClasses.classify(target: row.target),
                availability: row.availability, acute: row.acute, load: row.load,
                confidence: ReceptorClasses.parameters(forTarget: row.target).confidence,
            )
        }
        states = loaded
    }

    private func persist(_ computed: [String: TargetTolerance], now: Date) {
        guard let context else { return }
        let existing = (try? context.fetch(FetchDescriptor<ToleranceState>())) ?? []
        var byTarget = Dictionary(existing.map { ($0.target, $0) }, uniquingKeysWith: { a, _ in a })

        for (target, t) in computed {
            if let row = byTarget[target] {
                row.availability = t.availability
                row.acute = t.acute
                row.load = t.load
                row.lastUpdated = now
            } else {
                context.insert(ToleranceState(
                    target: target, availability: t.availability, acute: t.acute,
                    load: t.load, lastUpdated: now,
                ))
            }
            byTarget[target] = nil
        }
        // Targets no longer driven by any in-window dose: reset their cached row to naïve rather than
        // deleting (keeps a stable row set; a target that recovers fully reads as availability 1).
        for (_, stale) in byTarget {
            stale.availability = 1
            stale.acute = 1
            stale.load = 0
            stale.lastUpdated = now
        }

        try? context.save()
    }
}
