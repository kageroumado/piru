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

    /// Minimum severity for a non-safety class to earn a card — the "No tolerance" / "Mild" bucket
    /// boundary (``ToleranceBucket``: rested at responseFraction ≥ 0.90 ⇒ severity ≤ 0.10). Below it a
    /// card would render while labeling itself "No tolerance" and quoting a "fades in under an hour"
    /// recovery, which is noise — it's how a drug with only trace activity at the class's target (e.g.
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
            ("Tachyphylaxis", snapshot.sAcute, family.opacity(0.5)),
            ("Tolerance", snapshot.sAdaptive + snapshot.sSynthesis, family.opacity(0.82)),
            ("Deep", snapshot.sDeep, family),
        ]
        return raw.enumerated().compactMap { index, band in
            let (label, shift, color) = band
            guard shift > 0 else { return nil }
            return ToleranceBand(id: index, label: label, widthFraction: severity * shift / totalShift, color: color)
        }
    }

    // MARK: - Lede

    /// The card's one-line summary — **only** when it adds something the gauge doesn't already show.
    /// The plain level (mild / high / …) is read off the gauge, so a generic "Mild tolerance — your
    /// usual dose does a little less" would just restate it; those return `nil`. MDMA-type synthesis
    /// and the adrenergic rebound hosts carry real extra information, so they keep a line.
    var lede: LocalizedStringResource? {
        switch snapshot.receptorClass {
        case .alpha2Agonist, .betaBlocker:
            "Little tolerance builds — the thing to watch is stopping suddenly."
        case .serotonergicReleaser where snapshot.sSynthesis > 0.05:
            "Suppresses the enzyme that makes serotonin, so recovery takes weeks."
        default:
            nil
        }
    }

    // MARK: - Recovery curve / windows

    /// Forward-decay the engaged layers over `[0, window]` and convert each `S(t)` to a **tolerance
    /// percentage** — the curve starts at the **current** tolerance (t = 0) and *descends* toward 0 as
    /// the layers relax, matching the bar's orientation (full = strong tolerance). Uses the same
    /// saturating ``PDModel/responseFraction`` with the class's mechanism-aware cap (§5 — ½ for
    /// release/reuptake proxies, uncapped for agonists) as the gauge, so the graph and the bar can never
    /// disagree — the old inline `0.999_999` clamp pinned high-occupancy stimulants at a flat 100%
    /// "sensitivity", reading as *no* tolerance while the bar showed moderate. Shared by the per-card
    /// chart and the combined chart, so the sampling math lives in exactly one place.
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

    var chartCaption: LocalizedStringResource {
        let minutes = max(recoveryMinutes(toTolerance: 0.10) ?? 0, 0)
        let phrase = durationPhrase(minutes: minutes)
        if snapshot.sDeep > 0.05 {
            return "Most of it fades in \(phrase) if you stop now — the deep part takes months."
        }
        return "Most of it fades in \(phrase) if you stop now."
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
    func recoveryMinutes(toTolerance target: Double) -> Double? {
        // Match the gauge's mechanism-aware cap (§5): capped at ½ for release/reuptake proxies, uncapped
        // (just shy of 1 to avoid a divide-by-zero) for agonists — so the axis span never disagrees with
        // the plotted line or the bar.
        let cap = snapshot.receptorClass.gaugeOccupancyCap ?? 0.999_999
        let occupancy = min(cap, max(0, snapshot.representativeOccupancy))
        let ratio = occupancy / (1 - occupancy)
        let responseTarget = max(0.000_001, 1 - target)
        let targetShift = max(1, (ratio + 1) / responseTarget - ratio)
        let layers = [
            (s: snapshot.sAcute, tau: params.tauAcuteMinutes),
            (s: snapshot.sAdaptive, tau: params.tauAdaptiveMinutes),
            (s: snapshot.sDeep, tau: params.tauDeepMinutes),
            (s: snapshot.sSynthesis, tau: params.tauSynthesisMinutes),
        ]
        return PDModel.shiftDecayMinutes(layers: layers, toShift: targetShift)
    }

    // MARK: - Safety notes

    /// The trimmed one-sentence safety notes for this class, gated by tier where the note is Pharma-Nerd
    /// depth. Reset-overdose warnings need tolerance to lose; dependence warnings
    /// key on chronicity (duration of regular use), not tolerance magnitude —
    /// therapeutic-dose dependence develops without measurable tolerance (NAV26 §5.6).
    /// Adrenergic rebound always shows (it's the whole point of those faint-tolerance cards).
    func safetyNotes(tier: UserProfile) -> [ToleranceSafetyNote] {
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
                add("After a break, tolerance drops fast — a dose that felt fine before can stop your breathing. Restart low.")
            }
        case .dependenceKindling:
            if snapshot.chronicExposure > 0.10 {
                add("Regular use over weeks builds physical dependence — stopping abruptly can be dangerous even if you don't feel tolerant. Taper gradually.")
            }
        case .alpha2Rebound:
            add("Don't stop α₂-agonists cold after regular use — blood pressure can rebound. Taper.")
        case .betaRebound:
            add("Don't stop beta-blockers cold after regular use — heart rate and blood pressure can rebound. Taper.")
        default:
            break
        }

        // §6: stimulant cardiovascular is two mechanisms. Lead with the in-session hazard (safety-critical,
        // always) — the acute pressor doesn't tolerize, so chasing a faded high stacks fresh spikes. The
        // chronic line is calm and shows only once the chronic (adaptive) endpoint is actually engaged, so
        // it never implies dangerous cumulative load for a light/therapeutic user.
        if snapshot.safetyEndpointKind == .cardiovascular {
            add("Within a session the high fades faster than the strain on your heart — chasing it with more stacks onto a blood-pressure spike that hasn't eased. Space your doses.")
            if let cardiovascular = snapshot.safetyShiftFactor, cardiovascular > 1.05 {
                add(
                    "With regular use, your resting heart rate and blood pressure tend to settle over weeks.",
                    tint: Theme.secondaryLabel, image: "clock.arrow.circlepath",
                )
            }
        }

        if tier != .casual, snapshot.sDeep > 0.05 {
            add(
                "Heavy chronic use has shifted your baseline; the deepest part recovers over months.",
                tint: Theme.secondaryLabel, image: "clock.arrow.circlepath",
            )
        }

        return notes
    }

    // MARK: - Pharma Nerd footer

    var confidenceAndShift: LocalizedStringResource {
        let shift = String(format: "%.1f", snapshot.shiftFactor)
        return "\(String(localized: snapshot.confidence.label)) · S ≈ \(shift)×"
    }

    var engagedLayers: LocalizedStringResource {
        var names: [String] = []
        if snapshot.sAcute > 0.01 { names.append(String(localized: "acute")) }
        if snapshot.sAdaptive > 0.01 { names.append(String(localized: "adaptive")) }
        if snapshot.sDeep > 0.01 { names.append(String(localized: "deep")) }
        if snapshot.sSynthesis > 0.01 { names.append(String(localized: "synthesis")) }
        let joined = names.isEmpty ? String(localized: "none") : ListFormatter.localizedString(byJoining: names)
        return "Engaged layers: \(joined)"
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

/// Five tolerance buckets keyed on the response fraction — drives the capsule word and the note gating.
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

    /// The tolerance level in words — used both as the gauge's capsule/legend word and as its VoiceOver
    /// label so screen-reader users get the level without reading five bars.
    var word: LocalizedStringResource {
        switch self {
        case .rested: "No tolerance"
        case .mild: "Mild tolerance"
        case .moderate: "Moderate tolerance"
        case .high: "High tolerance"
        case .veryHigh: "Very high tolerance"
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

func durationPhrase(minutes: Double) -> String {
    let hours = minutes / 60
    let days = hours / 24
    if days >= 60 { return String(localized: "~\(Int((days / 30).rounded())) months") }
    if days >= 14 { return String(localized: "~\(Int((days / 7).rounded())) weeks") }
    if days >= 1.5 { return String(localized: "~\(Int(days.rounded())) days") }
    if hours >= 1 { return String(localized: "~\(Int(hours.rounded())) hours") }
    return String(localized: "under an hour")
}

/// A compact X-axis tick label. Ticks sit at 0·W … 1·W in quarter-window steps, so a coarse
/// (whole-hour / whole-day) unit collides on adjacent ticks for short windows — the "1h · 2h · 2h" bug.
/// Each magnitude drops to the next-finer unit (minutes < 2 h, hours < 4 d, days < 4 wk) so neighboring
/// ticks always round apart; the load-bearing recovery copy is the caption below the chart.
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
