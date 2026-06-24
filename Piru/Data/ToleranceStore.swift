import AsyncAlgorithms
import Foundation
import SwiftData

/// A snapshot of tolerance state at one receptor target, derived by replaying the dose log. The
/// value type the UI reads (Stage 2); the SwiftData ``ToleranceState`` row is its cached persistence.
nonisolated struct TargetTolerance: Hashable, Identifiable {
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

/// A predicted **cross-tolerance** readout for a substance about to be logged: the shared receptor
/// availability `A_R` at one engaged class, already lowered by recent use of substances that hit the
/// same target. Surfaced at dose entry (Stage 4a) — "≈X% of rested response."
struct CrossToleranceReadout: Identifiable {
    let receptorClass: ReceptorClasses.ReceptorClass
    /// Predicted availability `A_R` ∈ [0, 1] — 1 = rested. The "% of rested response."
    let availability: Double
    /// Substances driving this class's tolerance, recency order (may include the same substance's own
    /// recent doses — same-drug tolerance is as real as cross-drug).
    let contributors: [String]
    let confidence: ConfidenceTier

    var id: String {
        receptorClass.rawValue
    }

    /// Predicted response as a percentage of rested.
    var responsePercent: Int {
        Int((min(1, max(0, availability)) * 100).rounded())
    }
}

/// A predicted **reset-after-break overdose** risk for a μ-opioid about to be logged (Stage 5 opioid
/// safety axis). Fires *only* in the genuine relapse window: the user built real μ-opioid tolerance,
/// then a break let availability recover toward naïve — so a dose that was tolerated before the break
/// can now stop their breathing. Deliberately narrow (false positives spend trust); a naïve first-timer
/// and a still-actively-using person both fail the gate.
struct OpioidResetRisk: Identifiable {
    /// Lowest μ-opioid availability reached before the break — how tolerant they had become (≤ 1).
    let peakAvailability: Double
    /// Current μ-opioid availability, recovered toward naïve over the break.
    let currentAvailability: Double
    /// Whole days since the last opioid dose (the break length).
    let breakDays: Int
    /// The opioids that drove the prior tolerance, most-recent first.
    let contributors: [String]
    let confidence: ConfidenceTier

    var id: String {
        "opioid-reset"
    }

    /// Current response as a percentage of a rested/naïve system — how hard the old dose now hits.
    var currentResponsePercent: Int {
        Int((min(1, max(0, currentAvailability)) * 100).rounded())
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
    nonisolated static let defaultTimestepMinutes = 30.0

    /// How far back the replay reaches. Beyond the longest recovery/decay τ (a few months) a dose's
    /// contribution has decayed to nothing, so older history is dropped to bound the work.
    nonisolated static let defaultLookbackDays = 547.0 // ~18 months

    /// Lookback for the cross-tolerance readout (Stage 4a). Cross-tolerance reads only the *availability*
    /// axis, whose slowest recovery τ among multiplier classes is ~10 days (opioid/GABA), so a dose more
    /// than ~6 τ back has recovered to <1% and contributes nothing. 90 days is a generous margin and a
    /// far smaller fetch/replay than the 18-month load window (the LOAD axis, which needs the long
    /// window, is not used here).
    static let crossToleranceLookbackDays = 90.0

    /// Current per-target tolerance snapshot, keyed by target. Observation-tracked; views read this.
    private(set) var states: [String: TargetTolerance] = [:]

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
        var params: [String: PharmacologyParameters] = [:]
        var resolved = Set<String>()
        for dose in doses where resolved.insert(dose.substance).inserted {
            params[dose.substance] = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: dose.substance)
        }

        let computed = await Self.computeOffMain(doses: doses, params: params, now: now, weightKg: weightKg)
        states = computed
        lastSignature = signature
        persist(computed, now: now)
    }

    /// Run the parallel replay off the main actor and off the shared cooperative pool by pinning it to
    /// ``replayExecutor``. `withTaskExecutorPreference` makes that pin apply to the whole operation *and*
    /// the `TaskGroup` children spawned inside ``simulateConcurrently(doses:params:now:weightKg:...)`` —
    /// and, because the preference is explicit, it also overrides `NonisolatedNonsendingByDefault`
    /// (SE-0461), which would otherwise run this nonisolated async work back on the caller's (main) actor.
    /// Structured (cancellation propagates) — no manual continuation, no `concurrentPerform`.
    private nonisolated static func computeOffMain(
        doses: [SimDose], params: [String: PharmacologyParameters], now: Date, weightKg: Double,
    ) async -> [String: TargetTolerance] {
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

    /// Current availability at a target, or `nil` if untracked (treated as naïve `1` by callers).
    func tolerance(forTarget target: String) -> TargetTolerance? {
        states[target]
    }

    // MARK: - Cross-tolerance readout (Stage 4a)

    /// Predicted **cross-tolerance** for a substance about to be logged: the already-computed shared
    /// availability `A_R` at the receptor classes it engages, lowered by *other* recent substances that
    /// hit the same target ("≈X% of rested response — shared 5-HT2A tolerance from LSD 3 days ago").
    ///
    /// Reads the **warm ``states`` snapshot** (kept fresh by the background refresh) for the engaged
    /// classes' availability, and a cheap recent-window fetch only for the *contributor names* — so this
    /// interactive path does **no replay** (it was ~650 ms over a multi-thousand-dose log). The prospective
    /// dose itself is excluded — tolerance is a property of *past* exposure. Falls back to a (now fast,
    /// near-linear) replay if the cache hasn't warmed yet — e.g. immediately after launch. Returns `[]`
    /// before launch configuration.
    func crossToleranceReadouts(forSubstance name: String, now: Date = .now) -> [CrossToleranceReadout] {
        guard let context else { return [] }
        let resolve: (String) -> PharmacologyParameters? = {
            SubstanceStore.shared.pharmacologyParameters(forSubstanceName: $0)
        }
        // Recent window supplies only the contributor list (which substances drive each class). For a
        // multiplier class (availability τ ≤ ~10 d) the warm 18-month `states` and a 90-day replay agree.
        let cutoff = now.addingTimeInterval(-Self.crossToleranceLookbackDays * 86_400)
        let descriptor = FetchDescriptor<DoseEntry>(predicate: #Predicate<DoseEntry> { $0.timestamp >= cutoff })
        let recent = (try? context.fetch(descriptor)) ?? []

        if states.isEmpty {
            // Cache not warmed yet — replay the recent window directly (cheap on the near-linear engine).
            let weightKg = UserProfileStore.shared.effectiveWeightKg
            return Self.crossTolerance(forSubstance: name, entries: recent, now: now, weightKg: weightKg, resolve: resolve)
        }
        return Self.crossToleranceReadouts(forSubstance: name, states: states, recentEntries: recent, now: now, resolve: resolve)
    }

    /// Pure cross-tolerance computation (the testable core). Replays `entries` into a state snapshot, then
    /// derives the readouts from it. Production reads the warm snapshot instead (see the instance method);
    /// this stays the replay-based entry point the tests exercise with synthetic logs.
    @MainActor
    static func crossTolerance(
        forSubstance name: String,
        entries: [DoseEntry],
        now: Date,
        weightKg: Double,
        minReduction: Double = 0.1,
        resolve: (String) -> PharmacologyParameters?,
    ) -> [CrossToleranceReadout] {
        let states = simulate(entries: entries, now: now, weightKg: weightKg, resolve: resolve)
        guard !states.isEmpty else { return [] }
        return crossToleranceReadouts(
            forSubstance: name, states: states, recentEntries: entries, now: now,
            minReduction: minReduction, resolve: resolve,
        )
    }

    /// Derive cross-tolerance readouts from an **already-computed** state snapshot — no replay. For each
    /// receptor **class** the prospective substance engages that is a valid effect *multiplier*
    /// (``ReceptorClasses/Parameters/usesEffectMultiplier`` — psychedelic / opioid / GABA / NMDA / CB1 /
    /// adenosine; stimulants/releasers are excluded because their slow axis is LOAD, not a multiplier), it
    /// surfaces the worst (lowest-availability) shared state of that class and the substances (from
    /// `recentEntries`) driving it. Only classes reduced by at least `minReduction` are returned, worst first.
    @MainActor
    static func crossToleranceReadouts(
        forSubstance name: String,
        states: [String: TargetTolerance],
        recentEntries: [DoseEntry],
        now: Date,
        minReduction: Double = 0.1,
        resolve: (String) -> PharmacologyParameters?,
    ) -> [CrossToleranceReadout] {
        guard let prospective = resolve(name) else { return [] }

        // Receptor classes the prospective substance engages whose *availability* axis is a valid
        // multiplier (the only classes for which "≈X% of rested response" is meaningful). `.unknown`
        // is excluded: a "% of rested" readout for an uncurated receptor with class-default kinetics is
        // noise, even though that fallback class nominally allows the multiplier.
        var engagedClasses = Set<ReceptorClasses.ReceptorClass>()
        for engagement in prospective.targets {
            let cls = ReceptorClasses.classify(target: engagement.target, action: engagement.action)
            guard cls != .unknown, ReceptorClasses.parameters(for: cls).usesEffectMultiplier else { continue }
            engagedClasses.insert(cls)
        }
        guard !engagedClasses.isEmpty, !states.isEmpty else { return [] }

        // Substances driving each engaged class, recency order, deduped — mirrors `simulate`'s gating
        // (only occupancy-computable substances contribute) so the names match the computed state.
        let sortedDesc = recentEntries.filter { $0.timestamp <= now }.sorted { $0.timestamp > $1.timestamp }
        var contributorsByClass: [ReceptorClasses.ReceptorClass: [String]] = [:]
        var seenByClass: [ReceptorClasses.ReceptorClass: Set<String>] = [:]
        var paramCache: [String: PharmacologyParameters?] = [:]
        for entry in sortedDesc {
            let params: PharmacologyParameters?
            if let cached = paramCache[entry.substance] {
                params = cached
            } else {
                params = resolve(entry.substance)
                paramCache[entry.substance] = params
            }
            guard let params, params.canComputeOccupancy else { continue }
            for engagement in params.targets {
                let cls = ReceptorClasses.classify(target: engagement.target, action: engagement.action)
                guard engagedClasses.contains(cls) else { continue }
                if seenByClass[cls, default: []].insert(entry.substance).inserted {
                    contributorsByClass[cls, default: []].append(entry.substance)
                }
            }
        }

        var readouts: [CrossToleranceReadout] = []
        for cls in engagedClasses {
            let classStates = states.values.filter { $0.receptorClass == cls }
            guard let worst = classStates.min(by: { $0.availability < $1.availability }),
                  (1 - worst.availability) >= minReduction else { continue }
            readouts.append(CrossToleranceReadout(
                receptorClass: cls,
                availability: worst.availability,
                contributors: contributorsByClass[cls] ?? [],
                confidence: classStates.map(\.confidence).min() ?? worst.confidence,
            ))
        }
        return readouts.sorted { $0.availability < $1.availability }
    }

    // MARK: - Opioid reset-after-break overdose (Stage 5 safety axis)

    /// Peak μ-opioid availability ≤ this counts as having built genuine tolerance (≥ ~40% depressed).
    static let opioidTolerantThreshold = 0.6
    /// Current μ-opioid availability ≥ this counts as having recovered toward naïve over the break.
    static let opioidRecoveredThreshold = 0.78
    /// Minimum availability regained (current − peak) for the reset to be meaningful, not noise.
    static let opioidMinRecovery = 0.18
    /// Minimum gap since the last opioid dose to count as a break (days). Below this they're still
    /// actively using and the dose matches their tolerance — not a reset.
    static let opioidMinBreakDays = 5.0

    /// Predicted reset-after-break overdose risk for a μ-opioid about to be logged. Fetches the opioid
    /// window from the store's own context and replays it; returns `nil` (no warning) unless the full
    /// relapse pattern holds. See ``opioidResetRisk(forSubstance:entries:now:weightKg:resolve:)``.
    func opioidResetRisk(forSubstance name: String, now: Date = .now) -> OpioidResetRisk? {
        guard let context else { return nil }
        // Reach back far enough to see a long break after a using period (the classic post-detox window).
        let cutoff = now.addingTimeInterval(-Self.defaultLookbackDays * 86_400)
        let descriptor = FetchDescriptor<DoseEntry>(predicate: #Predicate<DoseEntry> { $0.timestamp >= cutoff })
        guard let entries = try? context.fetch(descriptor) else { return nil }
        let weightKg = UserProfileStore.shared.effectiveWeightKg
        return Self.opioidResetRisk(forSubstance: name, entries: entries, now: now, weightKg: weightKg) {
            SubstanceStore.shared.pharmacologyParameters(forSubstanceName: $0)
        }
    }

    /// Pure reset-after-break computation (the testable core). Fires only when **all** hold:
    /// 1. the prospective substance is a μ-opioid agonist (a respiratory depressant — the reset axis);
    /// 2. the user has prior μ-opioid doses (a naïve first-timer is *not* a reset, even at full availability);
    /// 3. a genuine break since the last opioid dose (``opioidMinBreakDays``);
    /// 4. real prior tolerance — peak (lowest) μ-opioid availability before the break ≤ ``opioidTolerantThreshold``;
    /// 5. that availability has since recovered toward naïve (≥ ``opioidRecoveredThreshold`` *and* by
    ///    ≥ ``opioidMinRecovery``), so the old dose now lands on a far less tolerant system.
    @MainActor
    static func opioidResetRisk(
        forSubstance name: String,
        entries: [DoseEntry],
        now: Date,
        weightKg: Double,
        resolve: (String) -> PharmacologyParameters?,
    ) -> OpioidResetRisk? {
        var paramCache: [String: PharmacologyParameters?] = [:]
        func params(_ s: String) -> PharmacologyParameters? {
            if let cached = paramCache[s] { return cached }
            let p = resolve(s)
            paramCache[s] = p
            return p
        }
        func engagesMuOpioid(_ p: PharmacologyParameters) -> Bool {
            p.targets.contains { ReceptorClasses.classify(target: $0.target, action: $0.action) == .muOpioid }
        }

        // 1. The prospective substance must be a μ-opioid agonist.
        guard let prospective = params(name), engagesMuOpioid(prospective) else { return nil }

        // 2. Prior μ-opioid doses (occupancy-computable, so they actually drove tolerance), recency-first.
        let past = entries.filter { $0.timestamp <= now }.sorted { $0.timestamp > $1.timestamp }
        let opioidPast = past.filter { e in
            guard let p = params(e.substance), p.canComputeOccupancy else { return false }
            return engagesMuOpioid(p)
        }
        guard let lastDose = opioidPast.first else { return nil }

        // 3. A genuine break since the last opioid dose.
        let breakInterval = now.timeIntervalSince(lastDose.timestamp)
        guard breakInterval >= opioidMinBreakDays * 86_400 else { return nil }

        /// 4. Real prior tolerance: the lowest μ-opioid availability reached by the end of the using period.
        func muAvailability(at instant: Date) -> Double? {
            let states = simulate(entries: opioidPast, now: instant, weightKg: weightKg, resolve: resolve)
            return states.values.filter { $0.receptorClass == .muOpioid }.map(\.availability).min()
        }
        guard let peakAvail = muAvailability(at: lastDose.timestamp), peakAvail <= opioidTolerantThreshold else { return nil }

        // 5. …that has since recovered toward naïve over the break.
        guard let currentAvail = muAvailability(at: now),
              currentAvail >= opioidRecoveredThreshold,
              currentAvail - peakAvail >= opioidMinRecovery else { return nil }

        var seen = Set<String>()
        let contributors = opioidPast.map(\.substance).filter { seen.insert($0).inserted }
        let confidence = simulate(entries: opioidPast, now: lastDose.timestamp, weightKg: weightKg, resolve: resolve)
            .values.filter { $0.receptorClass == .muOpioid }.map(\.confidence).min() ?? .low

        return OpioidResetRisk(
            peakAvailability: peakAvail,
            currentAvailability: currentAvail,
            breakDays: Int((breakInterval / 86_400).rounded(.down)),
            contributors: contributors,
            confidence: confidence,
        )
    }

    // MARK: - Pure replay (the testable core)

    /// Replay a dose log into per-target tolerance state. Pure aside from the injected `resolve`
    /// closure (production passes `SubstanceStore`), so the gate runs without a container or singleton.
    ///
    /// Each substance contributes a time-resolved occupancy curve at every target it engages
    /// (absolute molar concentration → Hill occupancy, Foundation A); contributions at a *shared*
    /// target combine via ``PDModel/combinedOccupancy(_:)``, and that combined occupancy drives the
    /// per-target availability/acute/load ODEs with the class's ``ReceptorClasses/Parameters``.
    /// A `Sendable` snapshot of one logged dose, so the heavy replay can run **off the main actor**
    /// (a SwiftData `DoseEntry` is a non-`Sendable` `@Model` and can't cross an isolation boundary).
    /// The unit→mg conversion is done while building the snapshot (on the actor that owns the entry).
    struct SimDose {
        let substance: String
        let amountMg: Double?
        let timestamp: Date

        init(substance: String, amountMg: Double?, timestamp: Date) {
            self.substance = substance
            self.amountMg = amountMg
            self.timestamp = timestamp
        }
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
    ) -> [String: TargetTolerance] {
        let doses = entries.map {
            SimDose(substance: $0.substance, amountMg: DoseUnit.convert($0.amount, from: $0.unit, to: "mg"), timestamp: $0.timestamp)
        }
        var params: [String: PharmacologyParameters] = [:]
        var resolved = Set<String>()
        for dose in doses where resolved.insert(dose.substance).inserted {
            if let p = resolve(dose.substance) { params[dose.substance] = p }
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
    /// availability/acute/load ODEs with the class's ``ReceptorClasses/Parameters``.
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
    ) -> [String: TargetTolerance] {
        guard let prepared = buildTargetWork(
            doses: doses, params: params, now: now, weightKg: weightKg, lookbackDays: lookbackDays,
        ) else { return [:] }

        var result = [String: TargetTolerance](minimumCapacity: prepared.work.count)
        for work in prepared.work {
            result[work.target] = tolerance(for: work, totalMinutes: prepared.totalMinutes, step: timestepMinutes)
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
    ) async -> [String: TargetTolerance] {
        guard let prepared = buildTargetWork(
            doses: doses, params: params, now: now, weightKg: weightKg, lookbackDays: lookbackDays,
        ) else { return [:] }
        let totalMinutes = prepared.totalMinutes
        let step = timestepMinutes

        return await withTaskGroup(of: (String, TargetTolerance).self) { group in
            for work in prepared.work {
                group.addTask { (work.target, tolerance(for: work, totalMinutes: totalMinutes, step: step)) }
            }
            var result = [String: TargetTolerance](minimumCapacity: prepared.work.count)
            for await (target, state) in group {
                result[target] = state
            }
            return result
        }
    }

    /// One target's full replay input: its contributors, its receptor class, and the modulators acting on
    /// that class. `Sendable` so it can be handed to a `TaskGroup` child for off-actor integration.
    private struct TargetWork {
        let target: String
        let receptorClass: ReceptorClasses.ReceptorClass
        let contributors: [Contributor]
        let modulators: [ModulatorContributor]
    }

    /// Shared, cheap (serial) preparation for both `simulate` variants: filter the log to the lookback
    /// window, turn each dose into per-target ``Contributor``s (and per-class tolerance modulators), and
    /// group them into independent ``TargetWork`` units. Returns `nil` when there is nothing to replay.
    private nonisolated static func buildTargetWork(
        doses: [SimDose],
        params: [String: PharmacologyParameters],
        now: Date,
        weightKg: Double,
        lookbackDays: Double,
    ) -> (work: [TargetWork], totalMinutes: Double)? {
        let cutoff = now.addingTimeInterval(-lookbackDays * 86_400)
        let relevant = doses
            .filter { $0.timestamp <= now && $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }
        guard let start = relevant.first?.timestamp, weightKg > 0 else { return nil }

        var contributorsByTarget: [String: [Contributor]] = [:]
        var classByTarget: [String: ReceptorClasses.ReceptorClass] = [:]
        // Tolerance-modulation contributors keyed by the *affected* class (Stage 4b): an NMDA
        // antagonist onboard lowers μ-opioid tolerance development, etc.
        var modulatorsByClass: [ReceptorClasses.ReceptorClass: [ModulatorContributor]] = [:]

        for dose in relevant {
            guard let p = params[dose.substance], p.canComputeOccupancy,
                  let vdPerKg = p.vdLPerKg, let mw = p.molarMassGramsPerMole,
                  let f = p.bioavailabilityFraction, let halfLife = p.halfLifeMinutes,
                  let doseMg = dose.amountMg
            else { continue }
            let vd = vdPerKg * weightKg
            guard vd > 0, mw > 0, halfLife > 0 else { continue }
            let ke = PKModel.ke(fromHalfLifeMinutes: halfLife)
            let ka = PKModel.defaultKa(ke: ke)
            // molar = (F·dose/Vd)·shape /1000 /MW ; ×1e9 → nM (fu = 1, Stage 1). One concentration()
            // call per contributor per step then multiplies this prefactor.
            let prefactorNanomolar = (f * doseMg / vd) / 1_000 / mw * 1e9
            let onset = dose.timestamp.timeIntervalSince(start) / 60

            // Most-potent target per class (p.targets is tightest-first, so the first per class wins) —
            // used both to route the contributor and to drive any modulation edge's presence curve.
            var bestTargetByClass: [ReceptorClasses.ReceptorClass: PharmacologyParameters.TargetEngagement] = [:]
            for engagement in p.targets {
                let cls = ReceptorClasses.classify(target: engagement.target, action: engagement.action)
                if bestTargetByClass[cls] == nil { bestTargetByClass[cls] = engagement }
                let expiry = onset + decayWindowMinutes(
                    ke: ke, ka: ka, prefactorNanomolar: prefactorNanomolar,
                    halfMaxNanomolar: engagement.halfMaxNanomolar,
                )
                contributorsByTarget[engagement.target, default: []].append(
                    Contributor(
                        onset: onset, expiry: expiry, ke: ke, ka: ka,
                        prefactorNanomolar: prefactorNanomolar,
                        halfMaxNanomolar: engagement.halfMaxNanomolar,
                        confidence: Swift.min(p.vdConfidence, engagement.confidence),
                    ),
                )
                classByTarget[engagement.target] = cls
            }

            // Register this dose as a tolerance modulator for any class it modulates. Presence is the
            // occupancy of its most-potent target *of the modulating class*, so the edge fires only
            // while the modulator is actually onboard (concentration/overlap-gated).
            for (modClass, best) in bestTargetByClass {
                for edge in ToleranceModulation.edges(forModulatorClass: modClass) {
                    let expiry = onset + decayWindowMinutes(
                        ke: ke, ka: ka, prefactorNanomolar: prefactorNanomolar,
                        halfMaxNanomolar: best.halfMaxNanomolar,
                    )
                    modulatorsByClass[edge.affectedClass, default: []].append(
                        ModulatorContributor(
                            onset: onset, expiry: expiry, ke: ke, ka: ka,
                            prefactorNanomolar: prefactorNanomolar,
                            halfMaxNanomolar: best.halfMaxNanomolar,
                            muFactor: edge.muFactor,
                        ),
                    )
                }
            }
        }
        guard !contributorsByTarget.isEmpty else { return nil }

        let work = contributorsByTarget.map { target, contributors -> TargetWork in
            let receptorClass = classByTarget[target] ?? .unknown
            return TargetWork(
                target: target, receptorClass: receptorClass,
                contributors: contributors, modulators: modulatorsByClass[receptorClass] ?? [],
            )
        }
        return (work, now.timeIntervalSince(start) / 60)
    }

    /// Integrate one prepared ``TargetWork`` into its tolerance snapshot — the unit of work both `simulate`
    /// drivers run (serially or as a `TaskGroup` child).
    private nonisolated static func tolerance(
        for work: TargetWork, totalMinutes: Double, step: Double,
    ) -> TargetTolerance {
        let params = ReceptorClasses.parameters(for: work.receptorClass)
        let state = integrateTarget(
            contributors: work.contributors, modulators: work.modulators,
            params: params, totalMinutes: totalMinutes, step: step,
        )
        let inputConfidence = work.contributors.map(\.confidence).min() ?? .unverified
        return TargetTolerance(
            target: work.target, receptorClass: work.receptorClass,
            availability: state.availability, acute: state.acute, load: state.load,
            confidence: Swift.min(inputConfidence, params.confidence),
        )
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
    /// At 1e-9 the discarded tail's effect on availability/load is ≪ 1e-6 (far below the integer-percent
    /// the UI shows); the golden test (`ToleranceGoldenTests`) pins the resulting numbers to the dense
    /// replay within 1e-6 to keep this honest.
    nonisolated static let occupancyPruneEpsilon = 1e-9

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

    /// Integrate one target's availability / acute / load over `[0, totalMinutes]`, fine-stepping only
    /// inside the contributors' merged active windows and crossing idle gaps with the exact closed-form
    /// recovery (see ``simulate(doses:params:now:weightKg:timestepMinutes:lookbackDays:)``).
    private nonisolated static func integrateTarget(
        contributors rawContributors: [Contributor],
        modulators rawModulators: [ModulatorContributor],
        params: ReceptorClasses.Parameters,
        totalMinutes: Double,
        step: Double,
    ) -> (availability: Double, acute: Double, load: Double) {
        var availability = 1.0
        var acute = 1.0
        var load = 0.0
        guard totalMinutes > 0, step > 0, !rawContributors.isEmpty else {
            return (availability, acute, load)
        }
        let hasAcute = params.hasAcutePool
        let hasLoad = params.loadGain > 0

        let contributors = rawContributors.sorted { $0.onset < $1.onset }
        let modulators = rawModulators.sorted { $0.onset < $1.onset }

        // Merge contributor windows into the disjoint intervals where *some* contributor is active
        // (occupancy ≥ ε). Outside them occupancy is 0, so availability/acute recover and load decays
        // analytically — no need to walk the grid.
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
        guard lastCell >= 0 else { return (availability, acute, load) }

        /// Closed-form recovery over an idle span of `minutes` (occupancy ≡ 0): exact for the linear ODEs.
        func recover(_ minutes: Double) {
            guard minutes > 0 else { return }
            availability = 1 + (availability - 1) * exp(-minutes / params.tauSlowMinutes)
            if hasAcute { acute = 1 + (acute - 1) * exp(-minutes / params.tauAcuteMinutes) }
            if hasLoad { load *= exp(-minutes / params.tauLoadMinutes) }
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
                var complement = 1.0
                var writeIndex = 0
                for readIndex in activeContributors.indices {
                    let contributor = activeContributors[readIndex]
                    if contributor.expiry < midpoint { continue }
                    if writeIndex != readIndex { activeContributors[writeIndex] = contributor }
                    writeIndex += 1
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

                // μ_R(t): tolerance-modulation factor for the slow availability axis only (Stage 4b),
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

                availability = PDModel.stepAvailability(
                    availability: availability, occupancy: occupancy, dtMinutes: cellLength,
                    kappa: params.kappaSlow, tauMinutes: params.tauSlowMinutes, modulation: modulation,
                )
                if hasAcute {
                    acute = PDModel.stepAvailability(
                        availability: acute, occupancy: occupancy, dtMinutes: cellLength,
                        kappa: params.kappaAcute, tauMinutes: params.tauAcuteMinutes,
                    )
                }
                if hasLoad {
                    load = PDModel.stepLoad(
                        load: load, occupancy: occupancy, dtMinutes: cellLength,
                        tauMinutes: params.tauLoadMinutes, gain: params.loadGain,
                    )
                }
            }
            lastSteppedCell = lastCellInRun
        }

        // Final idle tail from the last fine-stepped cell to `now` (covers a partial last cell exactly).
        recover(totalMinutes - Double(lastSteppedCell + 1) * step)
        return (availability, acute, load)
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
