import AsyncAlgorithms
import Foundation
import SwiftData

/// A snapshot of tolerance state for one **mechanism class**, derived by replaying the dose log and
/// aggregating every engaged target in that class (DAT+NET → Stimulants, all NMDA sites →
/// Dissociatives, …). The value type the UI reads (Stage 2); the SwiftData ``ToleranceState`` row is
/// its cached persistence. One card per class — the redesign's unit (see
/// `Specs/tolerance-tool-audit-and-redesign.md`).
nonisolated struct ClassTolerance: Hashable, Identifiable {
    let receptorClass: ReceptorClasses.ReceptorClass
    /// Acute ln-shift `sAcute ≥ 0` — within-session tachyphylaxis (the redose loop).
    let sAcute: Double
    /// Adaptive ln-shift `sAdaptive ≥ 0` — the days–weeks baseline shift people mean by "tolerance".
    let sAdaptive: Double
    /// Deep ln-shift `sDeep ≥ 0` — entrenched, months-scale neuroadaptation (gated off for
    /// therapeutic users).
    let sDeep: Double
    /// Synthesis ln-shift `sSynthesis ≥ 0` — the slow serotonin-synthesis pool (τ ≈ weeks) that only
    /// the synthesis-suppressing SERT releasers (MDMA-type entactogens) drive (§3.4). `0` for every
    /// other class and for the cathinone releasers, which spare synthesis and reset on the fast pool.
    let sSynthesis: Double
    /// Representative peak occupancy at the user's usual dose for this class (the median of the
    /// contributors' single-dose peaks) — the gauge's reference point for ``responseFraction``.
    let representativeOccupancy: Double
    /// Weakest-link confidence across the contributing substances' occupancy inputs and the class
    /// kinetics — the house "predicted (model, confidence)" tier.
    let confidence: ConfidenceTier
    /// Canonical sub-targets in this class that some logged dose engaged (for the card's breakdown).
    let subTargets: [String]
    /// Logged substances driving this class (those that passed the mechanism + occupancy gates), for
    /// the card's "driven by" line. Same set the engine integrated, so the chips never disagree with
    /// the number.
    let contributors: [String]
    /// Right-shift `S = exp(sAcuteSafety + sAdaptiveSafety) ≥ 1` of this class's **differential safety
    /// endpoint** (opioid respiratory, stimulant cardiovascular), or `nil` for the classes without one.
    /// It tolerizes on its own kinetics — shallower and faster-recovering for opioid respiratory, and
    /// `1` always for the stimulant cardiovascular pressor (which does not tolerize) — so the gap to
    /// ``shiftFactor`` is the safety story (Stage C). Defaults `nil`: the cache reload carries no
    /// safety state, and it's `nil` for endpoint-less classes.
    let safetyShiftFactor: Double?
    /// Which harm axis ``safetyShiftFactor`` measures, or `nil` when the class has no endpoint.
    let safetyEndpointKind: ReceptorClasses.SafetyEndpoint.Kind?

    var id: ReceptorClasses.ReceptorClass {
        receptorClass
    }

    /// The total dose-response right-shift `S = exp(sAcute + sAdaptive + sDeep + sSynthesis) ≥ 1` —
    /// `1` is naïve, larger means the curve has shifted further right (the same dose does less). The
    /// synthesis layer keeps an MDMA-type entactogen toleranced for weeks after the fast pool relaxes.
    var shiftFactor: Double {
        Foundation.exp(sAcute + sAdaptive + sDeep + sSynthesis)
    }

    /// The gauge: fraction of the naïve effect you'd feel at your usual dose under the current
    /// right-shift (`1` = full, → small as `S` grows). See
    /// ``PDModel/responseFraction(shiftFactor:representativeOccupancy:)``.
    var responseFraction: Double {
        PDModel.responseFraction(shiftFactor: shiftFactor, representativeOccupancy: representativeOccupancy)
    }

    /// One unified "how affected" axis ∈ [0, 1] for ranking and the state word — `1 − responseFraction`,
    /// so a bigger right-shift (less response at the usual dose) ranks higher.
    var severity: Double {
        1 - responseFraction
    }

    /// The **danger ratio** between the desired effect and the safety endpoint, or `nil` for a class
    /// without one. `> 1` means the desired effect is more toleranced than the safety endpoint — the
    /// gap that makes a reset dose dangerous (opioid analgesia outruns respiratory protection) or a
    /// redose toxic (the stimulant high outruns the un-toleranced pressor, where `safetyShiftFactor ≈ 1`
    /// so this collapses to ``shiftFactor`` — how far the high has pulled ahead).
    var safetyGap: Double? {
        guard let safetyShiftFactor else { return nil }
        return shiftFactor / max(1, safetyShiftFactor)
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

    /// Default integration timestep (minutes). The closed-form ``PDModel/stepShift`` is exact for
    /// piecewise-constant occupancy, so a coarse grid stays accurate; 30 min balances fidelity against
    /// the cost of replaying a long history.
    nonisolated static let defaultTimestepMinutes = 30.0

    /// How far back the replay reaches. 90 days (3 months) fully captures the acute + adaptive layers;
    /// a dose from long ago is irrelevant to current sensitivity, and the months-scale deep layer is
    /// carried forward by the persisted checkpoint (a later stage), so the short window doesn't lose
    /// long-run deep state on incremental updates.
    nonisolated static let defaultLookbackDays = 90.0

    /// The canonical PK-complete **class representative** for each class whose PK-less members should
    /// still build tolerance: a substance with no full pharmacokinetics is modeled *as* this stand-in
    /// at an equivalent dose (Stage D missing-PK fallback, `Specs/tolerance-faithful-model.md` §4), so
    /// an RC benzo with only a dose ladder still accrues GABA tolerance. Classes absent here have no
    /// fallback — their PK-less members stay listed as "can't predict yet".
    nonisolated static let classRepresentative: [ReceptorClasses.ReceptorClass: String] = [
        .gaba: "Diazepam",
        .muOpioid: "Morphine",
        .catecholamineStimulant: "Amphetamine",
        .serotonergicReleaser: "MDMA",
        // 4-AcO-DMT, 2C-E, 4-HO-MET and most research psychedelics/dissociatives ship a dose ladder
        // but no full PK, so they need a stand-in too. Psilocin (oral F/Vd/t½ all known) is the
        // 5-HT2A psychedelic representative; Ketamine the NMDA dissociative one.
        .psychedelic5HT2A: "Psilocin",
        .nmdaAntagonist: "Ketamine",
    ]

    /// Oral **morphine-milligram-equivalent** factors (CDC 2022, §3.1) — morphine-mg per 1 mg of the
    /// named opioid. The principled equivalent dose when a PK-less opioid is one of these named drugs
    /// (the fallback then models it as Morphine at `dose × factor` mg); a novel/unlisted opioid falls
    /// back to the generic dose-fraction proxy instead. Fentanyl (mcg) and methadone's tiered
    /// nonlinearity are intentionally omitted from this simple linear table.
    nonisolated static let opioidMMEPerMg: [String: Double] = [
        "morphine": 1, "codeine": 0.15, "hydrocodone": 1, "oxycodone": 1.5,
        "oxymorphone": 3, "hydromorphone": 4, "tramadol": 0.2,
    ]

    /// Entactogens whose metabolites suppress serotonin synthesis (TPH) → weeks-scale recovery, unlike
    /// the cathinone releasers (mephedrone etc.) which spare synthesis and reset in days (§3.4). Keyed
    /// by canonical name, lowercased. Methylenedioxy entactogens only — **not** cathinones: membership
    /// resolves ``PharmacologyParameters/suppressesSerotoninSynthesis``, which gates the SERT class's
    /// slow synthesis pool so the two recover on different clocks within the same mechanism class.
    nonisolated static let serotoninSynthesisSuppressors: Set<String> = [
        "mdma", "mda", "mdea", "mbdb", "mdoh",
    ]

    /// Current per-class tolerance snapshot, keyed by mechanism class. Observation-tracked; views read
    /// this. One entry per engaged class (aggregating all of that class's targets).
    private(set) var states: [ReceptorClasses.ReceptorClass: ClassTolerance] = [:]

    /// Logged substances inside the window that engaged a tolerance-bearing mechanism but could not be
    /// modeled (missing PK / Kᵢ — ``PharmacologyParameters/canComputeOccupancy`` false). Surfaced by the
    /// UI as an honest "can't predict yet" state so a class never silently reads as rested (the
    /// heavy-kratom → "Opioids: nearly recovered" safety trap). Observation-tracked.
    private(set) var incompleteDataSubstances: [String] = []

    /// Signature of the inputs behind the current ``states`` (dose-log content + body weight + an hourly
    /// time bucket). A repeat ``recompute(from:now:)`` with the same signature is a no-op, so re-opening
    /// the tool or returning to it serves the warm snapshot instead of replaying the whole log again.
    @ObservationIgnored private var lastSignature: String?

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var context: ModelContext?

    /// Long-lived task that keeps ``states`` warm in the background: debounced recomputes driven by
    /// ``DoseLogService`` change ticks. App-lifetime; cancelled only if ``configure(container:)`` re-runs.
    @ObservationIgnored private var backgroundRefreshTask: Task<Void, Never>?

    /// Lookback for the background-warmed snapshot fetch — the full tolerance window.
    @ObservationIgnored static let warmFetchLookbackDays = defaultLookbackDays

    /// Public for the test seam; production uses ``shared``.
    init() {}

    // MARK: - Lifecycle

    /// Bind to the app's shared container, load the last cached snapshot, and start keeping the snapshot
    /// warm in the background. Call once at launch.
    func configure(container: ModelContainer) {
        self.container = container
        context = ModelContext(container)
        loadCachedSnapshot()
        // Only the production singleton runs the background loop: `DoseLogService.changes` is a
        // single-consumer `AsyncStream`, so a test-seam instance must not also subscribe and compete.
        if self === Self.shared { startBackgroundRefresh() }
    }

    /// Subscribe to ``DoseLogService`` change ticks, debounce them (coalescing import bursts and rapid
    /// edits), and recompute off-main so the warm snapshot — read by the tool *and* the dose-entry
    /// cross-tolerance readout — is always fresh without any interactive path triggering a replay. An
    /// initial tick warms the cache at launch. The signature gate makes non-dose saves cheap no-ops.
    private func startBackgroundRefresh() {
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = Task { [weak self] in
            // Let the first paint settle before the initial replay: it resolves
            // pharmacology (pk + bindings) per dosed substance on the main actor,
            // which competed with launch rendering. The warm snapshot is only
            // read by the tool and the dose-entry readout, so a short delay is
            // invisible.
            try? await Task.sleep(for: .seconds(1.5))
            if Task.isCancelled { return }
            await self?.recomputeFromStore()
            let ticks = DoseLogService.shared.changes.debounce(for: .seconds(2))
            for await _ in ticks {
                if Task.isCancelled { return }
                await self?.recomputeFromStore()
            }
        }
    }

    /// Fetch the dose log from the store's own context (lean — only the fields ``SimDose`` reads) and
    /// recompute. The signature gate inside ``recompute(from:now:)`` skips redundant work.
    private func recomputeFromStore(now: Date = .now) async {
        guard let context else { return }
        // Cutoff computed outside the predicate — `#Predicate` can't call `addingTimeInterval`.
        let cutoff = now.addingTimeInterval(-Self.warmFetchLookbackDays * 86_400)
        var descriptor = FetchDescriptor<DoseEntry>(predicate: #Predicate { $0.timestamp >= cutoff })
        descriptor.propertiesToFetch = [\.substance, \.amount, \.unit, \.timestamp]
        guard let entries = try? context.fetch(descriptor) else { return }
        await recompute(from: entries, now: now)
    }

    /// Recompute every target's tolerance from the dose log and refresh the cache. Call after the dose
    /// log changes (and at launch). `now` is injectable for deterministic tests.
    ///
    /// The dose snapshot and per-substance pharmacology resolution happen on the main actor (the
    /// `@Model` entries and `SubstanceStore` are main-actor bound), then the heavy replay runs **off**
    /// the cooperative pool so the UI never stalls. A signature gate skips the work entirely when the
    /// inputs are unchanged, so navigating back into the tool is free.
    func recompute(from entries: [DoseEntry], now: Date = .now) async {
        let weightKg = UserProfileStore.shared.effectiveWeightKg
        let signature = Self.signature(entries: entries, weightKg: weightKg, now: now)
        if signature == lastSignature { return }

        // Snapshot to Sendable values + resolve each unique substance once (kills the per-dose N+1).
        let doses = entries.map {
            SimDose(substance: $0.substance, amountMg: DoseUnit.convert($0.amount, from: $0.unit, to: "mg"), timestamp: $0.timestamp)
        }
        // Resolve pharmacology off the main actor: the per-substance Kᵢ/PK/molar-mass reads run on
        // SubstanceStore's batch connection, not in a tight loop on main (the post-commit hang the
        // 1.5 s launch delay only masked). The class representatives are resolved alongside the logged
        // substances so the PK-less fallback (Stage D) has their PK template in `params`.
        let uniqueNames = Array(Set(doses.map(\.substance) + Self.classRepresentative.values))
        let params = await SubstanceStore.shared.pharmacologyParametersBatchOffMain(forNames: uniqueNames)

        let computed = await Self.computeOffMain(doses: doses, params: params, now: now, weightKg: weightKg)
        states = computed
        incompleteDataSubstances = Self.incompleteData(doses: doses, params: params, now: now)
        lastSignature = signature
        persist(computed, now: now)
    }

    /// Logged substances inside the window that *would* drive a tolerance class but can't be modeled
    /// because their occupancy inputs are incomplete (no Vd / F / half-life / molar mass / graded
    /// target). These are surfaced as "can't predict yet" rather than silently contributing nothing —
    /// the heavy-kratom safety case. A substance with no tolerance-bearing target at all (action /
    /// mechanism mismatch only) is *not* incomplete data, just out of scope, so it isn't listed.
    ///
    /// Stage D: a PK-less substance that a **class representative** *can* model (the missing-PK
    /// fallback below builds surrogate contributors for at least one of its classes) is no longer
    /// incomplete — it's predicted, just at a degraded confidence. Only a substance with no
    /// representative-backed fallback for any of its classes stays listed here. The eligibility test
    /// mirrors ``fallbackClasses(for:params:)`` so the two never disagree.
    nonisolated static func incompleteData(
        doses: [SimDose], params: [String: PharmacologyParameters], now: Date,
    ) -> [String] {
        let cutoff = now.addingTimeInterval(-defaultLookbackDays * 86_400)
        var seen = Set<String>()
        var result: [String] = []
        for dose in doses.sorted(by: { $0.timestamp > $1.timestamp })
            where dose.timestamp <= now && dose.timestamp >= cutoff {
            guard !seen.contains(dose.substance) else { continue }
            guard let p = params[dose.substance], !p.canComputeOccupancy else { continue }
            // Only flag substances whose *named* targets include a recognised tolerance mechanism
            // (so a vitamin with a stray binding row doesn't show up as "incomplete tolerance data").
            // The rebound-hosting adrenergic classes (§3.5) are excluded: they barely tolerize and have
            // no PK-less representative by design, so a PK-less clonidine/propranolol is not "missing a
            // prediction" — there is no tolerance curve to predict. (It just produces no card.)
            guard p.targets.contains(where: {
                let cls = ReceptorClasses.classify(target: $0.target, action: $0.action)
                return cls != .unknown && !cls.hostsReboundWarningOnly
            }) else { continue }
            // A representative-backed fallback can still model it ⇒ not incomplete.
            guard fallbackClasses(for: p, params: params).isEmpty else { continue }
            seen.insert(dose.substance)
            result.append(dose.substance)
        }
        return result
    }

    /// The tolerance classes a **PK-less** substance can still be modeled in via a class representative
    /// (Stage D missing-PK fallback): each class whose named, mechanism-gated targets it engages and
    /// for which a PK-complete ``classRepresentative`` plus both reference doses (the substance's own
    /// and the representative's) exist. Empty ⇒ genuinely unmodelable (stays "can't predict yet").
    /// Shared by ``buildClassWork`` (which builds the surrogate contributors) and ``incompleteData``.
    private nonisolated static func fallbackClasses(
        for substanceParams: PharmacologyParameters, params: [String: PharmacologyParameters],
    ) -> Set<ReceptorClasses.ReceptorClass> {
        guard substanceParams.referenceDoseMg != nil else { return [] }
        var classes: Set<ReceptorClasses.ReceptorClass> = []
        for engagement in substanceParams.targets {
            let cls = ReceptorClasses.classify(target: engagement.target, action: engagement.action)
            guard cls != .unknown,
                  let repName = classRepresentative[cls],
                  let rep = params[repName], rep.canComputeOccupancy, rep.referenceDoseMg != nil
            else { continue }
            classes.insert(cls)
        }
        return classes
    }

    /// Run the parallel replay off the main actor and off the shared cooperative pool by pinning it to
    /// ``replayExecutor``. `withTaskExecutorPreference` makes that pin apply to the whole operation *and*
    /// the `TaskGroup` children spawned inside ``simulateConcurrently(doses:params:now:weightKg:...)`` —
    /// and, because the preference is explicit, it also overrides `NonisolatedNonsendingByDefault`
    /// (SE-0461), which would otherwise run this nonisolated async work back on the caller's (main) actor.
    /// Structured (cancellation propagates) — no manual continuation, no `concurrentPerform`.
    private nonisolated static func computeOffMain(
        doses: [SimDose], params: [String: PharmacologyParameters], now: Date, weightKg: Double,
    ) async -> [ReceptorClasses.ReceptorClass: ClassTolerance] {
        await withTaskExecutorPreference(replayExecutor) {
            await simulateConcurrently(doses: doses, params: params, now: now, weightKg: weightKg)
        }
    }

    /// A cheap fingerprint of everything the replay depends on: the in-window dose-log content, the body
    /// weight, and an hourly bucket of `now` (so time-decay is refreshed at most ~hourly, never on mere
    /// navigation). Stable within a process run, which is all the gate needs.
    ///
    /// Only doses **inside the lookback window** are hashed — exactly the set ``simulate`` integrates —
    /// so the tool (which passes the whole `@Query`) and the background refresh (which fetches a
    /// lookback-filtered set) produce the *same* signature and dedupe against each other's work.
    private static func signature(entries: [DoseEntry], weightKg: Double, now: Date) -> String {
        let cutoff = now.addingTimeInterval(-defaultLookbackDays * 86_400)
        // Order-independent: the tool passes a reverse-chron `@Query` while the background path fetches in
        // store order, so combine per-entry hashes with XOR (commutative) rather than a sequential
        // `Hasher`, which would differ by iteration order. `count` guards adds/removes.
        var combined: UInt64 = 0
        var count = 0
        for entry in entries where entry.timestamp <= now && entry.timestamp >= cutoff {
            count += 1
            var hasher = Hasher()
            hasher.combine(entry.substance)
            hasher.combine(entry.amount)
            hasher.combine(entry.unit)
            hasher.combine(entry.timestamp)
            combined ^= UInt64(bitPattern: Int64(hasher.finalize()))
        }
        return "\(count)|\(combined)|\(Int(now.timeIntervalSince1970 / 3_600))|\(weightKg)"
    }

    /// Current tolerance at a mechanism class, or `nil` if untracked (treated as naïve by callers).
    func tolerance(for receptorClass: ReceptorClasses.ReceptorClass) -> ClassTolerance? {
        states[receptorClass]
    }

    // MARK: - Pure replay (the testable core)

    /// Replay a dose log into per-target tolerance state. Pure aside from the injected `resolve`
    /// closure (production passes `SubstanceStore`), so the gate runs without a container or singleton.
    ///
    /// Each substance contributes a time-resolved occupancy curve at every target it engages
    /// (absolute molar concentration → Hill occupancy, Foundation A); contributions at a *shared*
    /// target combine via ``PDModel/combinedOccupancy(_:)``, and that combined occupancy drives the
    /// per-class three-layer right-shift `S(t)` with the class's ``ReceptorClasses/Parameters``.
    /// A `Sendable` snapshot of one logged dose, so the heavy replay can run **off the main actor**
    /// (a SwiftData `DoseEntry` is a non-`Sendable` `@Model` and can't cross an isolation boundary).
    /// The unit→mg conversion is done while building the snapshot (on the actor that owns the entry).
    struct SimDose {
        let substance: String
        let amountMg: Double?
        let timestamp: Date
    }

    /// Replay a SwiftData dose log into per-target tolerance state. Thin `@MainActor` adapter over the
    /// pure ``simulate(doses:params:now:weightKg:timestepMinutes:lookbackDays:)`` core: it snapshots the
    /// `@Model` entries into `Sendable` ``SimDose`` and resolves each **unique** substance's pharmacology
    /// exactly once (the closure production passes is `SubstanceStore`, three GRDB reads per call — so
    /// memoizing per unique name, not per entry, is what removes the N+1 over a multi-thousand-dose log).
    static func simulate(
        entries: [DoseEntry],
        now: Date,
        weightKg: Double,
        timestepMinutes: Double = defaultTimestepMinutes,
        lookbackDays: Double = defaultLookbackDays,
        resolve: (String) -> PharmacologyParameters?,
    ) -> [ReceptorClasses.ReceptorClass: ClassTolerance] {
        let doses = entries.map {
            SimDose(substance: $0.substance, amountMg: DoseUnit.convert($0.amount, from: $0.unit, to: "mg"), timestamp: $0.timestamp)
        }
        var params: [String: PharmacologyParameters] = [:]
        var resolved = Set<String>()
        for dose in doses where resolved.insert(dose.substance).inserted {
            if let p = resolve(dose.substance) { params[dose.substance] = p }
        }
        // Resolve the class representatives too, so the PK-less fallback (Stage D) can model a logged
        // substance as its representative at an equivalent dose.
        for repName in Self.classRepresentative.values where resolved.insert(repName).inserted {
            if let p = resolve(repName) { params[repName] = p }
        }
        return simulate(
            doses: doses, params: params, now: now, weightKg: weightKg,
            timestepMinutes: timestepMinutes, lookbackDays: lookbackDays,
        )
    }

    /// The pure, `nonisolated` replay core — runs off the main actor over `Sendable` inputs.
    ///
    /// Each substance-dose contributes a time-resolved occupancy curve at every target it engages
    /// (absolute molar concentration → Hill occupancy, Foundation A); contributions at a *shared* target
    /// combine via ``PDModel/combinedOccupancy(_:)``, and that combined occupancy drives the per-target
    /// three-layer right-shift `S(t)` with the class's ``ReceptorClasses/Parameters``.
    ///
    /// ## Why it is near-linear (not O(history × doses))
    /// A dose's occupancy decays to nothing within a handful of half-lives, so it is wasteful to
    /// re-evaluate every dose at every 30-min step across an 18-month window. Each contributor instead
    /// carries an **active window** `[onset, expiry]` (``decayWindowMinutes`` — where its occupancy
    /// crosses ``occupancyPruneEpsilon``), and per target the integrator (1) fine-steps the 30-min grid
    /// **only inside the union of active windows**, evaluating just the *currently* active contributors,
    /// and (2) crosses idle gaps with the ODE's **exact closed-form recovery** (occupancy ≡ 0 there, so a
    /// single exponential is identical to stepping). The result matches the dense replay to within the
    /// sub-ε prune; the cost drops from ~`span/step × Σdoses` to ~`Σ(window/step)`.
    nonisolated static func simulate(
        doses: [SimDose],
        params: [String: PharmacologyParameters],
        now: Date,
        weightKg: Double,
        timestepMinutes: Double = defaultTimestepMinutes,
        lookbackDays: Double = defaultLookbackDays,
    ) -> [ReceptorClasses.ReceptorClass: ClassTolerance] {
        guard let prepared = buildClassWork(
            doses: doses, params: params, now: now, weightKg: weightKg, lookbackDays: lookbackDays,
        ) else { return [:] }

        var result = [ReceptorClasses.ReceptorClass: ClassTolerance](minimumCapacity: prepared.work.count)
        for work in prepared.work {
            result[work.receptorClass] = tolerance(for: work, totalMinutes: prepared.totalMinutes, step: timestepMinutes)
        }
        return result
    }

    /// Concurrent sibling of ``simulate(doses:params:now:weightKg:timestepMinutes:lookbackDays:)`` —
    /// identical inputs and output, but the independent per-target replays are fanned out across a
    /// `TaskGroup`. This is the path the background ``recompute(from:now:)`` takes (via ``computeOffMain``,
    /// which pins it to ``replayExecutor``); the synchronous `simulate` above is kept for the small
    /// main-actor callers (cross-tolerance / opioid-reset readouts, tests) that replay narrow windows and
    /// don't benefit from fan-out.
    ///
    /// `TaskGroup` rather than `DispatchQueue.concurrentPerform`: parallelism is bounded by the executor's
    /// width (no GCD thread-explosion), and it is structured + cancellable. Group children inherit the
    /// caller's task-executor preference, so when this runs under `withTaskExecutorPreference(replayExecutor)`
    /// each per-target integration executes on that dedicated queue — off the main actor and off the shared
    /// cooperative pool. Per-target granularity (~33 children) keeps task-creation overhead negligible
    /// against the integration cost.
    nonisolated static func simulateConcurrently(
        doses: [SimDose],
        params: [String: PharmacologyParameters],
        now: Date,
        weightKg: Double,
        timestepMinutes: Double = defaultTimestepMinutes,
        lookbackDays: Double = defaultLookbackDays,
    ) async -> [ReceptorClasses.ReceptorClass: ClassTolerance] {
        guard let prepared = buildClassWork(
            doses: doses, params: params, now: now, weightKg: weightKg, lookbackDays: lookbackDays,
        ) else { return [:] }
        let totalMinutes = prepared.totalMinutes
        let step = timestepMinutes

        return await withTaskGroup(of: ClassTolerance.self) { group in
            for work in prepared.work {
                group.addTask { tolerance(for: work, totalMinutes: totalMinutes, step: step) }
            }
            var result = [ReceptorClasses.ReceptorClass: ClassTolerance](minimumCapacity: prepared.work.count)
            for await state in group {
                result[state.receptorClass] = state
            }
            return result
        }
    }

    /// One mechanism class's full replay input: the contributors aggregated across *all* its engaged
    /// targets, the canonical sub-targets (for the card breakdown), and the modulators acting on the
    /// class. `Sendable` so it can be handed to a `TaskGroup` child for off-actor integration.
    private struct ClassWork {
        let receptorClass: ReceptorClasses.ReceptorClass
        let subTargets: [String]
        let contributorSubstances: [String]
        let contributors: [Contributor]
        let modulators: [ModulatorContributor]
        /// Median single-dose peak occupancy across this class's contributors — the gauge's
        /// representative occupancy at the usual dose.
        let representativeOccupancy: Double
    }

    /// Shared, cheap (serial) preparation for both `simulate` variants: filter the log to the lookback
    /// window, turn each dose into per-target ``Contributor``s, and **group them by mechanism class**
    /// (action-aware, so a 5-HT2A antagonist isn't a psychedelic), so DAT+NET → one Stimulants unit and
    /// every NMDA site → one Dissociatives unit. Weak off-target engagements (peak occupancy below
    /// ``minMeaningfulOccupancy``) are dropped so they neither spawn a class nor pollute a contributor
    /// list. Returns `nil` when there is nothing to replay.
    private nonisolated static func buildClassWork(
        doses: [SimDose],
        params: [String: PharmacologyParameters],
        now: Date,
        weightKg: Double,
        lookbackDays: Double,
    ) -> (work: [ClassWork], totalMinutes: Double)? {
        let cutoff = now.addingTimeInterval(-lookbackDays * 86_400)
        let relevant = doses
            .filter { $0.timestamp <= now && $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }
        guard let start = relevant.first?.timestamp, weightKg > 0 else { return nil }

        var contributorsByClass: [ReceptorClasses.ReceptorClass: [Contributor]] = [:]
        var subTargetsByClass: [ReceptorClasses.ReceptorClass: [String]] = [:]
        // Single-dose peak occupancies per class — the gauge's representative-occupancy input (median).
        var peaksByClass: [ReceptorClasses.ReceptorClass: [Double]] = [:]
        var seenSubTarget: [ReceptorClasses.ReceptorClass: Set<String>] = [:]
        // Substance names driving each class, in most-recent-first order (the "driven by" chips). The
        // log is walked oldest→newest, so the most recent dose of a substance wins its position.
        var substanceRecency: [ReceptorClasses.ReceptorClass: [String: Double]] = [:]
        // Tolerance-modulation contributors keyed by the *affected* class (Stage 4b): an NMDA
        // antagonist onboard lowers μ-opioid tolerance development, etc.
        var modulatorsByClass: [ReceptorClasses.ReceptorClass: [ModulatorContributor]] = [:]

        // The PK + occupancy prefactor a substance's pharmacology resolves to for one dose, plus the
        // most-potent surviving engagement per class — the modulator-presence driver the direct path
        // reuses. `nil` when the source can't compute occupancy.
        struct DoseExposure {
            let ke: Double
            let ka: Double
            let prefactorNanomolar: Double
            let bestTargetByClass: [ReceptorClasses.ReceptorClass: PharmacologyParameters.TargetEngagement]
        }

        /// Build per-target ``Contributor``s for one dose from `sourceParams`' PK + targets, grouping
        /// them into the shared by-class accumulators. The reusable inner block both paths run:
        /// - **Direct** — `sourceParams` is the substance's own pharmacology, `restrictToClass` nil,
        ///   `confidenceFloor` `.high` (a no-op `min`) ⇒ unchanged behaviour.
        /// - **Fallback (Stage D)** — `sourceParams` is a class representative's, `restrictToClass`
        ///   pins it to the one class being surrogate-modeled (so Morphine→MOR only, not its
        ///   off-targets), and `confidenceFloor` (`.low` MME / `.unverified` dose-fraction) is
        ///   `min`-combined into every contributor so the class badges as predicted-not-measured.
        ///
        /// `doseMg` is the *effective* dose to expose at (the logged mg directly, or the
        /// representative-equivalent mg); `loggedName` is always the user's logged substance so the
        /// "driven by" chips keep their name. Returns the dose's ``DoseExposure`` (for the direct
        /// path's modulators), or `nil` when the source PK is insufficient.
        func appendContributors(
            sourceParams: PharmacologyParameters, doseMg: Double, escalation: Double, onset: Double,
            loggedName: String, restrictToClass: ReceptorClasses.ReceptorClass?,
            confidenceFloor: ConfidenceTier,
        ) -> DoseExposure? {
            guard sourceParams.canComputeOccupancy,
                  let vdPerKg = sourceParams.vdLPerKg, let mw = sourceParams.molarMassGramsPerMole,
                  let f = sourceParams.bioavailabilityFraction, let halfLife = sourceParams.halfLifeMinutes
            else { return nil }
            let vd = vdPerKg * weightKg
            guard vd > 0, mw > 0, halfLife > 0 else { return nil }
            let ke = PKModel.ke(fromHalfLifeMinutes: halfLife)
            let ka = PKModel.defaultKa(ke: ke)
            // molar = (F·dose·scale/Vd)·shape /1000 /MW ; ×1e9 → nM (fu = 1, Stage 1). One
            // concentration() call per contributor per step then multiplies this prefactor. `doseScale`
            // converts a logged *preparation* mass to active-compound mass (Kratom→mitragynine etc.); 1
            // for pure compounds.
            let prefactorNanomolar = (f * doseMg * sourceParams.doseScale / vd) / 1_000 / mw * 1e9

            // Most-potent *surviving* target per class (targets are tightest-first, so the first per
            // class wins) — drives any modulation edge's presence curve.
            var bestTargetByClass: [ReceptorClasses.ReceptorClass: PharmacologyParameters.TargetEngagement] = [:]
            for engagement in sourceParams.targets {
                // Mechanism-direction gate: off-mechanism engagements (a 5-HT2A antagonist, an α7
                // antagonist) classify to `.unknown` and are skipped — no card.
                let cls = ReceptorClasses.classify(target: engagement.target, action: engagement.action)
                guard cls != .unknown else { continue }
                // Fallback path: only build the representative's targets that fall in the one class
                // being surrogate-modeled.
                if let restrictToClass, cls != restrictToClass { continue }
                // Meaningfulness gate: skip engagements barely occupied at this dose (weak off-targets).
                let peak = peakOccupancy(
                    prefactorNanomolar: prefactorNanomolar, ke: ke, ka: ka,
                    halfMaxNanomolar: engagement.halfMaxNanomolar,
                )
                guard peak >= minMeaningfulOccupancy else { continue }
                peaksByClass[cls, default: []].append(peak)

                if bestTargetByClass[cls] == nil { bestTargetByClass[cls] = engagement }
                let expiry = onset + decayWindowMinutes(
                    ke: ke, ka: ka, prefactorNanomolar: prefactorNanomolar,
                    halfMaxNanomolar: engagement.halfMaxNanomolar,
                )
                contributorsByClass[cls, default: []].append(
                    Contributor(
                        onset: onset, expiry: expiry, ke: ke, ka: ka,
                        prefactorNanomolar: prefactorNanomolar,
                        halfMaxNanomolar: engagement.halfMaxNanomolar,
                        confidence: Swift.min(sourceParams.vdConfidence, sourceParams.bioavailabilityConfidence, sourceParams.doseScaleConfidence, engagement.confidence, confidenceFloor),
                        escalation: escalation,
                        suppressesSynthesis: sourceParams.suppressesSerotoninSynthesis,
                    ),
                )
                let canonical = ReceptorClasses.canonicalTarget(engagement.target)
                if seenSubTarget[cls, default: []].insert(canonical).inserted {
                    subTargetsByClass[cls, default: []].append(canonical)
                }
                substanceRecency[cls, default: [:]][loggedName] = onset
            }
            return DoseExposure(ke: ke, ka: ka, prefactorNanomolar: prefactorNanomolar, bestTargetByClass: bestTargetByClass)
        }

        for dose in relevant {
            guard let p = params[dose.substance], let doseMg = dose.amountMg else { continue }
            let onset = dose.timestamp.timeIntervalSince(start) / 60

            if p.canComputeOccupancy {
                // Direct path — model the substance on its own pharmacology (unchanged behaviour).
                // Dose-relative escalation = logged mg ÷ the substance's heavy ceiling (both in
                // preparation mg, so no doseScale). 0 when no reference dose ⇒ the deep gate stays closed.
                let escalation = (p.referenceDoseMg ?? 0) > 0 ? doseMg / p.referenceDoseMg! : 0
                guard let exposure = appendContributors(
                    sourceParams: p, doseMg: doseMg, escalation: escalation, onset: onset,
                    loggedName: dose.substance, restrictToClass: nil, confidenceFloor: .high,
                ) else { continue }

                // Register this dose as a tolerance modulator for any class it modulates. Presence is
                // the occupancy of its most-potent target *of the modulating class*, so the edge fires
                // only while the modulator is actually onboard (concentration/overlap-gated). Direct
                // path only — a PK-less modulator can't be time-resolved (Stage D).
                for (modClass, best) in exposure.bestTargetByClass {
                    for edge in ToleranceModulation.edges(forModulatorClass: modClass) {
                        let expiry = onset + decayWindowMinutes(
                            ke: exposure.ke, ka: exposure.ka, prefactorNanomolar: exposure.prefactorNanomolar,
                            halfMaxNanomolar: best.halfMaxNanomolar,
                        )
                        modulatorsByClass[edge.affectedClass, default: []].append(
                            ModulatorContributor(
                                onset: onset, expiry: expiry, ke: exposure.ke, ka: exposure.ka,
                                prefactorNanomolar: exposure.prefactorNanomolar,
                                halfMaxNanomolar: best.halfMaxNanomolar,
                                muFactor: edge.muFactor,
                            ),
                        )
                    }
                }
            } else if let refSub = p.referenceDoseMg, refSub > 0 {
                // Stage D missing-PK fallback — model the substance AS its class representative at an
                // equivalent dose, so an RC benzo with only a dose ladder still accrues GABA tolerance.
                // The deep gate still uses the *substance's own* escalation (dose ÷ its heavy ceiling).
                let escalation = doseMg / refSub
                for cls in fallbackClasses(for: p, params: params) {
                    guard let repName = Self.classRepresentative[cls], let rep = params[repName],
                          let refRep = rep.referenceDoseMg, refRep > 0 else { continue }
                    let equivalentDoseMg: Double
                    let confidenceFloor: ConfidenceTier
                    if cls == .muOpioid, let mme = Self.opioidMMEPerMg[dose.substance.lowercased()] {
                        // Named opioid → CDC morphine-mg-equivalent, modeled as Morphine at that dose.
                        equivalentDoseMg = doseMg * mme
                        confidenceFloor = .low
                    } else {
                        // Generic dose-fraction proxy: the same fraction of the heavy ceiling, expressed
                        // in the representative's mg.
                        equivalentDoseMg = (doseMg / refSub) * refRep
                        confidenceFloor = .unverified
                    }
                    _ = appendContributors(
                        sourceParams: rep, doseMg: equivalentDoseMg, escalation: escalation, onset: onset,
                        loggedName: dose.substance, restrictToClass: cls, confidenceFloor: confidenceFloor,
                    )
                }
            }
        }
        guard !contributorsByClass.isEmpty else { return nil }

        let work = contributorsByClass.map { receptorClass, contributors -> ClassWork in
            let recency = substanceRecency[receptorClass] ?? [:]
            let names = recency.sorted { $0.value > $1.value }.map(\.key)
            return ClassWork(
                receptorClass: receptorClass,
                subTargets: subTargetsByClass[receptorClass] ?? [],
                contributorSubstances: names,
                contributors: contributors, modulators: modulatorsByClass[receptorClass] ?? [],
                representativeOccupancy: median(peaksByClass[receptorClass] ?? []),
            )
        }
        return (work, now.timeIntervalSince(start) / 60)
    }

    /// Integrate one prepared ``ClassWork`` into its tolerance snapshot — the unit of work both `simulate`
    /// drivers run (serially or as a `TaskGroup` child).
    private nonisolated static func tolerance(
        for work: ClassWork, totalMinutes: Double, step: Double,
    ) -> ClassTolerance {
        let params = ReceptorClasses.parameters(for: work.receptorClass)
        let state = integrateTarget(
            contributors: work.contributors, modulators: work.modulators,
            params: params, totalMinutes: totalMinutes, step: step,
        )
        let inputConfidence = work.contributors.map(\.confidence).min() ?? .unverified
        // The differential safety endpoint's right-shift (Stage C) — `exp` of its two parallel ln-shift
        // layers, or `nil` when the class has no endpoint. Same occupancy, its own kinetics.
        let safetyShiftFactor: Double? = params.safetyEndpoint == nil
            ? nil
            : Foundation.exp(state.sAcuteSafety + state.sAdaptiveSafety)
        return ClassTolerance(
            receptorClass: work.receptorClass,
            sAcute: state.sAcute, sAdaptive: state.sAdaptive, sDeep: state.sDeep,
            sSynthesis: state.sSynthesis,
            representativeOccupancy: work.representativeOccupancy,
            confidence: Swift.min(inputConfidence, params.confidence),
            subTargets: work.subTargets, contributors: work.contributorSubstances,
            safetyShiftFactor: safetyShiftFactor,
            safetyEndpointKind: params.safetyEndpoint?.kind,
        )
    }

    /// Median of a peak-occupancy list (sorted middle element), `0` when empty — the gauge's
    /// representative occupancy at the usual dose.
    private nonisolated static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// Single-dose **peak** fractional occupancy of one engagement, evaluated at the modeled Tmax — the
    /// meaningfulness gate in ``buildClassWork``. A receptor barely touched at a typical dose shouldn't
    /// spawn a tolerance card or appear as a contributor.
    private nonisolated static func peakOccupancy(
        prefactorNanomolar: Double, ke: Double, ka: Double, halfMaxNanomolar: Double,
    ) -> Double {
        guard ke > 0, ka > 0, halfMaxNanomolar > 0, prefactorNanomolar > 0 else { return 0 }
        let tmax = PKModel.tmax(ke: ke, ka: ka)
        let peakConc = prefactorNanomolar * PKModel.concentration(at: tmax, ke: ke, ka: ka)
        return peakConc / (peakConc + halfMaxNanomolar)
    }

    // MARK: - Private

    /// Dedicated executor for the heavy off-main replay: a concurrent, utility-QoS dispatch queue used
    /// directly as a `TaskExecutor` (`DispatchQueue: TaskExecutor`, iOS 18.4+). Pinning the replay here
    /// keeps the ~second-long CPU burst off **both** the main actor and Swift's *shared* cooperative
    /// pool, so it can't stall the UI or starve unrelated structured concurrency — and, unlike a plain
    /// `Task.detached`, it isn't pulled back onto the caller's executor by `NonisolatedNonsendingByDefault`
    /// (SE-0461, enabled project-wide). Concurrent attribute so the `TaskGroup` fan-out actually parallelizes.
    private nonisolated static let replayExecutor = DispatchQueue(
        label: "dev.yumeji.piru.tolerance-replay", qos: .utility, attributes: .concurrent,
    )

    /// Occupancy below which a contributor is treated as fully decayed and dropped from the integration.
    /// At 1e-9 the discarded tail's effect on the ln-shift layers is ≪ 1e-6 (far below the integer-percent
    /// the UI shows); the golden test (`ToleranceGoldenTests`) pins the resulting numbers to the dense
    /// replay within 1e-6 to keep this honest.
    nonisolated static let occupancyPruneEpsilon = 1e-9

    /// Minimum single-dose **peak occupancy** for an engagement to count toward its class (the
    /// meaningfulness gate in ``buildClassWork``). Below ~5% the receptor is barely engaged at a
    /// typical dose, so it shouldn't spawn a card or a contributor (drops weak off-targets such as
    /// ketamine's ~28 µM κ-opioid). Distinct from ``occupancyPruneEpsilon``, which is the numeric
    /// integration tail cutoff.
    nonisolated static let minMeaningfulOccupancy = 0.05

    /// One substance-dose's contribution to one target: PK shape + the nM prefactor + that target's
    /// half-saturation constant, plus the `[onset, expiry]` active window that bounds the integration.
    private nonisolated struct Contributor {
        let onset: Double
        let expiry: Double
        let ke: Double
        let ka: Double
        let prefactorNanomolar: Double
        let halfMaxNanomolar: Double
        let confidence: ConfidenceTier
        /// Dose-relative **escalation** factor `dose ÷ the substance's heavy ceiling` for the dose
        /// that spawned this contributor — the deep-layer gate's signal (`0` when the substance has
        /// no reference dose, which keeps the gate closed). Identical across all of a dose's targets.
        let escalation: Double
        /// Whether the source substance suppresses serotonin synthesis (§3.4) — drives the SERT class's
        /// slow synthesis pool. `true` only for the MDMA-type entactogens; the fallback surrogates
        /// follow their representative (MDMA ⇒ `true`). Identical across all of a dose's targets.
        let suppressesSynthesis: Bool
    }

    /// One co-active substance's tolerance-modulation contribution at one affected class.
    private nonisolated struct ModulatorContributor {
        let onset: Double
        let expiry: Double
        let ke: Double
        let ka: Double
        let prefactorNanomolar: Double
        let halfMaxNanomolar: Double
        let muFactor: Double
    }

    /// Minutes after onset by which this contributor's occupancy has decayed below
    /// ``occupancyPruneEpsilon`` — its active-window length. Inverts the Hill isotherm and the
    /// one-compartment decay tail: occupancy `< ε ⇔ C < ε/(1−ε)·K`, and on the tail
    /// `C ≈ prefactor·(ka/(ka−ke))·e^{−ke·dt}`, so `dt = ln(peakAmp / Cthreshold) / ke`. Always covers at
    /// least the absorption peak (`Tmax`) so a contributor is never dropped before it has acted, and the
    /// `ka/(ka−ke)` coefficient over-estimates the amplitude, so the window errs long (safe).
    private nonisolated static func decayWindowMinutes(
        ke: Double, ka: Double, prefactorNanomolar: Double, halfMaxNanomolar: Double,
        epsOcc: Double = occupancyPruneEpsilon,
    ) -> Double {
        guard ke > 0, ka > 0, halfMaxNanomolar > 0, prefactorNanomolar > 0 else { return 0 }
        let tmax = PKModel.tmax(ke: ke, ka: ka)
        let cThreshold = (epsOcc / (1 - epsOcc)) * halfMaxNanomolar
        let coeff = abs(ka - ke) < 1e-10 ? 1 : ka / (ka - ke)
        let peakAmp = prefactorNanomolar * Swift.max(coeff, 1e-300)
        let ratio = peakAmp / cThreshold
        let dtTail = ratio > 1 ? log(ratio) / ke : 0
        return Swift.max(tmax * 1.5, dtTail)
    }

    /// Integrate one class's three right-shift layers (`sAcute`/`sAdaptive`/`sDeep`) over
    /// `[0, totalMinutes]`, fine-stepping only inside the contributors' merged active windows and
    /// crossing idle gaps with the exact closed-form layer decay (see
    /// ``simulate(doses:params:now:weightKg:timestepMinutes:lookbackDays:)``).
    private nonisolated static func integrateTarget(
        contributors rawContributors: [Contributor],
        modulators rawModulators: [ModulatorContributor],
        params: ReceptorClasses.Parameters,
        totalMinutes: Double,
        step: Double,
    ) -> (sAcute: Double, sAdaptive: Double, sDeep: Double, sSynthesis: Double, sAcuteSafety: Double, sAdaptiveSafety: Double) {
        var sAcute = 0.0
        var sAdaptive = 0.0
        var sDeep = 0.0
        // The slow serotonin-synthesis pool (Stage E) — gated per-cell on whether any currently-active
        // contributor is a synthesis suppressor (MDMA-type), so the SERT class recovers over weeks for
        // entactogens but only days for the cathinones. `0` for every class with `synthesisShiftMax 0`.
        var sSynthesis = 0.0
        // The differential safety endpoint's two parallel ln-shift layers (Stage C) — acute + adaptive
        // only, no deep, no escalation gate; driven by the same occupancy. Left at 0 when the class has
        // no endpoint (the result then `exp`s to a neutral `1`, but `tolerance(for:)` reports `nil`).
        var sAcuteSafety = 0.0
        var sAdaptiveSafety = 0.0
        let safetyEndpoint = params.safetyEndpoint
        guard totalMinutes > 0, step > 0, !rawContributors.isEmpty else {
            return (sAcute, sAdaptive, sDeep, sSynthesis, sAcuteSafety, sAdaptiveSafety)
        }

        let contributors = rawContributors.sorted { $0.onset < $1.onset }
        let modulators = rawModulators.sorted { $0.onset < $1.onset }

        // Merge contributor windows into the disjoint intervals where *some* contributor is active
        // (occupancy ≥ ε). Outside them occupancy is 0, so every layer decays toward 0 analytically —
        // no need to walk the grid.
        var merged: [(lo: Double, hi: Double)] = []
        for c in contributors {
            if var last = merged.last, c.onset <= last.hi {
                last.hi = Swift.max(last.hi, c.expiry)
                merged[merged.count - 1] = last
            } else {
                merged.append((c.onset, c.expiry))
            }
        }

        let lastCell = Int((totalMinutes / step).rounded(.up)) - 1
        guard lastCell >= 0 else { return (sAcute, sAdaptive, sDeep, sSynthesis, sAcuteSafety, sAdaptiveSafety) }

        /// Closed-form recovery over an idle span of `minutes` (occupancy ≡ 0): each ln-shift layer
        /// decays toward 0 (with no active contributor the escalation gate is closed anyway, so deep
        /// only relaxes). Exact for the linear leaky integrators. The safety endpoint's two layers
        /// decay on their own time-constants — the opioid respiratory layer recovers *faster* than
        /// the analgesic adaptive (τ 10 d vs 20 d), the source of the reset-after-break overdose gap.
        func recover(_ minutes: Double) {
            guard minutes > 0 else { return }
            sAcute *= exp(-minutes / params.tauAcuteMinutes)
            sAdaptive *= exp(-minutes / params.tauAdaptiveMinutes)
            sDeep *= exp(-minutes / params.tauDeepMinutes)
            sSynthesis *= exp(-minutes / params.tauSynthesisMinutes)
            if let safetyEndpoint {
                sAcuteSafety *= exp(-minutes / safetyEndpoint.tauAcuteMinutes)
                sAdaptiveSafety *= exp(-minutes / safetyEndpoint.tauAdaptiveMinutes)
            }
        }

        var activeContributors: [Contributor] = []
        var activeModulators: [ModulatorContributor] = []
        var nextContributor = 0
        var nextModulator = 0
        var lastSteppedCell = -1 // index of the last grid cell that was fine-stepped

        for interval in merged {
            // Cells (interior midpoint = (index + 0.5)·step) whose midpoint falls inside this window.
            let firstCell = Swift.max(0, Int((interval.lo / step - 0.5).rounded(.up)))
            let lastCellInRun = Swift.min(lastCell, Int((interval.hi / step - 0.5).rounded(.down)))
            guard firstCell <= lastCellInRun else { continue }

            // Jump the idle cells between the last fine-stepped cell and this run.
            if firstCell > lastSteppedCell + 1 {
                recover(Double(firstCell - lastSteppedCell - 1) * step)
            }

            for cell in firstCell ... lastCellInRun {
                let cellStart = Double(cell) * step
                let cellLength = Swift.min(step, totalMinutes - cellStart)
                if cellLength <= 0 { break }
                let midpoint = cellStart + cellLength / 2

                while nextContributor < contributors.count, contributors[nextContributor].onset <= midpoint {
                    activeContributors.append(contributors[nextContributor]); nextContributor += 1
                }
                while nextModulator < modulators.count, modulators[nextModulator].onset <= midpoint {
                    activeModulators.append(modulators[nextModulator]); nextModulator += 1
                }

                // Combined occupancy = union `1 − ∏(1 − occupancyᵢ)`, computed inline while compacting
                // expired contributors in place — no per-cell allocation (the hot path over a dense log).
                // The peak escalation among the *currently-active* contributors drives the deep gate.
                var complement = 1.0
                var maxEscalation = 0.0
                // Whether any currently-active contributor suppresses serotonin synthesis (§3.4) —
                // the slow synthesis pool's drive (OR over survivors).
                var anySynthesisSuppressor = false
                var writeIndex = 0
                for readIndex in activeContributors.indices {
                    let contributor = activeContributors[readIndex]
                    if contributor.expiry < midpoint { continue }
                    if writeIndex != readIndex { activeContributors[writeIndex] = contributor }
                    writeIndex += 1
                    if contributor.escalation > maxEscalation { maxEscalation = contributor.escalation }
                    if contributor.suppressesSynthesis { anySynthesisSuppressor = true }
                    let concentration = contributor.prefactorNanomolar
                        * PKModel.concentration(at: midpoint - contributor.onset, ke: contributor.ke, ka: contributor.ka)
                    if concentration > 0 {
                        complement *= contributor.halfMaxNanomolar / (contributor.halfMaxNanomolar + concentration)
                    }
                }
                if writeIndex < activeContributors.count {
                    activeContributors.removeLast(activeContributors.count - writeIndex)
                }
                let occupancy = 1 - complement

                // μ(t): tolerance-modulation factor driving the adaptive layer only (Stage 4b),
                // same inline-compaction pattern.
                var modulation = 1.0
                if !activeModulators.isEmpty {
                    var modWriteIndex = 0
                    for readIndex in activeModulators.indices {
                        let modulator = activeModulators[readIndex]
                        if modulator.expiry < midpoint { continue }
                        if modWriteIndex != readIndex { activeModulators[modWriteIndex] = modulator }
                        modWriteIndex += 1
                        let freeConcentration = modulator.prefactorNanomolar
                            * PKModel.concentration(at: midpoint - modulator.onset, ke: modulator.ke, ka: modulator.ka)
                        if freeConcentration > 0 {
                            let presence = freeConcentration / (modulator.halfMaxNanomolar + freeConcentration)
                            modulation *= (1 - (1 - modulator.muFactor) * presence)
                        }
                    }
                    if modWriteIndex < activeModulators.count {
                        activeModulators.removeLast(activeModulators.count - modWriteIndex)
                    }
                }

                // Advance the three ln-shift layers. The deep gate is driven by the *dose-relative
                // escalation* (dose ÷ heavy ceiling) of the active contributors, not the adaptive
                // shift: saturating occupancy makes therapeutic and heavy dosing look identical at the
                // receptor, so only the dose-to-heavy ratio separates "significant escalation". Deep
                // therefore accrues only when a dose is both well above the heavy ceiling (the gate)
                // and sustained (the months-τ leaky integrator × the occupancy term).
                sAcute = PDModel.stepShift(
                    current: sAcute, shiftMax: params.acuteShiftMax, occupancy: occupancy,
                    drive: 1, dtMinutes: cellLength, tauMinutes: params.tauAcuteMinutes,
                )
                let gate = PDModel.deepGate(
                    escalation: maxEscalation, threshold: params.deepEscThreshold, width: params.deepEscWidth,
                )
                sAdaptive = PDModel.stepShift(
                    current: sAdaptive, shiftMax: params.adaptiveShiftMax, occupancy: occupancy,
                    drive: modulation, dtMinutes: cellLength, tauMinutes: params.tauAdaptiveMinutes,
                )
                sDeep = PDModel.stepShift(
                    current: sDeep, shiftMax: params.deepShiftMax, occupancy: occupancy,
                    drive: gate, dtMinutes: cellLength, tauMinutes: params.tauDeepMinutes,
                )
                // The slow synthesis pool (Stage E, §3.4): same occupancy, driven only while a
                // synthesis-suppressing contributor is active — so MDMA-type entactogens build this
                // weeks-τ pool while the cathinone releasers (drive 0) never do. Inert for every class
                // whose `synthesisShiftMax` is 0 (no shift accrues regardless of the drive).
                sSynthesis = PDModel.stepShift(
                    current: sSynthesis, shiftMax: params.synthesisShiftMax, occupancy: occupancy,
                    drive: anySynthesisSuppressor ? 1 : 0, dtMinutes: cellLength,
                    tauMinutes: params.tauSynthesisMinutes,
                )

                // The differential safety endpoint's two parallel layers (Stage C) — same occupancy,
                // its own kinetics, no deep and no escalation gate. The acute layer is `drive: 1`; the
                // adaptive layer shares the primary's tolerance-modulation `μ`.
                if let safetyEndpoint {
                    sAcuteSafety = PDModel.stepShift(
                        current: sAcuteSafety, shiftMax: safetyEndpoint.acuteShiftMax, occupancy: occupancy,
                        drive: 1, dtMinutes: cellLength, tauMinutes: safetyEndpoint.tauAcuteMinutes,
                    )
                    sAdaptiveSafety = PDModel.stepShift(
                        current: sAdaptiveSafety, shiftMax: safetyEndpoint.adaptiveShiftMax, occupancy: occupancy,
                        drive: modulation, dtMinutes: cellLength, tauMinutes: safetyEndpoint.tauAdaptiveMinutes,
                    )
                }
            }
            lastSteppedCell = lastCellInRun
        }

        // Final idle tail from the last fine-stepped cell to `now` (covers a partial last cell exactly).
        recover(totalMinutes - Double(lastSteppedCell + 1) * step)
        return (sAcute, sAdaptive, sDeep, sSynthesis, sAcuteSafety, sAdaptiveSafety)
    }

    // MARK: - Persistence (cache)

    /// Reload the cached per-class snapshot. The `ToleranceState.target` column stores the
    /// ``ReceptorClasses/ReceptorClass`` raw value now (the entity is a disposable cache; the column
    /// name is kept to avoid a non-additive rename). Sub-targets aren't persisted — they're recomputed
    /// on the next replay, which the background refresh kicks off at launch anyway.
    private func loadCachedSnapshot() {
        guard let context else { return }
        guard let rows = try? context.fetch(FetchDescriptor<ToleranceState>()) else { return }
        var loaded: [ReceptorClasses.ReceptorClass: ClassTolerance] = [:]
        for row in rows {
            guard let receptorClass = ReceptorClasses.ReceptorClass(rawValue: row.target) else { continue }
            // The cache only carries the three ln-shift layers; representativeOccupancy, sub-targets,
            // contributors and the real confidence are recomputed on the first replay (the background
            // refresh runs at launch), so warm them with neutral placeholders — overwritten promptly.
            loaded[receptorClass] = ClassTolerance(
                receptorClass: receptorClass,
                sAcute: row.sAcute, sAdaptive: row.sAdaptive, sDeep: row.sDeep,
                sSynthesis: row.sSynthesis,
                representativeOccupancy: 0.5,
                confidence: .unverified,
                subTargets: [], contributors: [],
                // The cache carries no safety state — recomputed on the first replay (Stage C).
                safetyShiftFactor: nil, safetyEndpointKind: nil,
            )
        }
        states = loaded
    }

    /// Write the durable ``ToleranceState`` cache **off the main actor**.
    ///
    /// The save flushes to the SQLite store and, at launch, showed up as a ~190 ms main-thread block
    /// (SwiftData store flush) right after the off-main replay. Because these rows are a *cache* —
    /// written only here and re-read only at launch via ``loadCachedSnapshot()``, with the in-memory
    /// ``states`` being the live source of truth the UI observes — the write can run on a throwaway
    /// background ``ModelContext`` created from the (Sendable) container, so it never touches the main
    /// thread. Overlapping writes self-heal (last-writer-wins on a cache); the 2 s debounce + signature
    /// gate already make concurrent persists rare.
    private func persist(_ computed: [ReceptorClasses.ReceptorClass: ClassTolerance], now: Date) {
        guard let container else { return }
        Task.detached(priority: .utility) {
            let context = ModelContext(container)
            let existing = (try? context.fetch(FetchDescriptor<ToleranceState>())) ?? []
            var byKey = Dictionary(existing.map { ($0.target, $0) }, uniquingKeysWith: { a, _ in a })

            for (receptorClass, t) in computed {
                let key = receptorClass.rawValue
                if let row = byKey[key] {
                    row.sAcute = t.sAcute
                    row.sAdaptive = t.sAdaptive
                    row.sDeep = t.sDeep
                    row.sSynthesis = t.sSynthesis
                    row.lastUpdated = now
                } else {
                    context.insert(ToleranceState(
                        target: key, sAcute: t.sAcute, sAdaptive: t.sAdaptive,
                        sDeep: t.sDeep, sSynthesis: t.sSynthesis, lastUpdated: now,
                    ))
                }
                byKey[key] = nil
            }
            // Leftover rows: legacy per-receptor cache keys (pre per-class refactor) aren't valid class
            // raw values — delete them. A class no longer driven by any in-window dose is reset to naïve
            // (all layers 0 ⇒ S = 1) rather than deleted (stable row set; a recovered class reads rested).
            for (key, stale) in byKey {
                if ReceptorClasses.ReceptorClass(rawValue: key) == nil {
                    context.delete(stale)
                } else {
                    stale.sAcute = 0
                    stale.sAdaptive = 0
                    stale.sDeep = 0
                    stale.sSynthesis = 0
                    stale.lastUpdated = now
                }
            }

            try? context.save()
        }
    }
}
