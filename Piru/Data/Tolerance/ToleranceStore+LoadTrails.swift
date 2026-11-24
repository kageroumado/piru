import Foundation

/// The relative-load trails Receptor Load and the GABA loading card draw, read from the same
/// pharmacology and replay preparation as the tolerance snapshot.
extension ToleranceStore {
    /// Forward relative-load curve for one class from `now` (∈ [0, 1], fraction of the user's recent peak
    /// drive) — the saturation-immune clearance the withdrawal clock and the receptor-loading card read.
    /// Resolves pharmacology + body weight exactly as ``recompute(from:now:)`` does, then evaluates the
    /// class's active contributors off main.
    func loadTrail(
        for receptorClass: ReceptorClasses.ReceptorClass,
        from entries: [DoseEntry],
        now: Date = .now,
        pastHorizon: TimeInterval = 0,
        horizon: TimeInterval = 21 * 86_400,
        step: TimeInterval = 3 * 3_600,
    ) async -> [(date: Date, load: Double)] {
        let weightKg = UserProfileStore.shared.effectiveWeightKg
        let doses = Self.snapshots(of: entries).map {
            SimDose(substance: $0.substance, amountMg: $0.dose.milligrams, timestamp: $0.timestamp)
        }
        let params = await parameters(for: doses)
        return Self.loadTrail(
            doses: doses, params: params, now: now, weightKg: weightKg,
            receptorClass: receptorClass, horizonMinutes: horizon / 60, stepMinutes: step / 60,
            pastHorizonMinutes: pastHorizon / 60,
        )
    }

    /// The past relative-load trail of every class in `classes` over `[now − pastHorizon, now]`, keyed
    /// by class; a class no in-window dose drives has no key. One pharmacology read and one replay
    /// preparation serve all the classes, off the main actor, and every trail ends with a sample at
    /// `now` whatever the step. The values match ``loadTrail(for:from:now:pastHorizon:horizon:step:)``
    /// at every sample the two share.
    func loadTrails(
        for classes: Set<ReceptorClasses.ReceptorClass>,
        from entries: [DoseEntry],
        now: Date = .now,
        pastHorizon: TimeInterval,
        step: TimeInterval,
    ) async -> [ReceptorClasses.ReceptorClass: [(date: Date, load: Double)]] {
        let weightKg = UserProfileStore.shared.effectiveWeightKg
        let doses = Self.snapshots(of: entries).map {
            SimDose(substance: $0.substance, amountMg: $0.dose.milligrams, timestamp: $0.timestamp)
        }
        let params = await parameters(for: doses)
        return await Task.detached(priority: .userInitiated) {
            Self.loadTrails(
                doses: doses, params: params, now: now, weightKg: weightKg, classes: classes,
                stepMinutes: step / 60, pastHorizonMinutes: pastHorizon / 60,
            )
        }.value
    }
}
