import Foundation
import SwiftUI

/// One mechanism class's tolerance snapshot paired with its ``ReceptorClasses/Parameters``, plus the
/// pure per-row derivations the cards and charts read (bands, recovery curve, ledes, safety notes). All
/// math here is a pure function of the snapshot + parameters, so the card/chart views stay thin.
struct ToleranceRow: Identifiable {
    let snapshot: ClassTolerance
    let params: ReceptorClasses.Parameters

    var id: ReceptorClasses.ReceptorClass {
        snapshot.receptorClass
    }

    /// The level at or under which a class reads **near baseline**: the rested / mild boundary of
    /// ``ToleranceBucket`` (rested at responseFraction ≥ 0.90 ⇒ severity ≤ 0.10). It is the line the
    /// charts draw, the point the "near baseline" date names, and the floor for a card.
    static let nearBaselineSeverity = 0.10

    /// Minimum severity for a class to earn a card on its level alone. Below it a card would render for
    /// a level the gauge draws as empty, which is noise: a drug with only trace activity at the class's
    /// target (amphetamine's weak SERT release) would otherwise bring its own card and chart line.
    static let minimumCardSeverity = nearBaselineSeverity

    /// Lowest level the near-baseline list names: one that prints as at least 1%.
    static let minimumListedSeverity = 0.005

    /// A class earns a card when its level is above near baseline, or when it is safety-critical and has
    /// a note to carry (the adrenergic rebound hosts, a chronically used GABAergic), so a
    /// discontinuation warning always has a card to sit on.
    var earnsCard: Bool {
        snapshot.severity > Self.minimumCardSeverity || (isSafetyCritical && !safetyNotes().isEmpty)
    }

    /// Classes pinned to the top of the flat list — the reset-overdose, dependence-kindling, and
    /// adrenergic discontinuation-rebound hosts. They lead regardless of how faint the right-shift is.
    var isSafetyCritical: Bool {
        switch params.safetyAxis {
        case .resetOverdose, .dependenceKindling, .alpha2Rebound, .betaRebound: true
        default: false
        }
    }

    /// The card's identity color for this mechanism family.
    var familyColor: Color {
        snapshot.receptorClass.familyColor
    }

    // MARK: - Tolerance bar bands

    /// Decompose a class's tolerance into up to three timescale bands — **tachyphylaxis** (the acute
    /// same-session/same-day pool), **tolerance** (the days-scale adaptive baseline shift, plus the
    /// slow serotonin-synthesis pool for entactogens), and **deep** (months-scale entrenchment) —
    /// ordered fast → slow. Each band's width is the overall severity apportioned by its share of the
    /// summed ln-shift `ln S = Σ sₗ` (the additive latent behind the saturating gauge), so a faint
    /// contributor draws a faint sliver and the whole bar reads as the overall tolerance.
    var bands: [ToleranceBand] {
        let totalShift = snapshot.sAcute + snapshot.sAdaptive + snapshot.sDeep + snapshot.sSynthesis
        guard totalShift > 0 else { return [] }
        let severity = max(0, min(1, snapshot.severity))
        let family = familyColor
        let raw: [(LocalizedStringResource, Double, Color)] = [
            ("Tachyphylaxis", snapshot.sAcute, family.opacity(Theme.Opacity.dimmed)),
            ("Tolerance", snapshot.sAdaptive + snapshot.sSynthesis, family.opacity(0.82)),
            ("Deep", snapshot.sDeep, family),
        ]
        return raw.enumerated().compactMap { index, band in
            let (label, shift, color) = band
            let width = severity * shift / totalShift
            guard width >= Self.minimumBandWidth else { return nil }
            return ToleranceBand(id: index, label: label, widthFraction: width, color: color)
        }
    }

    /// Narrowest band the bar draws and its legend names, as a share of the track: about 3 pt at phone
    /// width, the least a reader can see.
    static let minimumBandWidth = 0.01

    // MARK: - Recovery curve / windows

    /// The class's tolerance `minutes` from now with no further dosing, as a percentage: every layer
    /// decays on its own time constant and the shift is read through the same saturating
    /// ``PDModel/responseFraction`` and mechanism-aware cap as the gauge, so a curve, a readout and the
    /// bar can never disagree.
    func tolerancePercent(afterMinutes minutes: Double) -> Double {
        let shift = ToleranceRecovery.shiftFactor(layers: recoveryLayers(), afterMinutes: max(0, minutes))
        let tolerance = 1 - PDModel.responseFraction(
            shiftFactor: shift, representativeOccupancy: snapshot.representativeOccupancy,
            occupancyCap: snapshot.receptorClass.gaugeOccupancyCap,
        )
        return max(0, min(100, tolerance * 100))
    }

    /// The curve from the **current** tolerance (t = 0) down toward 0 across `[0, window]`. Samples sit
    /// closer together near now, where the acute layer drops within hours, so a weeks-long window still
    /// draws that first fall as a curve.
    func recoveryCurve(overMinutes window: Double, sampleCount: Int = 48) -> [ToleranceChartPoint] {
        let span = max(window, 1)
        return (0 ..< sampleCount).map { index in
            let position = Double(index) / Double(sampleCount - 1)
            let minutes = span * position * position
            return ToleranceChartPoint(id: index, day: minutes / 1_440, percent: tolerancePercent(afterMinutes: minutes))
        }
    }

    /// Time for tolerance to fade to ~5% if dosing stops now, in minutes, capped at 180 days: the span a
    /// chart takes when every plotted class already reads near baseline.
    var fadeMinutes: Double {
        let minutes = recoveryMinutes(toTolerance: 0.05) ?? 0
        return min(max(minutes, 0), 180 * 1_440)
    }

    /// Minutes until the class reads near baseline (``nearBaselineSeverity``) with no further dosing:
    /// `0` when it already does, `nil` when the model places no such point inside its five-year forecast.
    var minutesToNearBaseline: Double? {
        guard let minutes = recoveryMinutes(toTolerance: Self.nearBaselineSeverity),
              minutes < Self.forecastHorizonMinutes else { return nil }
        return minutes
    }

    /// The reach of ``PDModel/shiftDecayMinutes(layers:toShift:)``'s search: five years of minutes.
    private static let forecastHorizonMinutes: Double = 2_628_000

    /// Minutes for **tolerance** to decay to `target` (∈ [0,1]) if dosing stops now. Tolerance is
    /// `1 − responseFraction`, so the target response fraction is `1 − target`; inverting the saturating
    /// gauge (with the class's mechanism-aware cap, exactly as ``PDModel/responseFraction``) gives the
    /// shift `S` at which that response is reached, then all four layers decay on their own time-constants
    /// to it. The cap must match the curve/bar or the axis span and the plotted line would disagree.
    func recoveryMinutes(toTolerance target: Double, shiftScale: Double = 1) -> Double? {
        ToleranceRecovery.minutes(
            toTolerance: target, layers: recoveryLayers(shiftScale: shiftScale),
            occupancy: snapshot.representativeOccupancy,
            occupancyCap: snapshot.receptorClass.gaugeOccupancyCap,
        )
    }

    /// The four recovery layers in fast → slow order, each ln-shift scaled by `shiftScale`.
    private func recoveryLayers(shiftScale: Double = 1) -> [ToleranceRecovery.Layer] {
        [
            (s: snapshot.sAcute * shiftScale, tau: params.tauAcuteMinutes),
            (s: snapshot.sAdaptive * shiftScale, tau: params.tauAdaptiveMinutes),
            (s: snapshot.sDeep * shiftScale, tau: params.tauDeepMinutes),
            (s: snapshot.sSynthesis * shiftScale, tau: params.tauSynthesisMinutes),
        ]
    }

    // MARK: - Safety notes

    /// The trimmed one-sentence safety notes for this class. Reset-overdose warnings need tolerance
    /// to lose; dependence warnings
    /// key on chronicity (duration of regular use), not tolerance magnitude —
    /// therapeutic-dose dependence develops without measurable tolerance (NAV26 §5.6).
    /// Adrenergic rebound always shows (it's the whole point of those faint-tolerance cards).
    func safetyNotes() -> [ToleranceSafetyNote] {
        var notes: [ToleranceSafetyNote] = []

        func add(
            _ text: LocalizedStringResource,
            tint: Color = .orange,
            image: String = "exclamationmark.triangle.fill",
        ) {
            notes.append(ToleranceSafetyNote(id: notes.count, text: text, tint: tint, systemImage: image))
        }

        let hasTolerance = ToleranceBucket(responseFraction: snapshot.responseFraction) != .rested
        switch params.safetyAxis {
        case .resetOverdose:
            if hasTolerance {
                add("After a break or in a new setting, tolerance drops. A dose that felt fine before can stop your breathing.")
            }
        case .dependenceKindling:
            if snapshot.chronicExposure > 0.10 {
                add("Regular use over weeks builds physical dependence. Stopping abruptly can be dangerous even if you don't feel tolerant.")
            }
        case .alpha2Rebound:
            add("Stopping an α₂-agonist abruptly after regular use can make blood pressure rebound.")
        case .betaRebound:
            add("Stopping a beta-blocker abruptly after regular use can make heart rate and blood pressure rebound.")
        default:
            break
        }

        if snapshot.safetyEndpointKind == .cognitiveImpairment, hasTolerance {
            add("Feeling less sedated does not establish that memory or coordination are unimpaired. Tolerance to sedation builds faster than tolerance to impairment.")
        }

        return notes
    }
}

// MARK: - Value types

/// One colored segment of the tolerance bar — a recovery layer's *attributed share* of the overall
/// right-shift. `widthFraction` is already the fraction of the **full track** this band fills (overall
/// severity × the band's ln-shift share), so the segments laid end-to-end fill the bar to the overall
/// tolerance level and split it by where that tolerance comes from.
struct ToleranceBand: Identifiable {
    let id: Int
    let label: LocalizedStringResource
    let widthFraction: Double
    let color: Color
}

/// One sampled point on a tolerance recovery curve: `day` on the X axis, `percent` (0–100) tolerance.
struct ToleranceChartPoint: Identifiable {
    let id: Int
    let day: Double
    let percent: Double
}

/// One trimmed safety note rendered inside a card.
struct ToleranceSafetyNote: Identifiable {
    let id: Int
    let text: LocalizedStringResource
    let tint: Color
    let systemImage: String
}

/// Five tolerance buckets keyed on the response fraction — gates which safety notes show.
enum ToleranceBucket {
    case rested
    case mild
    case moderate
    case high
    case veryHigh

    init(responseFraction: Double) {
        switch responseFraction {
        case 0.90...: self = .rested
        case 0.70 ..< 0.90: self = .mild
        case 0.50 ..< 0.70: self = .moderate
        case 0.30 ..< 0.50: self = .high
        default: self = .veryHigh
        }
    }
}

// MARK: - Tier-aware wording / formatting

/// The mechanism class's name at the given detail level.
func toleranceClassName(
    _ receptorClass: ReceptorClasses.ReceptorClass,
    tier: UserProfile,
) -> LocalizedStringResource {
    switch tier {
    case .casual: receptorClass.casualName
    case .curious: receptorClass.displayName
    }
}

/// A time axis tick: "now" at the origin, then the tick's count in the axis's one unit.
func toleranceTimeTickLabel(_ axis: ToleranceChartScale.TimeAxis, days: Double) -> String {
    let count = axis.count(atDays: days)
    if count <= 0 { return String(localized: "now") }
    switch axis.unit {
    case .hours: return String(localized: "\(count)h")
    case .days: return String(localized: "\(count)d")
    case .weeks: return String(localized: "\(count)wk")
    }
}

/// A modeled level as whole percent ("27%").
func tolerancePercentText(_ percent: Double) -> String {
    (max(0, min(100, percent)) / 100).formatted(.percent.precision(.fractionLength(0)))
}

/// When a class reads near baseline, as a sentence: a date `minutes` from `now`, or "now" at zero.
func toleranceNearBaselineText(minutes: Double, now: Date = .now) -> String {
    guard minutes > 0 else { return String(localized: "Near baseline now") }
    let date = ToleranceBaselineDate.text(
        for: now.addingTimeInterval(minutes * 60),
        precision: ToleranceBaselineDate.precision(minutesAhead: minutes),
    )
    return String(localized: "Near baseline around \(date)")
}

/// "A, B and C" style join for the incomplete-data list.
func toleranceListPhrase(_ names: [String]) -> String {
    ListFormatter.localizedString(byJoining: names)
}

/// The line for a class a scheduled My Meds item projects: where the modeled curve settles on that
/// schedule, or whether it is still rising or falling at the end of the window. States what the model
/// shows, no more.
func toleranceProjectionText(_ outcome: ToleranceStore.ToleranceProjection.Outcome) -> String {
    switch outcome {
    case let .settles(percent, _):
        String(localized: "Settles near \(tolerancePercentText(percent)) on your My Meds schedule")
    case .rising:
        String(localized: "Still rising at the end of the window on your My Meds schedule")
    case .falling:
        String(localized: "Still falling at the end of the window on your My Meds schedule")
    }
}

/// The secondary line under a projected class: where the model reads near baseline with no more doses.
func toleranceNoFurtherText(minutes: Double, now: Date = .now) -> String {
    guard minutes > 0 else { return String(localized: "Near baseline now with no further doses") }
    let date = ToleranceBaselineDate.text(
        for: now.addingTimeInterval(minutes * 60),
        precision: ToleranceBaselineDate.precision(minutesAhead: minutes),
    )
    return String(localized: "With no further doses, near baseline around \(date)")
}
