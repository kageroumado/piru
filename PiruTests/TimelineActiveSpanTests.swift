import CoreGraphics
import Foundation
import Testing
@testable import Piru

/// The spans ``TimelineStripBuilder`` hands ``TimelineTimeMap`` as active —
/// the only time compression may not squeeze. A long half-life or a light
/// dose under a heavy one must not hold a whole day at the uniform scale.
@Suite("TimelineActiveSpan")
struct TimelineActiveSpanTests {
    private let ppm: CGFloat = 1.4
    /// A fixed "now": the day after the fixture's doses, at noon.
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func minutes(_ m: Double) -> TimeInterval {
        m * 60
    }

    /// Cumulative phase boundaries in minutes, as ``DurationProfile/phaseBoundaries`` lays them out.
    private typealias Phases = (onset: Double, comeup: Double, peak: Double, offset: Double, total: Double)
    /// Phase-range widths (max − min) for the spread-aware curve fit.
    private typealias Spreads = (comeup: Double?, peak: Double?, offset: Double?)

    private func state(
        _ name: String,
        at timestamp: Date,
        phases: Phases,
        magnitude: Double,
        tachyphylaxis: Double,
        spreads: Spreads = (nil, nil, nil),
    ) -> ActiveSubstanceState {
        ActiveSubstanceState(
            substanceName: name,
            colorHex: "FF66AA",
            doseTimestamp: timestamp,
            amount: 1,
            unit: "mg",
            route: "oral",
            onsetEndMinutes: phases.onset,
            comeupEndMinutes: phases.comeup,
            peakEndMinutes: phases.peak,
            offsetEndMinutes: phases.offset,
            afterglowEndMinutes: nil,
            totalMinutes: phases.total,
            doseIntensity: min(magnitude, 1),
            doseMagnitude: magnitude,
            tachyphylaxis: tachyphylaxis,
            comeupSpreadMinutes: spreads.comeup,
            peakSpreadMinutes: spreads.peak,
            offsetSpreadMinutes: spreads.offset,
        )
    }

    // MARK: - The day from the report: daily memantine, a stimulant, an opioid, a depot

    /// The bundled profiles as they resolve today: memantine oral (curated:
    /// onset 60–180, peak 240–480, offset 480–720, total 720–1440; heavy 120 mg;
    /// dissociative tachyphylaxis 0.25), amphetamine oral (curated: onset 20–45,
    /// come-up 25–50, peak 90–150, offset 90–180, total 240–420; heavy 60 mg;
    /// stimulant 0.75), kratom oral (heavy 8 g; opioid 0). The 8 mg estradiol
    /// enanthate SC is a depot: it draws no effect state at all.
    private var yesterday: Date {
        now.addingTimeInterval(-27 * 3_600)
    }

    private var memantine: ActiveSubstanceState {
        state(
            "Memantine", at: yesterday,
            phases: (onset: 120, comeup: 120, peak: 480, offset: 1_080, total: 1_080),
            magnitude: 15.0 / 120, tachyphylaxis: 0.25,
            spreads: (comeup: nil, peak: 240, offset: 240),
        )
    }

    private var amphetamine: ActiveSubstanceState {
        state(
            "Amphetamine", at: yesterday.addingTimeInterval(minutes(60)),
            phases: (onset: 32.5, comeup: 70, peak: 190, offset: 325, total: 330),
            magnitude: 0.5, tachyphylaxis: 0.75,
            spreads: (comeup: 25, peak: 60, offset: 90),
        )
    }

    private var kratom: ActiveSubstanceState {
        state(
            "Kratom", at: yesterday.addingTimeInterval(minutes(300)),
            phases: (onset: 25, comeup: 50, peak: 110, offset: 210, total: 210),
            magnitude: 3.0 / 8, tachyphylaxis: 0,
        )
    }

    private func map(activeIntervals: [DateInterval], from start: Date) -> TimelineTimeMap {
        let end = now.addingTimeInterval(minutes(10))
        return TimelineTimeMap(
            start: start,
            end: end,
            now: now,
            slices: [.init(bottomTime: start, topTime: end, breakAbove: false, minimumHeight: 0)],
            anchors: activeIntervals.map(\.start),
            activeIntervals: activeIntervals,
            pointsPerMinute: ppm,
            compressGaps: true,
        )
    }

    @Test
    func `A light dose under a heavy one stops counting where it stops being legible`() throws {
        let intervals = TimelineActivity.activeSpans(states: [memantine, amphetamine, kratom]).map(\.interval)
        let byName = Dictionary(uniqueKeysWithValues: zip(["Memantine", "Amphetamine", "Kratom"], intervals.sorted { $0.start < $1.start }))

        // Compared against its own peak, the 15 mg memantine curve (magnitude
        // 0.125) stays "active" for 1,153.7 min; beside the 30 mg amphetamine
        // (0.5) it is under the 5 % bar from 959.9 min on.
        let selfCompared = TimelineCurveModel.visibleExtent(
            for: memantine, peerMagnitude: memantine.doseMagnitude, threshold: TimelineActivity.activeThreshold,
        )
        #expect(abs(selfCompared - 1_153.69) < 0.5)
        #expect(try abs(#require(byName["Memantine"]?.duration) / 60 - 959.85) < 0.5)
        // The tallest dose keeps its own extent; kratom (0.375) loses a few
        // minutes of tail to the amphetamine beside it.
        #expect(try abs(#require(byName["Amphetamine"]?.duration) / 60 - 359.79) < 0.5)
        #expect(try abs(#require(byName["Kratom"]?.duration) / 60 - 200.88) < 0.5)
    }

    @Test
    func `A light dose with nothing overlapping it keeps its own extent`() throws {
        // Amphetamine two days later shares no window with the memantine.
        let later = state(
            "Amphetamine", at: yesterday.addingTimeInterval(2 * 86_400),
            phases: (onset: 32.5, comeup: 70, peak: 190, offset: 325, total: 330),
            magnitude: 0.5, tachyphylaxis: 0.75,
        )
        let intervals = TimelineActivity.activeSpans(states: [later, memantine]).map(\.interval)
        let first = try #require(intervals.min { $0.start < $1.start })
        #expect(first.start == memantine.doseTimestamp)
        #expect(abs(first.duration / 60 - 1_153.69) < 0.5)
    }

    @Test
    func `The report's day shrinks while the stimulant and opioid windows keep the uniform scale`() {
        let states = [memantine, amphetamine, kratom]
        let start = yesterday.addingTimeInterval(-minutes(5))
        let before = map(
            activeIntervals: states.map { s in
                let m = TimelineCurveModel.visibleExtent(for: s, peerMagnitude: s.doseMagnitude, threshold: TimelineActivity.activeThreshold)
                return DateInterval(start: s.doseTimestamp, duration: minutes(m))
            },
            from: start,
        )
        let after = map(activeIntervals: TimelineActivity.activeSpans(states: states).map(\.interval), from: start)

        // Dose → now: 1,153.7 uniform minutes + one capped gap before,
        // 959.9 + the same gap after — 1,705.2 pt → 1,433.8 pt at 1.4 pt/min.
        let gap = TimelineTimeMap.gapCap(pointsPerMinute: ppm)
        #expect(abs(before.height(from: memantine.doseTimestamp, to: now) - (1_153.69 * ppm + gap)) < 1)
        #expect(abs(after.height(from: memantine.doseTimestamp, to: now) - (959.85 * ppm + gap)) < 1)

        // Inside the amphetamine and kratom windows every minute still costs
        // 1.4 pt, in both maps.
        let ampEnd = amphetamine.doseTimestamp.addingTimeInterval(minutes(359.79))
        #expect(abs(after.height(from: amphetamine.doseTimestamp, to: ampEnd) - 359.79 * ppm) < 1)
        let kratomEnd = kratom.doseTimestamp.addingTimeInterval(minutes(200.88))
        #expect(abs(after.height(from: kratom.doseTimestamp, to: kratomEnd) - 200.88 * ppm) < 1)
        // The memantine tail past 959.9 min is now dead time: one capped gap
        // up to now, where before it was 193.8 uniform minutes plus the gap.
        let memantineEnd = memantine.doseTimestamp.addingTimeInterval(minutes(959.85))
        #expect(after.height(from: memantineEnd, to: now) <= gap + 0.5)
        #expect(abs(before.height(from: memantineEnd, to: now) - ((1_153.69 - 959.85) * ppm + gap)) < 1)
    }

    // MARK: - Body load

    @Test
    func `Body load counts a dose active for two half-lives or 48 h, whichever comes first`() {
        // Memantine: t½ 70 h, absorption fit to a 120 min time-to-peak. To
        // 5 % of peak is 18,293 min (12.7 days); two half-lives is 8,400;
        // 48 h wins.
        let memantineKe = PKModel.ke(fromHalfLifeMinutes: 4_200)
        let memantineKa = PKModel.estimateKa(timeToPeak: 120, ke: memantineKe)
        #expect(abs(PKModel.timeToFraction(0.05, ke: memantineKe, ka: memantineKa) - 18_293.3) < 1)
        #expect(TimelineActivity.pkActiveMinutes(halfLife: 4_200, ke: memantineKe, ka: memantineKa) == 2_880)

        // Amphetamine: t½ 10 h → 2,681 min to 5 %; two half-lives (1,200) wins.
        let ampKe = PKModel.ke(fromHalfLifeMinutes: 600)
        let ampKa = PKModel.estimateKa(timeToPeak: 70, ke: ampKe)
        #expect(abs(PKModel.timeToFraction(0.05, ke: ampKe, ka: ampKa) - 2_681.0) < 1)
        #expect(TimelineActivity.pkActiveMinutes(halfLife: 600, ke: ampKe, ka: ampKa) == 1_200)

        // Kratom: t½ 23.2 h → 6,067 min to 5 %; two half-lives (2,780) wins.
        let kratomKe = PKModel.ke(fromHalfLifeMinutes: 1_390)
        let kratomKa = PKModel.estimateKa(timeToPeak: 50, ke: kratomKe)
        #expect(abs(PKModel.timeToFraction(0.05, ke: kratomKe, ka: kratomKa) - 6_066.8) < 1)
        #expect(TimelineActivity.pkActiveMinutes(halfLife: 1_390, ke: kratomKe, ka: kratomKa) == 2_780)

        // A short half-life too: 5 % of peak lies log2(20) ≈ 4.3 half-lives
        // past the peak, so two half-lives (180) decides before the threshold
        // for every half-life.
        let shortKe = PKModel.ke(fromHalfLifeMinutes: 90)
        let shortKa = PKModel.estimateKa(timeToPeak: 30, ke: shortKe)
        #expect(abs(PKModel.timeToFraction(0.05, ke: shortKe, ka: shortKa) - 430.7) < 1)
        #expect(TimelineActivity.pkActiveMinutes(halfLife: 90, ke: shortKe, ka: shortKa) == 180)
    }

    @Test
    func `One memantine dose two weeks ago no longer owns twelve days of strip`() {
        let dose = now.addingTimeInterval(-14 * 86_400)
        let start = dose.addingTimeInterval(-minutes(5))
        let ke = PKModel.ke(fromHalfLifeMinutes: 4_200)
        let ka = PKModel.estimateKa(timeToPeak: 120, ke: ke)

        let before = map(
            activeIntervals: [DateInterval(start: dose, duration: minutes(PKModel.timeToFraction(0.05, ke: ke, ka: ka)))],
            from: start,
        )
        let after = map(
            activeIntervals: [DateInterval(start: dose, duration: minutes(TimelineActivity.pkActiveMinutes(halfLife: 4_200, ke: ke, ka: ka)))],
            from: start,
        )
        let gap = TimelineTimeMap.gapCap(pointsPerMinute: ppm)
        // 25,700 pt of uniform tail → 4,032 pt of curve plus one capped gap.
        #expect(abs(before.height(from: dose, to: now) - (18_293.3 * ppm + gap)) < 2)
        #expect(abs(after.height(from: dose, to: now) - (2_880 * ppm + gap)) < 1)
    }

    // MARK: - A substance active for two days straight is a baseline

    private func span(_ key: String, from start: Date, minutes m: Double) -> TimelineActivity.ActiveSpan {
        .init(key: key, interval: DateInterval(start: start, duration: minutes(m)))
    }

    @Test
    func `A run of one substance protects its first 48 h and a gap resets the clock`() {
        let t0 = now.addingTimeInterval(-10 * 86_400)
        let protected = TimelineActivity.protectingIntervals([
            // Three doses 20 h apart, each active 24 h: one 64 h run.
            span("memantine", from: t0, minutes: 1_440),
            span("memantine", from: t0.addingTimeInterval(minutes(1_200)), minutes: 1_440),
            span("memantine", from: t0.addingTimeInterval(minutes(2_400)), minutes: 1_440),
            // A day off, then two more: a fresh 44 h run, kept whole.
            span("memantine", from: t0.addingTimeInterval(minutes(5_000)), minutes: 1_440),
            span("memantine", from: t0.addingTimeInterval(minutes(6_200)), minutes: 1_440),
            // Another substance inside the first run chains with nothing.
            span("amphetamine", from: t0.addingTimeInterval(minutes(3_000)), minutes: 360),
        ]).sorted { $0.start < $1.start }

        #expect(protected.count == 3)
        #expect(protected[0] == DateInterval(start: t0, duration: minutes(2_880)))
        #expect(protected[1] == DateInterval(start: t0.addingTimeInterval(minutes(3_000)), duration: minutes(360)))
        #expect(protected[2] == DateInterval(start: t0.addingTimeInterval(minutes(5_000)), duration: minutes(2_640)))
    }

    /// Five days of the report's log: memantine 20 mg at 09:00 and 15 mg at
    /// 20:00 every day, amphetamine 30 mg at 10:00 and kratom 3 g at 14:00
    /// on day 3, "now" at noon on day 5.
    private var day0: Date {
        now.addingTimeInterval(-(4 * 86_400 + 27 * 3_600))
    }

    private func at(day: Int, hour: Double) -> Date {
        day0.addingTimeInterval(Double(day) * 86_400 + (hour - 9) * 3_600)
    }

    private var memantineWeek: [ActiveSubstanceState] {
        (0 ..< 5).flatMap { day in
            [(9.0, 20.0), (20.0, 15.0)].map { hour, mg in
                state(
                    "Memantine", at: at(day: day, hour: hour),
                    phases: (onset: 120, comeup: 120, peak: 480, offset: 1_080, total: 1_080),
                    magnitude: mg / 120, tachyphylaxis: 0.25,
                    spreads: (comeup: nil, peak: 240, offset: 240),
                )
            }
        }
    }

    private var day3Amphetamine: ActiveSubstanceState {
        state(
            "Amphetamine", at: at(day: 3, hour: 10),
            phases: (onset: 32.5, comeup: 70, peak: 190, offset: 325, total: 330),
            magnitude: 0.5, tachyphylaxis: 0.75,
            spreads: (comeup: 25, peak: 60, offset: 90),
        )
    }

    private var day3Kratom: ActiveSubstanceState {
        state(
            "Kratom", at: at(day: 3, hour: 14),
            phases: (onset: 25, comeup: 50, peak: 110, offset: 210, total: 210),
            magnitude: 3.0 / 8, tachyphylaxis: 0,
        )
    }

    private func weekMap(activeIntervals: [DateInterval], anchors: [Date]) -> TimelineTimeMap {
        let start = day0.addingTimeInterval(-minutes(5))
        let end = now.addingTimeInterval(minutes(10))
        return TimelineTimeMap(
            start: start,
            end: end,
            now: now,
            slices: [.init(bottomTime: start, topTime: end, breakAbove: false, minimumHeight: 0)],
            anchors: anchors,
            activeIntervals: activeIntervals,
            pointsPerMinute: ppm,
            compressGaps: true,
        )
    }

    @Test
    func `Twice-daily memantine stops owning the strip after two days, in effect mode`() {
        let states = memantineWeek + [day3Amphetamine, day3Kratom]
        let anchors = states.map(\.doseTimestamp)
        let selfCompared = weekMap(
            activeIntervals: states.map { s in
                let m = TimelineCurveModel.visibleExtent(for: s, peerMagnitude: s.doseMagnitude, threshold: TimelineActivity.activeThreshold)
                return DateInterval(start: s.doseTimestamp, duration: minutes(m))
            },
            anchors: anchors,
        )
        let spans = TimelineActivity.activeSpans(states: states)
        let unchained = weekMap(activeIntervals: spans.map(\.interval), anchors: anchors)
        let chained = weekMap(activeIntervals: TimelineActivity.protectingIntervals(spans), anchors: anchors)

        // Day 0 09:00 → now is 7,380 min. Every memantine curve overlaps the
        // next dose's, so peer comparison alone leaves the whole run uniform
        // (10,332 pt); the baseline rule keeps only its first 2,880 min.
        #expect(abs(selfCompared.height(from: day0, to: now) - 10_332) < 1)
        #expect(abs(unchained.height(from: day0, to: now) - 10_332) < 1)
        #expect(abs(chained.height(from: day0, to: now) - 5_273.2) < 1)
        #expect(abs(chained.height(from: day0, to: at(day: 2, hour: 9)) - 2_880 * ppm) < 1)

        // The memantine-only stretch from day 2 09:00 to the amphetamine on
        // day 3 (25 h) is three capped gaps between dose anchors: 90 + 90 + 84.
        #expect(abs(unchained.height(from: at(day: 2, hour: 9), to: at(day: 3, hour: 10)) - 2_100) < 1)
        #expect(abs(chained.height(from: at(day: 2, hour: 9), to: at(day: 3, hour: 10)) - 264) < 1)

        // The amphetamine and kratom windows (10:00 → 17:21) keep the uniform
        // scale in every variant; the memantine tail after them is four
        // capped gaps up to now.
        let windowEnd = at(day: 3, hour: 10).addingTimeInterval(minutes(440.88))
        for map in [selfCompared, unchained, chained] {
            #expect(abs(map.height(from: at(day: 3, hour: 10), to: windowEnd) - 440.88 * ppm) < 1)
        }
        #expect(abs(unchained.height(from: windowEnd, to: now) - 3_582.8) < 1)
        #expect(abs(chained.height(from: windowEnd, to: now) - 360) < 1)
    }

    @Test
    func `Twice-daily memantine stops owning the strip after two days, in body-load mode`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 4_200)
        let ka = PKModel.estimateKa(timeToPeak: 120, ke: ke)
        let perDose = TimelineActivity.pkActiveMinutes(halfLife: 4_200, ke: ke, ka: ka)
        let memantine = memantineWeek.map { span("memantine", from: $0.doseTimestamp, minutes: perDose) }
        let ampKe = PKModel.ke(fromHalfLifeMinutes: 600)
        let kratomKe = PKModel.ke(fromHalfLifeMinutes: 1_390)
        let others = [
            span("amphetamine", from: at(day: 3, hour: 10), minutes: TimelineActivity.pkActiveMinutes(
                halfLife: 600, ke: ampKe, ka: PKModel.estimateKa(timeToPeak: 70, ke: ampKe),
            )),
            span("kratom", from: at(day: 3, hour: 14), minutes: TimelineActivity.pkActiveMinutes(
                halfLife: 1_390, ke: kratomKe, ka: PKModel.estimateKa(timeToPeak: 50, ke: kratomKe),
            )),
        ]
        let anchors = memantineWeek.map(\.doseTimestamp) + [at(day: 3, hour: 10), at(day: 3, hour: 14)]

        // 48 h per dose, twice a day: one unbroken run, so the per-dose cap
        // alone changes nothing (10,332 pt). Chained, the run protects its
        // first two days; the amphetamine (20 h) and kratom (46 h) spans
        // keep day 3 10:00 → now uniform.
        let unchained = weekMap(activeIntervals: (memantine + others).map(\.interval), anchors: anchors)
        let chained = weekMap(activeIntervals: TimelineActivity.protectingIntervals(memantine + others), anchors: anchors)
        #expect(abs(unchained.height(from: day0, to: now) - 10_332) < 1)
        #expect(abs(chained.height(from: day0, to: now) - 8_496) < 1)
        #expect(abs(chained.height(from: at(day: 2, hour: 9), to: at(day: 3, hour: 10)) - 264) < 1)
        #expect(abs(chained.height(from: at(day: 3, hour: 10), to: now) - 3_000 * ppm) < 1)

        // Memantine alone: 10,332 pt → 2,880 uniform minutes plus six capped
        // gaps between the remaining dose anchors.
        let memantineOnly = weekMap(
            activeIntervals: TimelineActivity.protectingIntervals(memantine),
            anchors: memantineWeek.map(\.doseTimestamp),
        )
        #expect(abs(memantineOnly.height(from: day0, to: now) - 4_572) < 1)
    }
}
