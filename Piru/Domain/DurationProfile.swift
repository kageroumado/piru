import Foundation

struct DurationRange: Codable, Hashable {
    let min: Double
    let max: Double

    var midpoint: Double {
        (min + max) / 2
    }

    /// A single figure with no stated interval. Its source gave one number
    /// (substance.wiki's curve-derived phases are all like this), so every
    /// surface prints it as approximate — "≈30 minutes" — never as a measured
    /// "29.5". It is still a real duration: the effect curve draws from it.
    var isPoint: Bool {
        max <= min
    }

    /// "30 – 60 minutes", "2 – 6 hours"; one figure — a point, or a range too
    /// narrow to survive rounding — reads "≈30 minutes". The "≈" mark means
    /// exactly that: a single, approximate figure. A range needs no mark; its
    /// two bounds already say it varies.
    var displayString: String {
        if max >= 120 {
            let minH = Self.roundHours(min / 60)
            let maxH = Self.roundHours(max / 60)
            if isPoint || minH == maxH {
                return String(localized: "≈\(Self.fmtHours(maxH)) hours")
            }
            return String(localized: "\(Self.fmtHours(minH)) – \(Self.fmtHours(maxH)) hours")
        }
        let minR = Int(min.rounded())
        let maxR = Int(max.rounded())
        if isPoint || minR == maxR {
            return String(localized: "≈\(maxR) minutes")
        }
        return String(localized: "\(minR) – \(maxR) minutes")
    }

    /// The compact form for tight cells: "30–45m", "1.5–2.5h", "≈30m" for a
    /// single figure. One unit for the whole range: a range that reaches into
    /// hours renders both bounds in hours, so a straddling total reads "1–4h"
    /// rather than a mixed "60m–4h".
    var compactString: String {
        let usesHours = max >= 120
        func part(_ minutes: Double) -> String {
            guard usesHours else { return "\(Int(minutes.rounded()))" }
            return Self.fmtHours(Self.roundHours(minutes / 60))
        }
        let unit = usesHours ? "h" : "m"
        let lo = part(min), hi = part(max)
        return isPoint || lo == hi ? "≈\(hi)\(unit)" : "\(lo)–\(hi)\(unit)"
    }

    /// Rounds hours to the nearest 0.5
    private static func roundHours(_ v: Double) -> Double {
        (v * 2).rounded() / 2
    }

    private static func fmtHours(_ v: Double) -> String {
        v == v.rounded(.toNearestOrEven) ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }
}

struct DurationProfile: Codable, Hashable {
    let onset: DurationRange?
    let comeup: DurationRange?
    let peak: DurationRange?
    let offset: DurationRange?
    let afterglow: DurationRange?
    let total: DurationRange?

    var estimatedTotalMinutes: Double {
        // The offset phase boundary — where the acute curve has fully fallen — is
        // the floor. A `total` field shorter than the phases that precede it is
        // incoherent source data (e.g. kratom oral: total 120–240 while the offset
        // phase alone ends at ~390); trusting it verbatim reports the dose "over"
        // while its curve is still visibly descending, desyncing the entry-row
        // rail / now-line / active fade — all gated on this value — from what the
        // graph draws (which follows the phase boundaries, not `total`).
        let phaseEnd = phaseBoundaries.offsetEnd
        if let total { return max(total.midpoint, phaseEnd) }
        return phaseEnd
    }

    var phaseBoundaries: PhaseBoundaries {
        let onsetEnd = onset?.midpoint ?? 0
        let comeupEnd = onsetEnd + (comeup?.midpoint ?? 0)
        let peakEnd = comeupEnd + (peak?.midpoint ?? 0)
        let offsetEnd = peakEnd + (offset?.midpoint ?? 0)
        let afterglowEnd = offsetEnd + (afterglow?.midpoint ?? 0)
        return PhaseBoundaries(
            onsetEnd: onsetEnd,
            comeupEnd: comeupEnd,
            peakEnd: peakEnd,
            offsetEnd: offsetEnd,
            afterglowEnd: afterglowEnd,
        )
    }

    /// The same profile with its onset `minutes` later. The delay is a lag: the dose
    /// sits in the stomach before any of it absorbs, so it lengthens the onset and
    /// leaves every later phase as long as it was. `total` grows by the same amount
    /// so the dose is not reported over while its shifted curve is still up.
    func delayingOnset(by minutes: Double) -> DurationProfile {
        guard minutes > 0 else { return self }
        func shifted(_ range: DurationRange) -> DurationRange {
            DurationRange(min: range.min + minutes, max: range.max + minutes)
        }
        return DurationProfile(
            onset: shifted(onset ?? DurationRange(min: 0, max: 0)),
            comeup: comeup,
            peak: peak,
            offset: offset,
            afterglow: afterglow,
            total: total.map(shifted),
        )
    }

    /// Fill in missing come-up/peak/offset phases when the data carries a real
    /// `total` but not the intermediate phases that shape the curve between
    /// onset and total (endpoint-only data from a single source). Without this,
    /// ``phaseBoundaries`` sums only the present phases and collapses the curve
    /// to roughly the onset length — discarding the stated duration (a ~12 h LSD
    /// trip rendered as a ~1 h spike). The real `total` is left intact; only the
    /// *unexplained* span (`total − present phases`) is distributed across the
    /// missing shapers using class-aware proportions
    /// (``SubstanceCategory/synthesizedPhaseShape``), so any genuine phase is
    /// preserved. Returns `self` for complete profiles and those with no `total`
    /// (the latter keep the half-life synthesis fallback).
    ///
    /// Applied wherever a **curve is drawn** — the journal timeline and the detail
    /// card alike. (It used to be journal-only, which is why the same dose drew two
    /// different shapes depending on the screen.) The detail card's numeric trio
    /// and phase disclosure still read the *raw* profile: those are a reference
    /// table and must stay verbatim source data.
    func fillingMissingPhases(for category: SubstanceCategory) -> DurationProfile {
        guard let total, total.midpoint > 0 else { return self }
        let shape = category.synthesizedPhaseShape
        let totalMin = total.midpoint
        let onsetMin = onset?.midpoint ?? totalMin * shape.onset
        let presentMiddle = (comeup?.midpoint ?? 0) + (peak?.midpoint ?? 0) + (offset?.midpoint ?? 0)
        let budget = totalMin - onsetMin - presentMiddle

        // A complete profile leaves ~no unexplained span; bail so it's untouched.
        // Likewise bail if every shaper is already present.
        let needsComeup = comeup == nil, needsPeak = peak == nil, needsOffset = offset == nil
        guard budget > totalMin * 0.1, needsComeup || needsPeak || needsOffset else { return self }

        let wComeup = needsComeup ? shape.comeup : 0
        let wPeak = needsPeak ? shape.peak : 0
        let wOffset = needsOffset ? shape.offset : 0
        let wSum = wComeup + wPeak + wOffset
        guard wSum > 0 else { return self }

        func filled(_ weight: Double) -> DurationRange? {
            guard weight > 0 else { return nil }
            let v = budget * weight / wSum
            return DurationRange(min: v, max: v)
        }
        return DurationProfile(
            onset: onset ?? DurationRange(min: onsetMin, max: onsetMin),
            comeup: comeup ?? filled(wComeup),
            peak: peak ?? filled(wPeak),
            offset: offset ?? filled(wOffset),
            afterglow: afterglow,
            total: total,
        )
    }
}

extension DurationProfile {
    /// Reconstruct a duration profile from phase boundaries stored in an ActiveSubstanceState.
    init(fromState state: ActiveSubstanceState) {
        let onsetLen = state.onsetEndMinutes
        let comeupLen = state.comeupEndMinutes - state.onsetEndMinutes
        let peakLen = state.peakEndMinutes - state.comeupEndMinutes
        let offsetLen = state.offsetEndMinutes - state.peakEndMinutes
        let afterglowLen: Double? = state.afterglowEndMinutes.map { $0 - state.offsetEndMinutes }

        self.init(
            onset: onsetLen > 0 ? DurationRange(min: onsetLen, max: onsetLen) : nil,
            comeup: comeupLen > 0 ? DurationRange(min: comeupLen, max: comeupLen) : nil,
            peak: peakLen > 0 ? DurationRange(min: peakLen, max: peakLen) : nil,
            offset: offsetLen > 0 ? DurationRange(min: offsetLen, max: offsetLen) : nil,
            afterglow: afterglowLen.flatMap { $0 > 0 ? DurationRange(min: $0, max: $0) : nil },
            total: DurationRange(min: state.totalMinutes, max: state.totalMinutes),
        )
    }
}

struct PhaseBoundaries {
    let onsetEnd: Double
    let comeupEnd: Double
    let peakEnd: Double
    let offsetEnd: Double
    let afterglowEnd: Double
}
