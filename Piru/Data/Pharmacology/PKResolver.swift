import Foundation

/// Resolves the one-compartment oral PK parameters a dose needs — the elimination
/// half-life and the `(ke, ka)` rate constants — from a substance model, its
/// aliases, and an acute duration profile.
///
/// This is the single home for half-life fallback and `ka`-from-time-to-peak
/// resolution. Never re-derive either at a call site — ``ActiveSubstanceCalculator``
/// (body-load), ``HalfLifeCalculatorView`` and ``SteadyStateView`` (the two PK
/// tools), and ``ActiveSubstanceState`` all read through here so they can't disagree.
///
/// Runs on the main actor, like the substance/duration model it reads (`midpoint`
/// and `resolveDuration` are `@MainActor`). The output is plain scalars, so the
/// `BodyLevelsManager` resolves a substance's ``Params`` once here and then reuses
/// the `(ke, ka)` doubles across an off-main per-day body-load replay against the
/// `nonisolated` ``PKModel``.
enum PKResolver {
    /// Resolved one-compartment oral PK parameters for a dose.
    struct Params: Equatable {
        /// Elimination half-life in minutes.
        let halfLifeMinutes: Double
        /// Elimination rate constant (per minute), `ln(2) / t½`.
        let ke: Double
        /// Absorption rate constant (per minute) — from the profile's time-to-peak
        /// when one is known, else ``PKModel/defaultKa(ke:)``.
        let ka: Double
    }

    /// Resolve the elimination half-life (minutes) from the substance's own record. `nil` when the
    /// database knows none — which is the honest answer for a compound nobody has measured, and is
    /// what every caller must keep handling.
    static func halfLifeMinutes(substance: Substance?, entryName _: String) -> Double? {
        guard let hl = substance?.halfLifeMinutes, hl > 0 else { return nil }
        return hl
    }

    /// The half-life (minutes) for a *specific logged dose*, depot-aware: a depot
    /// administration reports its slow terminal half-life, not the parent molecule's
    /// fast elimination. Every body-load path that has the entry in hand should use
    /// this rather than ``halfLifeMinutes(substance:entryName:)`` so a depot ester
    /// isn't shown clearing in days. `nil` when no half-life can be resolved.
    static func halfLifeMinutes(for entry: DoseEntry, substance: Substance?) -> Double? {
        depotHalfLifeMinutes(entry: entry) ?? halfLifeMinutes(substance: substance, entryName: entry.substance)
    }

    // MARK: - Depot administrations

    /// A depot dose that must not carry a depot heuristic below this, so a bad match
    /// can never fabricate a plausible-looking short half-life. 21 days spans the
    /// long injectable esters (undecylate) and the LAI antipsychotics (paliperidone
    /// palmitate ~25–49 d, aripiprazole ~30–47 d) closely enough for a body-load
    /// magnitude; the ester curves that *are* modeled bypass it with a real rate.
    private static let defaultDepotHalfLifeDays = 21.0

    /// Whether a dose is a **depot administration** — released slowly from a depot
    /// over days-to-weeks rather than acting acutely. Two signals: an injectable
    /// hormone ester (Estradiol Valerate IM/SC), or a formulation the catalog flags
    /// depot (`releaseForm` "DEP": LAI antipsychotics, Vivitrol, Depo-Provera). These
    /// have no acute onset/peak/offset curve, and their terminal half-life is
    /// governed by slow release (flip-flop kinetics), not the molecule's elimination.
    static func isDepot(entry: DoseEntry) -> Bool {
        if entry.releaseForm == "DEP" { return true }
        guard entry.route == .intramuscular || entry.route == .subcutaneous else { return false }
        let uid = entry.substanceUID ?? SubstanceStore.shared.substanceUID(forNameOrAlias: entry.substance)
        return SubstanceStore.shared.isEster(entry.saltForm, forParentUID: uid)
    }

    /// The depot terminal half-life (minutes) for a depot dose, or `nil` when the
    /// dose is not a depot. An injectable ester derives it from its `ester_pk`
    /// terminal release rate (`ln2 / k1`, the flip-flop terminal slope — ~3 d for
    /// valerate, ~8 d for cypionate); a catalog-only ester (undecylate, no curve)
    /// or a non-ester depot falls back to ``defaultDepotHalfLifeDays``.
    static func depotHalfLifeMinutes(entry: DoseEntry) -> Double? {
        guard isDepot(entry: entry) else { return nil }
        if let uid = entry.substanceUID ?? SubstanceStore.shared.substanceUID(forNameOrAlias: entry.substance),
           let label = entry.saltForm,
           let k1 = SubstanceStore.shared.esters(forParentUID: uid).first(where: { $0.label == label })?.parameters?.k1,
           k1 > 0 {
            return log(2) / k1 * 24 * 60 // days → minutes
        }
        return defaultDepotHalfLifeDays * 24 * 60
    }

    /// Derive `(ke, ka)` from a half-life and an optional acute duration profile.
    /// `ka` is fitted to the profile's time-to-peak (onset + come-up midpoints)
    /// when that is positive, otherwise it falls back to ``PKModel/defaultKa(ke:)``.
    static func rateConstants(halfLifeMinutes: Double, duration: DurationProfile?) -> (ke: Double, ka: Double) {
        let ke = PKModel.ke(fromHalfLifeMinutes: halfLifeMinutes)
        guard let duration else { return (ke, PKModel.defaultKa(ke: ke)) }
        let timeToPeak = (duration.onset?.midpoint ?? 0) + (duration.comeup?.midpoint ?? 0)
        let ka = timeToPeak > 0 ? PKModel.estimateKa(timeToPeak: timeToPeak, ke: ke) : PKModel.defaultKa(ke: ke)
        return (ke, ka)
    }

    /// Full resolution from a caller-resolved duration. `duration` is whichever
    /// acute profile the caller already picks — a per-product envelope, a
    /// route/salt/isomer-specific profile, or `nil`. `nil` result when no
    /// half-life can be resolved.
    static func params(substance: Substance?, entryName: String, duration: DurationProfile?) -> Params? {
        guard let halfLife = halfLifeMinutes(substance: substance, entryName: entryName) else { return nil }
        let (ke, ka) = rateConstants(halfLifeMinutes: halfLife, duration: duration)
        return Params(halfLifeMinutes: halfLife, ke: ke, ka: ka)
    }

    /// Full resolution that also resolves the route's acute profile off the
    /// substance model (no product envelope) — the convenience the single-dose
    /// PK tools use.
    static func params(substance: Substance?, entryName: String, route: RouteOfAdministration) -> Params? {
        params(substance: substance, entryName: entryName, duration: substance?.resolveDuration(for: route))
    }
}
