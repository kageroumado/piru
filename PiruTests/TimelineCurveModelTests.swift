import Foundation
import Testing
@testable import Piru

/// Characterization tests for the extracted timeline curve math. These pin the
/// *current* rendering semantics — the split flat-top effect shape, the
/// `Hill(Σ magnitude·bell)` redose merge, γ-compression, tail scanning, and the
/// lane/tick layout — so the pure functions can't drift silently under the view.
@Suite("TimelineCurveModel")
struct TimelineCurveModelTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    /// A dose with a typical oral profile: 30 min onset, come-up to 60, peak to
    /// 180, offset to 360. Magnitude defaults to 0.7 — inside Hill's
    /// near-linear region, like a single common dose.
    private func dose(
        name: String = "Testine",
        timestamp: Date? = nil,
        amount: Double = 20,
        route: String = "oral",
        onsetEnd: Double = 30,
        comeupEnd: Double = 60,
        peakEnd: Double = 180,
        offsetEnd: Double = 360,
        total: Double = 360,
        magnitude: Double = 0.7,
        tachyphylaxis: Double = 0,
    ) -> ActiveSubstanceState {
        ActiveSubstanceState(
            substanceName: name,
            colorHex: "FF66AA",
            doseTimestamp: timestamp ?? t0,
            amount: amount,
            unit: "mg",
            route: route,
            onsetEndMinutes: onsetEnd,
            comeupEndMinutes: comeupEnd,
            peakEndMinutes: peakEnd,
            offsetEndMinutes: offsetEnd,
            afterglowEndMinutes: nil,
            totalMinutes: total,
            doseIntensity: min(magnitude, 1),
            doseMagnitude: magnitude,
            tachyphylaxis: tachyphylaxis,
        )
    }

    // MARK: - Single-dose curve shape

    @Test
    func `Single-dose curve rises then falls with its peak after the onset`() {
        let s = dose()
        let extent = TimelineCurveModel.curveExtent(for: s)

        var peakValue = -1.0
        var peakTime = 0.0
        for t in stride(from: 0.0, through: extent, by: 1) {
            let v = TimelineCurveModel.intensity(at: t, for: s)
            if v > peakValue {
                peakValue = v
                peakTime = t
            }
        }
        // The crest reaches full strength, lands after the onset window, and
        // the tail has decayed well below it by the draw end.
        #expect(peakValue > 0.99)
        #expect(peakTime > s.onsetEndMinutes)
        #expect(peakTime < s.offsetEndMinutes)
        #expect(TimelineCurveModel.intensity(at: extent, for: s) < peakValue * 0.1)

        // Rising shoulder is monotone non-decreasing up to the crest.
        var previous = -1.0
        for t in stride(from: 0.0, through: 80, by: 10) {
            let v = TimelineCurveModel.intensity(at: t, for: s)
            #expect(v >= previous)
            previous = v
        }
    }

    @Test
    func `Intensity is non-negative and bounded and zero before the dose`() {
        let s = dose()
        let extent = TimelineCurveModel.curveExtent(for: s)
        for t in stride(from: 0.0, through: extent, by: 2) {
            let v = TimelineCurveModel.intensity(at: t, for: s)
            #expect(v >= 0)
            #expect(v <= 1)
        }
        #expect(TimelineCurveModel.intensity(at: -5, for: s) == 0)
    }

    @Test
    func `Descending limb tapers monotonically to near zero at the curve extent`() {
        let s = dose()
        let extent = TimelineCurveModel.curveExtent(for: s)
        // The extent reaches past the stated offset so the tail eases onto the
        // axis instead of being clipped.
        #expect(extent >= s.offsetEndMinutes)

        var previous = Double.greatestFiniteMagnitude
        for t in stride(from: s.peakEndMinutes, through: extent, by: 5) {
            let v = TimelineCurveModel.intensity(at: t, for: s)
            #expect(v <= previous + 1e-12)
            previous = v
        }
        #expect(TimelineCurveModel.intensity(at: extent, for: s) < 0.05)
    }

    @Test
    func `Tachyphylaxis crashes the descending limb but leaves onset and peak untouched`() {
        let plain = dose()
        let releaser = dose(tachyphylaxis: 0.8)

        // Identical through onset, come-up, and peak.
        for t in stride(from: 0.0, through: plain.peakEndMinutes, by: 10) {
            let a = TimelineCurveModel.intensity(at: t, for: plain)
            let b = TimelineCurveModel.intensity(at: t, for: releaser)
            #expect(a == b)
        }
        // Strictly weaker mid-offset, and faded by the full gate at `total`.
        let mid = (plain.peakEndMinutes + plain.totalMinutes) / 2
        let plainMid = TimelineCurveModel.intensity(at: mid, for: plain)
        let releaserMid = TimelineCurveModel.intensity(at: mid, for: releaser)
        #expect(releaserMid < plainMid)
        let plainEnd = TimelineCurveModel.intensity(at: plain.totalMinutes, for: plain)
        let releaserEnd = TimelineCurveModel.intensity(at: releaser.totalMinutes, for: releaser)
        #expect(abs(releaserEnd - plainEnd * 0.2) < 1e-12)
    }

    // MARK: - Phase boundaries

    @Test
    func `Phase boundaries stay ordered onset ≤ come-up ≤ peak ≤ extent`() {
        // An explicit come-up in the data is kept exactly as given.
        let explicit = dose()
        let comeup = TimelineCurveModel.effectiveComeupEnd(
            for: explicit, onsetEnd: explicit.onsetEndMinutes, peakEnd: explicit.peakEndMinutes,
        )
        #expect(comeup == explicit.comeupEndMinutes)
        #expect(explicit.onsetEndMinutes <= comeup)
        #expect(comeup <= explicit.peakEndMinutes)
        let extent = TimelineCurveModel.curveExtent(for: explicit)
        #expect(explicit.peakEndMinutes <= extent)
    }

    @Test
    func `Missing come-up phase synthesizes a climb between onset and peak`() {
        // Profile lists only onset → peak (come-up collapses onto the onset).
        let s = dose(onsetEnd: 30, comeupEnd: 30, peakEnd: 130)
        let comeup = TimelineCurveModel.effectiveComeupEnd(for: s, onsetEnd: 30, peakEnd: 130)
        #expect(comeup > 30)
        #expect(comeup < 130)

        // A slow, absorbed onset earns the synthesized climb: 60 % of the onset,
        // floored at 8 min, capped at half the onset→peak gap.
        let slow = dose(onsetEnd: 45, comeupEnd: 45, peakEnd: 145)
        let slowComeup = TimelineCurveModel.effectiveComeupEnd(for: slow, onsetEnd: 45, peakEnd: 145)
        #expect(slowComeup == 45 + 27)

        // A fast insufflated onset stays quick — the floor never exceeds the
        // onset itself. This used to assert `2 + 8`: a 2-minute onset was given
        // a 10-minute climb, which drew an absorption shoulder on routes that
        // have no absorption phase at all.
        let fast = dose(onsetEnd: 2, comeupEnd: 2, peakEnd: 32)
        let fastComeup = TimelineCurveModel.effectiveComeupEnd(for: fast, onsetEnd: 2, peakEnd: 32)
        #expect(fastComeup == 2 + 2)
        #expect(fastComeup < slowComeup)
    }

    @Test
    func `Crest is a dome, not a flat lid, across a long peak band`() {
        // Short come-up, long peak — the shape that drew a trapezoid: a
        // near-vertical rise into an exactly flat top (methamphetamine IV).
        let s = dose(onsetEnd: 0.5, comeupEnd: 2, peakEnd: 122, offsetEnd: 332)
        let samples = stride(from: 0.0, through: 332, by: 0.1)
            .map { TimelineCurveModel.effectShape(at: $0, for: s) }
        let peak = samples.max() ?? 0

        // The maximum is still 1, so nothing downstream has to renormalize.
        #expect(abs(peak - 1) < 1e-3)
        // A flat lid would leave hundreds of bit-identical maxima; a dome
        // touches its maximum essentially once.
        let atMaximum = samples.filter { peak - $0 < 1e-6 }.count
        #expect(atMaximum < 40)
        // Still recognizably a plateau: mid-crest sits within the sag budget,
        // not on a second bell.
        #expect(TimelineCurveModel.effectShape(at: 60, for: s) > 1 - TimelineCurveModel.EffectCurveParams.domeSag)
    }

    @Test
    func `Effect shape is one smooth arc — monotone each side of a single crest`() {
        // The old three-piece curve decelerated to a dead stop at the crest's
        // left edge, then climbed again to the true maximum — the visible
        // "cap, then up, then down". One monotone rise and one monotone fall
        // around a single argmax is exactly the property that forbids it.
        let profiles = [
            dose(onsetEnd: 5, comeupEnd: 12, peakEnd: 34, offsetEnd: 108), // insufflated stimulant
            dose(), // typical oral
            dose(onsetEnd: 40, comeupEnd: 75, peakEnd: 210, offsetEnd: 285), // MDMA-like
            dose(onsetEnd: 25, comeupEnd: 55, peakEnd: 320, offsetEnd: 500), // long-peak hypnotic
        ]
        for s in profiles {
            let extent = TimelineCurveModel.curveExtent(for: s)
            let samples = stride(from: 0.0, through: extent, by: 0.25)
                .map { TimelineCurveModel.effectShape(at: $0, for: s) }
            let crest = samples.firstIndex(of: samples.max() ?? 0) ?? 0
            for i in 1 ... crest {
                #expect(samples[i] >= samples[i - 1] - 1e-9)
            }
            for i in (crest + 1) ..< samples.count {
                #expect(samples[i] <= samples[i - 1] + 1e-9)
            }
        }
    }

    @Test
    func `Effect shape passes its phase anchors`() {
        // The closed-form fit lands the curve on the phase boundaries the rest
        // of the app quotes: near-zero at the end of onset, essentially full
        // through the peak band, and effects ended at the end of offset.
        let s = dose(onsetEnd: 40, comeupEnd: 75, peakEnd: 210, offsetEnd: 285)
        let foot = TimelineCurveModel.effectShape(at: 40, for: s)
        let comeupTop = TimelineCurveModel.effectShape(at: 75, for: s)
        let peakEdge = TimelineCurveModel.effectShape(at: 210, for: s)
        let tail = TimelineCurveModel.effectShape(at: 285, for: s)
        #expect(abs(foot - TimelineCurveModel.EffectCurveParams.footLo) < 0.02)
        #expect(comeupTop > 0.85)
        #expect(peakEdge > 0.85)
        #expect(abs(tail - TimelineCurveModel.EffectCurveParams.tailLo) < 0.03)
        // The extent still clears the stated offset, so "effects ended" copy
        // never outlives the drawn curve.
        #expect(TimelineCurveModel.curveExtent(for: s) >= 285)
    }

    @Test
    func `Phase-range spreads widen the curve without breaking its anchors`() {
        let tight = dose(onsetEnd: 40, comeupEnd: 75, peakEnd: 210, offsetEnd: 285)
        let spread = ActiveSubstanceState(
            substanceName: "Testine", colorHex: "FF66AA", doseTimestamp: t0,
            amount: 20, unit: "mg", route: "oral",
            onsetEndMinutes: 40, comeupEndMinutes: 75, peakEndMinutes: 210,
            offsetEndMinutes: 285, afterglowEndMinutes: nil, totalMinutes: 400,
            doseIntensity: 0.7, doseMagnitude: 0.7,
            comeupSpreadMinutes: 30, peakSpreadMinutes: 120, offsetSpreadMinutes: 90,
        )
        // The offset spread extends the tail landing: the spread curve still
        // carries real effect where the tight one has already landed.
        #expect(
            TimelineCurveModel.effectShape(at: 285, for: spread)
                > TimelineCurveModel.effectShape(at: 285, for: tight) + 0.02,
        )
        // Still one bounded, monotone-falling tail that reaches baseline.
        let extent = TimelineCurveModel.curveExtent(for: spread)
        #expect(extent > TimelineCurveModel.curveExtent(for: tight))
        #expect(TimelineCurveModel.effectShape(at: extent, for: spread) < 0.05)
    }

    @Test
    func `Visible extent trims a curve dwarfed by a taller peer`() {
        let s = dose(onsetEnd: 30, comeupEnd: 45, peakEnd: 120, offsetEnd: 300)
        let full = TimelineCurveModel.curveExtent(for: s)

        // Beside an equal peer the trim is a no-op-ish bound: never longer.
        let alone = TimelineCurveModel.visibleExtent(for: s, peerMagnitude: s.doseMagnitude)
        #expect(alone <= full)

        // Beside a peer 50× taller it stops much earlier — the dead-axis case.
        let dwarfed = TimelineCurveModel.visibleExtent(for: s, peerMagnitude: s.doseMagnitude * 50)
        #expect(dwarfed < alone)
        #expect(dwarfed >= 1)
    }

    // MARK: - Hill merge (dose stacking)

    @Test
    func `Hill link is zero at zero and half-saturated at EC50 and monotone below 1`() {
        #expect(TimelineCurveModel.hill(0) == 0)
        #expect(abs(TimelineCurveModel.hill(TimelineCurveModel.hillEC50) - 0.5) < 1e-12)
        var previous = -1.0
        for magnitude in stride(from: 0.0, through: 10, by: 0.25) {
            let v = TimelineCurveModel.hill(magnitude)
            #expect(v > previous)
            #expect(v < 1)
            previous = v
        }
    }

    @Test
    func `4×20 mg at one timestamp matches 1×80 mg through the Hill merge`() {
        // Four doses of magnitude 0.7 vs one dose of magnitude 2.8 — the
        // documented superposition invariant: linear raw-dose sum, one
        // saturating link.
        let quad = (0 ..< 4).map { _ in dose(amount: 20, magnitude: 0.7) }
        let single = [dose(amount: 80, magnitude: 2.8)]

        for t in stride(from: 0.0, through: 400, by: 5) {
            let stacked = TimelineCurveModel.stackedIntensity(
                atGlobalMinutes: t, group: quad, earliestDose: t0,
            )
            let combined = TimelineCurveModel.stackedIntensity(
                atGlobalMinutes: t, group: single, earliestDose: t0,
            )
            #expect(abs(stacked - combined) < 1e-9)
        }
    }

    @Test
    func `Stacked intensity of well-separated doses keeps distinct humps`() {
        // Two doses 12 h apart: between them the merged curve dips well below
        // the crests — they are separate experiences, not one dome.
        let group = [dose(), dose(timestamp: t0.addingTimeInterval(12 * 3_600))]
        func merged(_ t: Double) -> Double {
            TimelineCurveModel.stackedIntensity(atGlobalMinutes: t, group: group, earliestDose: t0)
        }
        let firstCrest = merged(120)
        let valley = merged(550)
        let secondCrest = merged(720 + 120)
        #expect(valley < firstCrest * 0.2)
        #expect(valley < secondCrest * 0.2)
    }

    @Test
    func `Same substance and route stack into one group while different routes split`() {
        let doses = [
            dose(name: "MDMA", route: "oral"),
            dose(name: "mdma", timestamp: t0.addingTimeInterval(3_600), route: "Oral"),
            dose(name: "MDMA", timestamp: t0.addingTimeInterval(7_200), route: "insufflated"),
            dose(name: "Ketamine", timestamp: t0.addingTimeInterval(9_000), route: "oral"),
        ]
        let groups = TimelineCurveModel.stackedGroups(of: doses)
        #expect(groups.count == 3)
        #expect(groups[0].count == 2)
        #expect(groups[0].allSatisfy { $0.substanceName.lowercased() == "mdma" })
        #expect(groups[1].count == 1)
        #expect(groups[1][0].route == "insufflated")
        #expect(groups[2][0].substanceName == "Ketamine")
    }

    @Test
    func `Heights follow the Hill link with a non-zero floor`() {
        let s = dose(magnitude: 0.7)
        let height = TimelineCurveModel.heightScale(for: s, substances: [s], maxDose: [:])
        #expect(height == TimelineCurveModel.hill(0.7))

        let nothing = dose(magnitude: 0)
        #expect(TimelineCurveModel.heightScale(for: nothing, substances: [nothing], maxDose: [:]) == 0.0001)
    }

    // MARK: - Amplitude γ-compression

    @Test
    func `Gamma compression is monotone and clamped and lifts the low end`() {
        #expect(TimelineCurveModel.compressedAmplitude(0) == 0)
        #expect(TimelineCurveModel.compressedAmplitude(1) == 1)
        #expect(TimelineCurveModel.compressedAmplitude(-0.5) == 0)
        #expect(TimelineCurveModel.compressedAmplitude(1.5) == 1)

        var previous = -1.0
        for amplitude in stride(from: 0.0, through: 1, by: 0.05) {
            let v = TimelineCurveModel.compressedAmplitude(amplitude)
            // More raw intensity never renders lower…
            #expect(v >= previous)
            // …and a faint dose is lifted, never crushed (γ = 0.5 ≤ 1).
            #expect(v >= amplitude)
            previous = v
        }
        #expect(TimelineCurveModel.compressedAmplitude(0.1) > 0.3)
    }

    // MARK: - Derived model

    @Test
    func `Empty input produces the benign flat model`() {
        let now = Date.now
        let derived = TimelineCurveModel.computeDerived(
            substances: [], markers: [], stackRedoses: false, dayBounded: false, currentTime: now,
        )
        #expect(derived.earliestDose == now)
        #expect(derived.maxDoseBySubstance.isEmpty)
        #expect(derived.stackedGroups.isEmpty)
        #expect(derived.peakCurveValue == 1)
        #expect(derived.yNormalization == 1)
        #expect(derived.rawDataTail == 1)
        #expect(derived.rawActivityTail == 1)
    }

    @Test
    func `Data tail reaches at least as far as the activity tail and respects the day bound`() {
        let s = dose()
        let derived = TimelineCurveModel.computeDerived(
            substances: [s], markers: [], stackRedoses: false, dayBounded: false, currentTime: t0,
        )
        #expect(derived.rawDataTail >= derived.rawActivityTail)
        #expect(derived.rawActivityTail >= 1)
        #expect(derived.earliestDose == t0)
        #expect(derived.maxDoseBySubstance["testine"] == 20)

        // A long-acting dose can't stretch a day-bounded axis past 24 h.
        let longActing = dose(peakEnd: 600, offsetEnd: 1_800, total: 1_800)
        let bounded = TimelineCurveModel.computeDerived(
            substances: [longActing], markers: [], stackRedoses: false, dayBounded: true, currentTime: t0,
        )
        #expect(bounded.rawDataTail <= 24 * 60)
    }

    @Test
    func `Y-normalization maps the tallest curve toward full height capped at 20×`() {
        let faint = dose(magnitude: 0.05)
        let derived = TimelineCurveModel.computeDerived(
            substances: [faint], markers: [], stackRedoses: false, dayBounded: false, currentTime: t0,
        )
        #expect(derived.peakCurveValue == TimelineCurveModel.hill(0.05))
        #expect(derived.yNormalization == min(1.0 / derived.peakCurveValue, 20.0))
    }

    // MARK: - Lane layout

    @Test
    func `Redoses share a lane and lanes keep first-dose order`() {
        let doses = [
            dose(name: "Caffeine"),
            dose(name: "Kratom", timestamp: t0.addingTimeInterval(1_800)),
            dose(name: "caffeine", timestamp: t0.addingTimeInterval(3_600)),
        ]
        let lanes = TimelineCurveModel.laneGroups(of: doses)
        #expect(lanes.count == 2)
        #expect(lanes[0].name == "Caffeine")
        #expect(lanes[0].doses.count == 2)
        #expect(lanes[1].name == "Kratom")
        #expect(lanes[1].doses.count == 1)
    }

    @Test
    func `Marker-only substances get their own lanes excluding curve substances`() {
        let lanes = TimelineCurveModel.laneGroups(of: [dose(name: "Caffeine")])
        let markers = [
            DoseMarker(substanceName: "Caffeine", timestamp: t0, colorHex: "FF66AA", amount: 80, unit: "mg"),
            DoseMarker(substanceName: "Melatonin", timestamp: t0, colorHex: "66AAFF", amount: 0.3, unit: "mg"),
            DoseMarker(substanceName: "melatonin", timestamp: t0.addingTimeInterval(600), colorHex: "66AAFF", amount: 0.3, unit: "mg"),
        ]
        let markerLanes = TimelineCurveModel.markerOnlyLanes(excluding: lanes, markers: markers)
        #expect(markerLanes.count == 1)
        #expect(markerLanes[0].name == "Melatonin")
        #expect(markerLanes[0].markers.count == 2)
    }

    // MARK: - Tick layout

    @Test
    func `Tick intervals are clean and yield about eight labels`() {
        #expect(TimelineCurveModel.intervalForSpan(60) == 15)
        #expect(TimelineCurveModel.intervalForSpan(480) == 60)
        #expect(TimelineCurveModel.intervalForSpan(1_440) == 240)
        // Beyond every candidate, the interval clamps to a day.
        #expect(TimelineCurveModel.intervalForSpan(20_000) == 1_440)
    }
}
