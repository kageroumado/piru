import Foundation
import Testing
@testable import Piru

/// The dose timeline's heavy-tier region: which graphs may show it, where the
/// line lands, and — mostly — when it must stay off.
///
/// The y-axis is normalized to whatever is on screen, so a height only means
/// something on a single-substance graph. Everything here is a guard against
/// putting a magnitude claim on an axis that does not carry one.
@Suite("Heavy threshold region")
struct HeavyThresholdRegionTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    private func dose(
        name: String = "Testine",
        timestamp: Date? = nil,
        magnitude: Double = 0.7,
        heavyThreshold: Double? = 1.0,
    ) -> ActiveSubstanceState {
        ActiveSubstanceState(
            substanceName: name,
            colorHex: "FF66AA",
            doseTimestamp: timestamp ?? t0,
            amount: 20,
            unit: "mg",
            route: "oral",
            onsetEndMinutes: 30,
            comeupEndMinutes: 60,
            peakEndMinutes: 180,
            offsetEndMinutes: 360,
            afterglowEndMinutes: nil,
            totalMinutes: 360,
            doseIntensity: min(magnitude, 1),
            doseMagnitude: magnitude,
            heavyThresholdMagnitude: heavyThreshold,
        )
    }

    /// Non-stacked height, the entry screen's path (one dose, one curve).
    private func lone(magnitude: Double, heavyThreshold: Double? = 1.0) -> Double? {
        let s = dose(magnitude: magnitude, heavyThreshold: heavyThreshold)
        return TimelineCurveModel.heavyThresholdHeight(
            substances: [s], stackedGroups: [], stackRedoses: false,
            yNormalization: 1 / TimelineCurveModel.heightScale(for: s, substances: [s], maxDose: [:]),
        )
    }

    /// Stacked height, the journal/session path — derived exactly as the view
    /// derives it, so the normalization under test is the real one.
    private func stacked(_ substances: [ActiveSubstanceState]) -> Double? {
        let derived = TimelineCurveModel.computeDerived(
            substances: substances, markers: [], stackRedoses: true, dayBounded: false, currentTime: t0,
        )
        return TimelineCurveModel.heavyThresholdHeight(
            substances: substances,
            stackedGroups: derived.stackedGroups,
            stackRedoses: true,
            yNormalization: derived.yNormalization,
        )
    }

    // MARK: - The data gate

    @Test
    func `A substance with no published heavy bound is never shaded`() {
        #expect(lone(magnitude: 3.0, heavyThreshold: nil) == nil)
        #expect(stacked([dose(magnitude: 3.0, heavyThreshold: nil)]) == nil)
    }

    @Test
    @MainActor
    func `A resolved heavy bound comes only from a real heavy value`() {
        // The curve's own denominator will happily fall back to strong/common —
        // it needs *a* height. The region may not.
        #expect(ActiveSubstanceState.heavyThresholdMagnitude(for: DoseRange(heavy: 200)) == 1.0)
        #expect(ActiveSubstanceState.heavyThresholdMagnitude(for: DoseRange(strong: 100 ... 180)) == nil)
        #expect(ActiveSubstanceState.heavyThresholdMagnitude(for: DoseRange(common: 40 ... 80)) == nil)
        #expect(ActiveSubstanceState.heavyThresholdMagnitude(for: DoseRange(threshold: 10)) == nil)
        #expect(ActiveSubstanceState.heavyThresholdMagnitude(for: DoseRange()) == nil)
        #expect(ActiveSubstanceState.heavyThresholdMagnitude(for: nil as DoseRange?) == nil)
        // A zero is not a bound.
        #expect(ActiveSubstanceState.heavyThresholdMagnitude(for: DoseRange(heavy: 0)) == nil)
    }

    @Test
    func `Doses disagreeing about the bound are not shaded`() {
        let substances = [dose(magnitude: 1.5), dose(timestamp: t0.addingTimeInterval(3_600), magnitude: 1.5, heavyThreshold: nil)]
        #expect(stacked(substances) == nil)
    }

    // MARK: - The single-substance gate

    @Test
    func `A graph carrying two substances is never shaded`() {
        // Heights on a shared axis are relative to the tallest curve, so a line
        // drawn for one substance would move when an unrelated dose is logged.
        let substances = [dose(name: "Testine", magnitude: 2.0), dose(name: "Otherine", magnitude: 2.0)]
        #expect(stacked(substances) == nil)
        #expect(TimelineCurveModel.heavyThresholdHeight(
            substances: substances, stackedGroups: [], stackRedoses: false, yNormalization: 1,
        ) == nil)
    }

    @Test
    func `An empty graph is not shaded`() {
        #expect(TimelineCurveModel.heavyThresholdHeight(
            substances: [], stackedGroups: [], stackRedoses: false, yNormalization: 1,
        ) == nil)
    }

    // MARK: - Where the line lands

    @Test
    func `A dose below the heavy bound puts it off the top of the graph`() {
        #expect(lone(magnitude: 0.5) == nil)
        #expect(lone(magnitude: 0.95) == nil)
        #expect(stacked([dose(magnitude: 0.6)]) == nil)
    }

    @Test
    func `A dose at twice the heavy bound crosses it at half height`() throws {
        let height = try #require(lone(magnitude: 2.0))
        #expect(abs(height - 0.5) < 0.0001)
    }

    @Test
    func `Both renderers agree that the line sits under the crest`() throws {
        let magnitude = 1.6
        let loneHeight = try #require(lone(magnitude: magnitude))
        let stackedHeight = try #require(stacked([dose(magnitude: magnitude)]))
        #expect(loneHeight < 1)
        #expect(stackedHeight < 1)
        // Different arithmetic (linear vs Hill-space), same ordering and the
        // same "the curve reaches it" verdict.
        #expect(stackedHeight > loneHeight)
    }

    @Test
    func `Redoses that add past the bound are shaded when a single one is not`() throws {
        // The point of stacking: two common doses an hour apart can clear a
        // bound that neither clears alone.
        #expect(stacked([dose(magnitude: 0.6)]) == nil)
        let redosed = [dose(magnitude: 0.6), dose(timestamp: t0.addingTimeInterval(1_800), magnitude: 0.6)]
        let height = try #require(stacked(redosed))
        #expect(height > 0)
        #expect(height <= 0.98)
    }

    // MARK: - Wire compatibility

    @Test
    func `An older Live Activity payload decodes with no threshold`() throws {
        // The field is append-only; an activity started by a build that predates
        // it must decode to "no region", not fail.
        let legacy = """
        {"substanceName":"Testine","colorHex":"FF66AA","doseTimestamp":0,"amount":20,"unit":"mg",
         "route":"oral","onsetEndMinutes":30,"comeupEndMinutes":60,"peakEndMinutes":180,
         "offsetEndMinutes":360,"totalMinutes":360,"doseIntensity":0.7,"doseMagnitude":0.7}
        """
        let decoded = try JSONDecoder().decode(ActiveSubstanceState.self, from: Data(legacy.utf8))
        #expect(decoded.heavyThresholdMagnitude == nil)
    }

    @Test
    func `The threshold survives a round trip`() throws {
        let encoded = try JSONEncoder().encode(dose(magnitude: 2.0))
        let decoded = try JSONDecoder().decode(ActiveSubstanceState.self, from: encoded)
        #expect(decoded.heavyThresholdMagnitude == 1.0)
    }
}
