import Foundation
import Testing
@testable import Piru

/// Depot PK math + lab calibration for the Injection Levels tool. The evidence
/// file (Specs/evidence/estradiol-tool/ester-pk-parameters.json) is the oracle:
/// it states the estrannaise oil-based cypionate fit peaks at 113 pg/mL at 3.88 d
/// and the valerate fit at 306 pg/mL at 1.90 d for a 5 mg dose.
@Suite("Depot PK")
struct DepotPKTests {
    // Population parameters (from ester_pk/estradiol.json).
    static let cypionate = PKModel.DepotParameters(d: 246.0, k1: 0.0825, k2: 3.57, k3: 0.669)
    static let valerate = PKModel.DepotParameters(d: 478.0, k1: 0.236, k2: 4.85, k3: 1.24)

    // MARK: - Single dose

    @Test
    func `Concentration at t=0 is zero`() {
        #expect(PKModel.depotConcentration(doseMg: 5, at: 0, parameters: Self.cypionate) == 0)
    }

    @Test
    func `Negative time returns zero`() {
        #expect(PKModel.depotConcentration(doseMg: 5, at: -1, parameters: Self.cypionate) == 0)
    }

    @Test
    func `Cypionate 5 mg peaks near 113 pg/mL at ~3.88 days`() {
        var peak = 0.0
        var peakDay = 0.0
        var day = 0.0
        while day < 30 {
            let c = PKModel.depotConcentration(doseMg: 5, at: day, parameters: Self.cypionate)
            if c > peak { peak = c; peakDay = day }
            day += 0.01
        }
        #expect(abs(peak - 112.7) < 1.0)
        #expect(abs(peakDay - 3.88) < 0.1)
    }

    @Test
    func `Valerate 5 mg peaks near 306 pg/mL at ~1.90 days`() {
        var peak = 0.0
        var peakDay = 0.0
        var day = 0.0
        while day < 20 {
            let c = PKModel.depotConcentration(doseMg: 5, at: day, parameters: Self.valerate)
            if c > peak { peak = c; peakDay = day }
            day += 0.01
        }
        #expect(abs(peak - 305.6) < 1.0)
        #expect(abs(peakDay - 1.90) < 0.1)
    }

    @Test
    func `Concentration is linear in dose`() {
        let one = PKModel.depotConcentration(doseMg: 5, at: 4, parameters: Self.cypionate)
        let two = PKModel.depotConcentration(doseMg: 10, at: 4, parameters: Self.cypionate)
        #expect(abs(two - 2 * one) < 1e-9)
    }

    @Test
    func `Coincident rate constants do not divide by zero`() {
        let p = PKModel.DepotParameters(d: 200, k1: 0.5, k2: 0.5, k3: 0.5)
        let c = PKModel.depotConcentration(doseMg: 5, at: 3, parameters: p)
        #expect(c.isFinite)
        #expect(c >= 0)
    }

    // MARK: - Multi-dose

    @Test
    func `Superposition equals the sum of single doses`() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let injections = [
            (date: now, doseMg: 5.0),
            (date: now.addingTimeInterval(14 * 86_400), doseMg: 5.0),
        ]
        let at = now.addingTimeInterval(20 * 86_400)
        let total = PKModel.depotConcentrationMultiDose(injections: injections, at: at, parameters: Self.cypionate)
        let a = PKModel.depotConcentration(doseMg: 5, at: 20, parameters: Self.cypionate)
        let b = PKModel.depotConcentration(doseMg: 5, at: 6, parameters: Self.cypionate)
        #expect(abs(total - (a + b)) < 1e-6)
    }

    @Test
    func `Future injections do not contribute`() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let injections = [(date: now.addingTimeInterval(10 * 86_400), doseMg: 5.0)]
        #expect(PKModel.depotConcentrationMultiDose(injections: injections, at: now, parameters: Self.cypionate) == 0)
    }

    @Test
    func `Curve samples the requested number of points across the range`() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(60 * 86_400)
        let curve = PKModel.depotCurve(
            injections: [(date: start, doseMg: 5)],
            over: start ... end, parameters: Self.cypionate, pointCount: 100,
        )
        #expect(curve.count == 100)
        #expect(curve.first?.date == start)
        #expect(try abs(#require(curve.last?.date.timeIntervalSince(end))) < 1)
    }
}

@Suite("Depot calibration")
struct DepotCalibrationTests {
    static let cypionate = DepotPKTests.cypionate

    @Test
    func `Single measurement scales amplitude by the observed/predicted ratio`() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let injections = [(date: now, doseMg: 5.0)]
        let drawDate = now.addingTimeInterval(4 * 86_400)
        // A user whose true level is 2× the population prediction.
        let unitPredicted = PKModel.depotConcentration(
            doseMg: 5, at: 4, parameters: Self.cypionate.withAmplitude(1),
        )
        let observed = 2 * Self.cypionate.d * unitPredicted
        let result = DepotCalibration.calibrate(
            population: Self.cypionate, injections: injections,
            measurements: [.init(date: drawDate, value: observed)],
        )
        #expect(result != nil)
        #expect(abs((result?.scale ?? 0) - 2) < 1e-6)
        #expect(result?.residualRMS == nil) // one point fits exactly
    }

    @Test
    func `No measurement on a nonzero prediction returns nil`() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        // Measurement before the only injection → predicted 0 → nothing to fit.
        let result = DepotCalibration.calibrate(
            population: Self.cypionate,
            injections: [(date: now.addingTimeInterval(86_400), doseMg: 5)],
            measurements: [.init(date: now, value: 100)],
        )
        #expect(result == nil)
    }

    @Test
    func `Two consistent measurements recover the true scale with small residual`() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let injections = [
            (date: now, doseMg: 5.0),
            (date: now.addingTimeInterval(14 * 86_400), doseMg: 5.0),
        ]
        func trueLevel(_ days: Double) -> Double {
            let at = now.addingTimeInterval(days * 86_400)
            return 1.5 * PKModel.depotConcentrationMultiDose(injections: injections, at: at, parameters: Self.cypionate)
        }
        let measurements = [
            DepotCalibration.Measurement(date: now.addingTimeInterval(4 * 86_400), value: trueLevel(4)),
            DepotCalibration.Measurement(date: now.addingTimeInterval(18 * 86_400), value: trueLevel(18)),
        ]
        let result = DepotCalibration.calibrate(population: Self.cypionate, injections: injections, measurements: measurements)
        #expect(abs((result?.scale ?? 0) - 1.5) < 1e-6)
        #expect((result?.residualRMS ?? 99) < 1e-3)
    }

    @Test
    func `Outlier detection needs at least three calibration points`() {
        #expect(!DepotCalibration.isOutlier(observed: 500, predicted: 100, residualRMS: 10, calibrationCount: 2))
        #expect(DepotCalibration.isOutlier(observed: 500, predicted: 100, residualRMS: 10, calibrationCount: 3))
        #expect(!DepotCalibration.isOutlier(observed: 105, predicted: 100, residualRMS: 10, calibrationCount: 3))
    }
}
