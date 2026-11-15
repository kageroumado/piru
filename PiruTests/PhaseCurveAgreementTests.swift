import Foundation
import Testing
@testable import Piru

/// The phase word, the milestone marks and "effects end" read the same
/// boundaries the effect curve is drawn through, so a dose labeled "Peak" is
/// on the drawn crest and one labeled "Come-up" is on the drawn rise.
@Suite("PhaseCurveAgreement")
struct PhaseCurveAgreementTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private typealias Fit = TimelineCurveModel.EffectCurveParams

    /// 4-FEA oral as the bundled DB resolves it: TripSit's onset 40–60 and
    /// total 4–6 h, drug.community's single-figure peak and offset of 2 h, no
    /// come-up anywhere. Too little of the total is unexplained for
    /// `fillingMissingPhases` to synthesize one, so the profile reaches the
    /// state with the come-up collapsed onto the onset.
    private var fourFEA: ActiveSubstanceState {
        let profile = DurationProfile(
            onset: DurationRange(min: 40, max: 60),
            comeup: nil,
            peak: DurationRange(min: 120, max: 120),
            offset: DurationRange(min: 120, max: 120),
            afterglow: DurationRange(min: 60, max: 720),
            total: DurationRange(min: 240, max: 360),
        )
        return state(profile, category: .stimulant)
    }

    /// Amphetamine oral's curated ranges, whose come-up and offset spreads
    /// move the anchors the curve is fitted through.
    private var amphetamine: ActiveSubstanceState {
        let profile = DurationProfile(
            onset: DurationRange(min: 20, max: 45),
            comeup: DurationRange(min: 25, max: 50),
            peak: DurationRange(min: 90, max: 150),
            offset: DurationRange(min: 90, max: 180),
            afterglow: nil,
            total: DurationRange(min: 240, max: 420),
        )
        return state(profile, category: .stimulant)
    }

    private func state(_ profile: DurationProfile, category: SubstanceCategory) -> ActiveSubstanceState {
        guard let state = ActiveSubstanceState(
            name: "Testine", tint: P3Color(red: 0.929, green: 0.439, blue: 0.660), timestamp: t0,
            amount: 15, unit: "mg", routeDisplayName: "Oral", duration: profile, category: category,
            doseIntensity: 0.5, doseMagnitude: 0.5, tachyphylaxis: category.acuteToleranceFactor,
        ) else {
            Issue.record("the builder dropped a profile with a total")
            return ActiveSubstanceState(
                substanceName: "", tint: P3Color(red: 0, green: 0, blue: 0), doseTimestamp: t0, amount: 0, unit: "mg",
                route: "", onsetEndMinutes: 0, comeupEndMinutes: 0, peakEndMinutes: 0, offsetEndMinutes: 0,
                afterglowEndMinutes: nil, totalMinutes: 0,
            )
        }
        return state
    }

    @Test
    func `A dose 56 minutes into 4-FEA is coming up, on the rise the curve draws`() {
        let s = fourFEA
        let phase = DosePhaseProgressBar.phase(s, elapsedMinutes: 56)
        #expect(phase == .comeup)
        #expect(TimelineCurveModel.effectShape(at: 56, for: s) < Fit.crestHi)
        // Onset ends at 50 min, the synthesized come-up runs 30 min to 80.
        #expect(abs(s.onsetEndMinutes - 50) < 1e-9)
        #expect(abs(s.comeupEndMinutes - 80) < 1e-9)
    }

    @Test(arguments: ["4-FEA", "amphetamine"])
    func `Every phase name matches the stretch of curve it labels`(_ name: String) {
        let s = name == "4-FEA" ? fourFEA : amphetamine
        let tolerance = 1e-6
        for minutes in stride(from: 0.5, through: s.totalMinutes, by: 0.5) {
            let shape = TimelineCurveModel.effectShape(at: minutes, for: s)
            switch DosePhaseProgressBar.phase(s, elapsedMinutes: minutes) {
            case .onset:
                #expect(shape <= Fit.footLo + tolerance, "onset at \(minutes) min draws \(shape)")
            case .comeup:
                #expect(shape >= Fit.footLo - tolerance && shape <= Fit.crestHi + tolerance, "come-up at \(minutes) min draws \(shape)")
            case .peak:
                #expect(shape >= Fit.crestHi - tolerance, "peak at \(minutes) min draws \(shape)")
            case .offset:
                #expect(shape >= Fit.tailLo - tolerance && shape <= Fit.crestHi + tolerance, "offset at \(minutes) min draws \(shape)")
            case .after:
                #expect(shape <= Fit.tailLo + tolerance, "afterglow at \(minutes) min draws \(shape)")
            }
        }
    }

    @Test(arguments: ["4-FEA", "amphetamine"])
    func `The milestones sit where the curve turns`(_ name: String) {
        let s = name == "4-FEA" ? fourFEA : amphetamine
        // The marks the timeline places: ↗ at onset end, ☀ at come-up end,
        // ↘ at peak end, the end mark at total.
        #expect(abs(TimelineCurveModel.effectShape(at: s.onsetEndMinutes, for: s) - Fit.footLo) < 1e-6)
        #expect(abs(TimelineCurveModel.effectShape(at: s.comeupEndMinutes, for: s) - Fit.crestHi) < 1e-6)
        #expect(abs(TimelineCurveModel.effectShape(at: s.peakEndMinutes, for: s) - Fit.crestHi) < 1e-6)
        #expect(abs(TimelineCurveModel.effectShape(at: s.offsetEndMinutes, for: s) - Fit.tailLo) < 1e-6)
        // "Effects end" is never before the tail lands, and the drawn curve
        // reaches the axis no later than a few percent past it.
        #expect(s.totalMinutes >= s.offsetEndMinutes)
        #expect(TimelineCurveModel.curveExtent(for: s) <= s.totalMinutes * 1.1)
    }

    @Test
    func `Spreads move the stored anchors and are not applied twice`() {
        let s = amphetamine
        // Midpoints 32.5 / 70 / 190 / 325; the come-up spread (25) delays full
        // effect by 12.5 min, the offset spread (90) lands the tail 45 min later.
        #expect(abs(s.comeupEndMinutes - 82.5) < 1e-9)
        #expect(abs(s.offsetEndMinutes - 370) < 1e-9)
        #expect(s.totalMinutes == 370)
        #expect(s.comeupSpreadMinutes == nil && s.offsetSpreadMinutes == nil)
        #expect(s.peakSpreadMinutes == 60)
    }

    @Test
    func `A state survives an encode and decode unchanged`() throws {
        for s in [fourFEA, amphetamine] {
            let decoded = try JSONDecoder().decode(ActiveSubstanceState.self, from: JSONEncoder().encode(s))
            #expect(decoded == s)
        }
    }

    @Test
    func `A payload with raw boundaries decodes onto the curve's anchors`() throws {
        // What a build before the anchors were stored put in a Live Activity.
        let raw = """
        {"substanceName":"Testine","tint":[0.9,0.4,0.6],"doseTimestamp":0,"amount":15,
         "unit":"mg","route":"Oral","onsetEndMinutes":32.5,"comeupEndMinutes":70,"peakEndMinutes":190,
         "offsetEndMinutes":325,"totalMinutes":330,"comeupSpreadMinutes":25,"peakSpreadMinutes":60,
         "offsetSpreadMinutes":90}
        """
        let decoded = try JSONDecoder().decode(ActiveSubstanceState.self, from: Data(raw.utf8))
        #expect(abs(decoded.comeupEndMinutes - 82.5) < 1e-9)
        #expect(abs(decoded.offsetEndMinutes - 370) < 1e-9)
        #expect(decoded.totalMinutes == 370)
    }
}
