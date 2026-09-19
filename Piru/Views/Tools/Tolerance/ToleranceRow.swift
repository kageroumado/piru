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

    /// Minimum severity for a non-safety class to earn a card — the rested / mild bucket
    /// boundary (``ToleranceBucket``: rested at responseFraction ≥ 0.90 ⇒ severity ≤ 0.10). Below it a
    /// card would render for a level the gauge draws as empty, which is noise — it's how a drug with only trace activity at the class's target (e.g.
    /// amphetamine's weak SERT release) slipped into the chart. Safety-critical classes bypass it.
    static let minimumCardSeverity = 0.10

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
            guard shift > 0 else { return nil }
            return ToleranceBand(id: index, label: label, widthFraction: severity * shift / totalShift, color: color)
        }
    }

    // MARK: - Recovery curve / windows

    /// Forward-decay the engaged layers over `[0, window]` and convert each `S(t)` to a **tolerance
    /// percentage** — the curve starts at the **current** tolerance (t = 0) and *descends* toward 0 as
    /// the layers relax, matching the bar's orientation (full = strong tolerance). Uses the same
    /// saturating ``PDModel/responseFraction`` with the class's mechanism-aware cap (§5 — ½ for
    /// release/reuptake proxies, uncapped for agonists) as the gauge, so the graph and the bar can never
    /// disagree. Shared by the per-card chart and the combined chart, so the sampling math lives in
    /// exactly one place.
    func recoveryCurve(overMinutes window: Double, sampleCount: Int = 24) -> [ToleranceChartPoint] {
        let span = max(window, 1)
        return (0 ..< sampleCount).map { index in
            let minutes = span * Double(index) / Double(sampleCount - 1)
            let shift = exp(
                snapshot.sAcute * exp(-minutes / params.tauAcuteMinutes)
                    + snapshot.sAdaptive * exp(-minutes / params.tauAdaptiveMinutes)
                    + snapshot.sDeep * exp(-minutes / params.tauDeepMinutes)
                    + snapshot.sSynthesis * exp(-minutes / params.tauSynthesisMinutes),
            )
            let tolerance = 1 - PDModel.responseFraction(
                shiftFactor: shift, representativeOccupancy: snapshot.representativeOccupancy,
                occupancyCap: snapshot.receptorClass.gaugeOccupancyCap,
            )
            return ToleranceChartPoint(id: index, day: minutes / 1_440, percent: max(0, min(100, tolerance * 100)))
        }
    }

    /// Linear day ticks across this row's recovery window — `now` at the origin, four evenly-spaced
    /// gridlines to the window edge.
    var xAxisDays: [Double] {
        let windowDays = recoveryWindowMinutes / 1_440
        return [0, windowDays * 0.25, windowDays * 0.5, windowDays * 0.75, windowDays]
    }

    /// Recovery window `W` (minutes) for the chart's X axis — time for tolerance to fade to ~5% if
    /// dosing stops now, capped at 180 days so the deep months-scale tail stays readable.
    var recoveryWindowMinutes: Double {
        let minutes = recoveryMinutes(toTolerance: 0.05) ?? 0
        return min(max(minutes, 0), 180 * 1_440)
    }

    /// Minutes for **tolerance** to decay to `target` (∈ [0,1]) if dosing stops now. Tolerance is
    /// `1 − responseFraction`, so the target response fraction is `1 − target`; inverting the saturating
    /// gauge (with the class's mechanism-aware cap, exactly as ``PDModel/responseFraction``) gives the
    /// shift `S` at which that response is reached, then all four layers decay on their own time-constants
    /// to it. The cap must match the curve/bar or the axis span and the plotted line would disagree.
    func recoveryMinutes(toTolerance target: Double, shiftScale: Double = 1) -> Double? {
        // The cap must stay strictly below 1: occupancy == 1 makes the ratio
        // divide by zero and floods the axis math with infinity.
        let cap = min(snapshot.receptorClass.gaugeOccupancyCap ?? 0.999_999, 0.999_999)
        let occupancy = min(cap, max(0, snapshot.representativeOccupancy))
        let ratio = occupancy / (1 - occupancy)
        let responseTarget = max(0.000_001, 1 - target)
        let targetShift = max(1, (ratio + 1) / responseTarget - ratio)
        let layers = [
            (s: snapshot.sAcute * shiftScale, tau: params.tauAcuteMinutes),
            (s: snapshot.sAdaptive * shiftScale, tau: params.tauAdaptiveMinutes),
            (s: snapshot.sDeep * shiftScale, tau: params.tauDeepMinutes),
            (s: snapshot.sSynthesis * shiftScale, tau: params.tauSynthesisMinutes),
        ]
        return PDModel.shiftDecayMinutes(layers: layers, toShift: targetShift)
    }

    // MARK: - Safety notes

    /// The trimmed one-sentence safety notes for this class, gated by tier where the note is Pharma-Nerd
    /// depth. Reset-overdose warnings need tolerance to lose; dependence warnings
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
                add("After a break or in a new setting, tolerance drops — a dose that felt fine before can stop your breathing.")
            }
        case .dependenceKindling:
            if snapshot.chronicExposure > 0.10 {
                add("Regular use over weeks builds physical dependence — stopping abruptly can be dangerous even if you don't feel tolerant.")
            }
        case .alpha2Rebound:
            add("Stopping an α₂-agonist abruptly after regular use can make blood pressure rebound.")
        case .betaRebound:
            add("Stopping a beta-blocker abruptly after regular use can make heart rate and blood pressure rebound.")
        default:
            break
        }

        if snapshot.safetyEndpointKind == .cognitiveImpairment, hasTolerance {
            add("Feeling less sedated does not establish that memory or coordination are unimpaired — tolerance to sedation builds faster than tolerance to impairment.")
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

/// The mechanism class's name at the given disclosure tier (casual → curious → Pharma Nerd).
func toleranceClassName(
    _ receptorClass: ReceptorClasses.ReceptorClass,
    tier: UserProfile,
) -> LocalizedStringResource {
    switch tier {
    case .casual: receptorClass.casualName
    case .harmReduction: receptorClass.displayName
    case .pharmaNerd: receptorClass.scientificName
    }
}

/// A compact X-axis tick label. Ticks sit at 0·W … 1·W in quarter-window steps, so a coarse
/// (whole-hour / whole-day) unit collides on adjacent ticks for short windows — the "1h · 2h · 2h" bug.
/// Each magnitude drops to the next-finer unit (minutes < 2 h, hours < 4 d, days < 4 wk) so neighboring
/// ticks always round apart.
func axisDayLabel(days: Double) -> String {
    let value = max(0, days)
    if value <= 0 { return String(localized: "now") }
    let hours = value * 24
    if hours < 2 {
        let mins = max(5, Int((hours * 60 / 5).rounded()) * 5)
        return String(localized: "\(mins)m")
    }
    if value < 4 { return String(localized: "\(Int(hours.rounded()))h") }
    if value < 28 { return String(localized: "\(Int(value.rounded()))d") }
    if value < 120 { return String(localized: "\(Int((value / 7).rounded()))wk") }
    return String(localized: "\(Int((value / 30).rounded()))mo")
}

/// "A, B and C" style join for the incomplete-data list.
func toleranceListPhrase(_ names: [String]) -> String {
    ListFormatter.localizedString(byJoining: names)
}
