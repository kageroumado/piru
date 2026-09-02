import Foundation
import Observation

/// The `(ke, ka)` pair a PK curve is drawn from, named so it can cross a view
/// boundary as a single `Equatable` input.
struct PKRateConstants: Equatable {
    let ke: Double
    let ka: Double
}

/// The single-dose pharmacokinetics behind ``HalfLifeCalculatorView``.
///
/// Every equation is ``PKModel``'s and every half-life resolution is
/// ``PKResolver``'s; this enum only decides which inputs reach them — the typed
/// half-life override, the `(ke, ka)` pair for the picked route, and the
/// milestone ladder the screen labels.
enum HalfLifeCalculation {
    /// One `1/2ⁿ` step of the elimination ladder.
    struct Milestone: Identifiable, Equatable {
        /// `n` — how many half-lives in.
        let id: Int
        /// Fraction of the dose still present, `1/2ⁿ`.
        let fraction: Double
        /// Minutes since the dose.
        let minutes: Double
    }

    /// The half-life the screen models with, in minutes: the typed override when
    /// the toggle is on, otherwise whatever the substance record knows. `nil`
    /// when neither answers, which every caller must keep handling.
    static func effectiveHalfLife(
        useCustom: Bool,
        customHours: Double?,
        substance: Substance?,
        entryName: String,
    ) -> Double? {
        if useCustom {
            guard let hours = customHours, hours > 0 else { return nil }
            return hours * 60
        }
        return PKResolver.halfLifeMinutes(substance: substance, entryName: entryName)
    }

    /// `(ke, ka)` fitted to the route's acute profile. `nil` when no positive
    /// half-life resolves.
    static func rateConstants(
        halfLifeMinutes: Double?,
        substance: Substance?,
        route: RouteOfAdministration,
    ) -> PKRateConstants? {
        guard let halfLife = halfLifeMinutes, halfLife > 0 else { return nil }
        let params = PKResolver.rateConstants(
            halfLifeMinutes: halfLife,
            duration: substance?.resolveDuration(for: route),
        )
        return PKRateConstants(ke: params.ke, ka: params.ka)
    }

    /// Time of peak concentration (Tmax) in minutes; `0` when the rate constants
    /// are unknown.
    static func peakTime(rateConstants: PKRateConstants?) -> Double {
        rateConstants.map { PKModel.tmax(ke: $0.ke, ka: $0.ka) } ?? 0
    }

    /// Amount still in the body — absorption site plus central compartment — at
    /// `elapsedMinutes`. Falls back to plain exponential decay when only a
    /// half-life is known.
    static func remainingAmount(
        dose: Double,
        elapsedMinutes: Double,
        halfLifeMinutes: Double,
        rateConstants: PKRateConstants?,
    ) -> Double {
        let elapsed = max(0, elapsedMinutes)
        if let params = rateConstants {
            return dose * PKModel.fractionRemainingInBody(at: elapsed, ke: params.ke, ka: params.ka)
        }
        return dose * pow(0.5, elapsed / halfLifeMinutes)
    }

    /// The first four `1/2ⁿ` steps, timed against the fitted curve when one
    /// exists and against the bare half-life otherwise.
    static func milestones(halfLifeMinutes: Double, rateConstants: PKRateConstants?) -> [Milestone] {
        (1 ... 4).map { n in
            let fraction = pow(0.5, Double(n))
            let minutes: Double = if let params = rateConstants {
                PKModel.timeToFraction(fraction, ke: params.ke, ka: params.ka, maxMinutes: halfLifeMinutes * 8)
            } else {
                halfLifeMinutes * Double(n)
            }
            return Milestone(id: n, fraction: fraction, minutes: minutes)
        }
    }
}

/// The inputs ``HalfLifeCalculatorView`` collects, plus the PK values derived
/// from them.
///
/// The screen's only mutable state: every field the user can type, pick, or
/// toggle lives here so a change re-evaluates the sections that read it rather
/// than the whole screen, and the derived values resolve through
/// ``HalfLifeCalculation`` instead of being recomputed inline in a `body`.
@Observable
@MainActor
final class HalfLifeCalculatorModel {
    var substanceName = ""
    var selectedSubstance: Substance?
    var doseAmount: Double? = 100
    var doseUnit: String = "mg"
    var timeTaken: Date = .now
    var useCustomHalfLife = false
    var customHalfLifeHours: Double?
    var selectedRoute: RouteOfAdministration = .oral

    /// How many substances in the library carry a half-life, for the header.
    private(set) var halfLifeCount = 0

    var dose: Double {
        doseAmount ?? 0
    }

    var effectiveHalfLife: Double? {
        HalfLifeCalculation.effectiveHalfLife(
            useCustom: useCustomHalfLife,
            customHours: customHalfLifeHours,
            substance: selectedSubstance,
            entryName: substanceName,
        )
    }

    var rateConstants: PKRateConstants? {
        HalfLifeCalculation.rateConstants(
            halfLifeMinutes: effectiveHalfLife,
            substance: selectedSubstance,
            route: selectedRoute,
        )
    }

    /// A substance is picked, its record knows no half-life, and the user has
    /// not typed one — the only state the no-data card answers.
    var isMissingHalfLife: Bool {
        selectedSubstance != nil && !useCustomHalfLife && selectedSubstance?.halfLifeMinutes == nil
    }

    /// Amount left now, in the dose's own units.
    func remainingAmount(at date: Date = .now) -> Double {
        guard let halfLife = effectiveHalfLife else { return 0 }
        return HalfLifeCalculation.remainingAmount(
            dose: dose,
            elapsedMinutes: date.timeIntervalSince(timeTaken) / 60,
            halfLifeMinutes: halfLife,
            rateConstants: rateConstants,
        )
    }

    /// Adopt a substance picked from search, along with the unit and route it
    /// is normally taken by.
    func select(_ substance: Substance) {
        selectedSubstance = substance
        substanceName = substance.name
        doseUnit = substance.defaultUnit
        selectedRoute = substance.defaultRoute
    }

    func loadHalfLifeCount() async {
        await SubstanceStore.shared.ensureAllLoaded()
        halfLifeCount = SubstanceLibrary.all.count(where: { $0.halfLifeMinutes != nil })
    }
}
