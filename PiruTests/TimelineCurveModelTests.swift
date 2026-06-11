import Foundation
import Testing
@testable import Piru

/// Characterization tests for the extracted timeline curve math. These pin the
/// *current* rendering semantics — the Gaussian-shouldered effect shape, the
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
        let params = TimelineCurveModel.pkParams(for: s)
        let extent = TimelineCurveModel.curveExtent(for: s, params: params)

        var peakValue = -1.0
        var peakTime = 0.0
        for t in stride(from: 0.0, through: extent, by: 1) {
            let v = TimelineCurveModel.intensity(at: t, for: s, params: params)
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
        #expect(TimelineCurveModel.intensity(at: extent, for: s, params: params) < peakValue * 0.1)

        // Rising shoulder is monotone non-decreasing up to the crest.
        var previous = -1.0
        for t in stride(from: 0.0, through: 80, by: 10) {
            let v = TimelineCurveModel.intensity(at: t, for: s, params: params)
            #expect(v >= previous)
            previous = v
        }
    }

    @Test
    func `Intensity is non-negative and bounded and zero before the dose`() {
        let s = dose()
        let params = TimelineCurveModel.pkParams(for: s)
        let extent = TimelineCurveModel.curveExtent(for: s, params: params)
        for t in stride(from: 0.0, through: extent, by: 2) {
            let v = TimelineCurveModel.intensity(at: t, for: s, params: params)
            #expect(v >= 0)
            #expect(v <= 1)
        }
        #expect(TimelineCurveModel.intensity(at: -5, for: s, params: params) == 0)
    }

    @Test
    func `Descending limb tapers monotonically to near zero at the curve extent`() {
        let s = dose()
        let params = TimelineCurveModel.pkParams(for: s)
        let extent = TimelineCurveModel.curveExtent(for: s, params: params)
        // The extent reaches past the stated offset so the tail eases onto the
        // axis instead of being clipped.
        #expect(extent >= s.offsetEndMinutes)

        var previous = Double.greatestFiniteMagnitude
        for t in stride(from: s.peakEndMinutes, through: extent, by: 5) {
            let v = TimelineCurveModel.intensity(at: t, for: s, params: params)
            #expect(v <= previous + 1e-12)
            previous = v
        }
        #expect(TimelineCurveModel.intensity(at: extent, for: s, params: params) < 0.05)
    }

    @Test
    func `Tachyphylaxis crashes the descending limb but leaves onset and peak untouched`() {
        let plain = dose()
        let releaser = dose(tachyphylaxis: 0.8)
        let pPlain = TimelineCurveModel.pkParams(for: plain)
        let pReleaser = TimelineCurveModel.pkParams(for: releaser)

        // Identical through onset, come-up, and peak.
        for t in stride(from: 0.0, through: plain.peakEndMinutes, by: 10) {
            let a = TimelineCurveModel.intensity(at: t, for: plain, params: pPlain)
            let b = TimelineCurveModel.intensity(at: t, for: releaser, params: pReleaser)
            #expect(a == b)
        }
        // Strictly weaker mid-offset, and faded by the full gate at `total`.
        let mid = (plain.peakEndMinutes + plain.totalMinutes) / 2
        let plainMid = TimelineCurveModel.intensity(at: mid, for: plain, params: pPlain)
        let releaserMid = TimelineCurveModel.intensity(at: mid, for: releaser, params: pReleaser)
        #expect(releaserMid < plainMid)
        let plainEnd = TimelineCurveModel.intensity(at: plain.totalMinutes, for: plain, params: pPlain)
        let releaserEnd = TimelineCurveModel.intensity(at: releaser.totalMinutes, for: releaser, params: pReleaser)
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
        let extent = TimelineCurveModel.curveExtent(for: explicit, params: TimelineCurveModel.pkParams(for: explicit))
        #expect(explicit.peakEndMinutes <= extent)
    }

    @Test
    func `Missing come-up phase synthesizes a climb between onset and peak`() {
        // Profile lists only onset → peak (come-up collapses onto the onset).
        let s = dose(onsetEnd: 30, comeupEnd: 30, peakEnd: 130)
        let comeup = TimelineCurveModel.effectiveComeupEnd(for: s, onsetEnd: 30, peakEnd: 130)
        #expect(comeup > 30)
        #expect(comeup < 130)

        // A fast insufflated onset stays quick: floored at 8 min, capped at
        // half the onset→peak gap.
        let fast = dose(onsetEnd: 2, comeupEnd: 2, peakEnd: 32)
        let fastComeup = TimelineCurveModel.effectiveComeupEnd(for: fast, onsetEnd: 2, peakEnd: 32)
        #expect(fastComeup == 2 + 8)
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
        let quadParams = quad.map { TimelineCurveModel.pkParams(for: $0) }
        let singleParams = single.map { TimelineCurveModel.pkParams(for: $0) }

        for t in stride(from: 0.0, through: 400, by: 5) {
            let stacked = TimelineCurveModel.stackedIntensity(
                atGlobalMinutes: t, group: quad, params: quadParams, earliestDose: t0,
            )
            let combined = TimelineCurveModel.stackedIntensity(
                atGlobalMinutes: t, group: single, params: singleParams, earliestDose: t0,
            )
            #expect(abs(stacked - combined) < 1e-9)
        }
    }

    @Test
    func `Stacked intensity of well-separated doses keeps distinct humps`() {
        // Two doses 12 h apart: between them the merged curve dips well below
        // the crests — they are separate experiences, not one dome.
        let group = [dose(), dose(timestamp: t0.addingTimeInterval(12 * 3_600))]
        let params = group.map { TimelineCurveModel.pkParams(for: $0) }
        func merged(_ t: Double) -> Double {
            TimelineCurveModel.stackedIntensity(atGlobalMinutes: t, group: group, params: params, earliestDose: t0)
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
            dose(name: "mdma", route: "Oral", timestamp: t0.addingTimeInterval(3_600)),
            dose(name: "MDMA", route: "insufflated", timestamp: t0.addingTimeInterval(7_200)),
            dose(name: "Ketamine", route: "oral", timestamp: t0.addingTimeInterval(9_000)),
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
