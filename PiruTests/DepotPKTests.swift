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

    // MARK: - Multi-ester summation

    @Test
    func `A single summed contribution equals its own depot curve`() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(60 * 86_400)
        let inj = [(date: start, doseMg: 5.0), (date: start.addingTimeInterval(14 * 86_400), doseMg: 5.0)]
        let single = PKModel.depotCurve(injections: inj, over: start ... end, parameters: Self.cypionate, pointCount: 50)
        let summed = PKModel.depotCurveSummed(
            contributions: [.init(injections: inj, parameters: Self.cypionate)],
            over: start ... end, pointCount: 50,
        )
        #expect(summed.total.count == 50)
        #expect(summed.contributions.count == 1)
        for (a, b) in zip(single, summed.total) {
            #expect(a.date == b.date)
            #expect(abs(a.pgPerML - b.value) < 1e-9)
        }
    }

    @Test
    func `The summed total is the elementwise sum of two esters on a shared grid`() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(60 * 86_400)
        let valerate = [(date: start, doseMg: 4.0)]
        let cypionate = [(date: start.addingTimeInterval(21 * 86_400), doseMg: 3.0)]
        let a = PKModel.depotCurve(injections: valerate, over: start ... end, parameters: Self.valerate, pointCount: 80)
        let b = PKModel.depotCurve(injections: cypionate, over: start ... end, parameters: Self.cypionate, pointCount: 80)
        let summed = PKModel.depotCurveSummed(
            contributions: [
                .init(injections: valerate, parameters: Self.valerate),
                .init(injections: cypionate, parameters: Self.cypionate),
            ],
            over: start ... end, pointCount: 80,
        )
        #expect(summed.contributions.count == 2)
        for i in 0 ..< 80 {
            #expect(summed.contributions[0][i].date == summed.total[i].date)
            #expect(abs(summed.contributions[0][i].value - a[i].pgPerML) < 1e-9)
            #expect(abs(summed.contributions[1][i].value - b[i].pgPerML) < 1e-9)
            #expect(abs(summed.total[i].value - (a[i].pgPerML + b[i].pgPerML)) < 1e-9)
        }
    }

    @Test
    func `A one-point summed curve returns a single sample per contribution`() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let inj = [(date: start.addingTimeInterval(-5 * 86_400), doseMg: 5.0)]
        let summed = PKModel.depotCurveSummed(
            contributions: [.init(injections: inj, parameters: Self.cypionate)],
            over: start ... start, pointCount: 1,
        )
        #expect(summed.total.count == 1)
        #expect(summed.contributions.count == 1)
        #expect(summed.total[0].value > 0)
    }

    @Test
    func `depotConcentrationSummed adds each contribution at an instant`() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let at = start.addingTimeInterval(10 * 86_400)
        let valerate = [(date: start, doseMg: 4.0)]
        let cypionate = [(date: start, doseMg: 3.0)]
        let summed = PKModel.depotConcentrationSummed(
            contributions: [
                .init(injections: valerate, parameters: Self.valerate),
                .init(injections: cypionate, parameters: Self.cypionate),
            ],
            at: at,
        )
        let a = PKModel.depotConcentrationMultiDose(injections: valerate, at: at, parameters: Self.valerate)
        let b = PKModel.depotConcentrationMultiDose(injections: cypionate, at: at, parameters: Self.cypionate)
        #expect(abs(summed - (a + b)) < 1e-9)
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
    func `Amplitude-only fit recovers the true scale exactly with small residual`() {
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
        // fitRate off → pure amplitude fit, exact for amplitude-only data.
        let result = DepotCalibration.calibrate(population: Self.cypionate, injections: injections, measurements: measurements, fitRate: false)
        #expect(abs((result?.scale ?? 0) - 1.5) < 1e-6)
        #expect(result?.k1Scale == 1.0)
        #expect((result?.residualRMS ?? 99) < 1e-3)
    }

    @Test
    func `Rate-fit recovers a rate-scaled curve two params from two points`() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let injections = [
            (date: now, doseMg: 5.0),
            (date: now.addingTimeInterval(14 * 86_400), doseMg: 5.0),
        ]
        // Synthesize a user whose amplitude is 1.5× AND whose terminal rate k1 runs
        // 1.3× the population — the shape the amplitude-only fit structurally can't reach.
        let trueParams = Self.cypionate.withK1Scale(1.3).withAmplitude(Self.cypionate.d * 1.5)
        func trueLevel(_ days: Double) -> Double {
            PKModel.depotConcentrationMultiDose(injections: injections, at: now.addingTimeInterval(days * 86_400), parameters: trueParams)
        }
        let measurements = [
            DepotCalibration.Measurement(date: now.addingTimeInterval(4 * 86_400), value: trueLevel(4)),
            DepotCalibration.Measurement(date: now.addingTimeInterval(20 * 86_400), value: trueLevel(20)),
        ]
        let result = DepotCalibration.calibrate(population: Self.cypionate, injections: injections, measurements: measurements)
        #expect(result?.didFitRate == true)
        #expect(abs((result?.k1Scale ?? 0) - 1.3) < 5e-3)
        #expect(abs((result?.scale ?? 0) - 1.5) < 5e-3)
        // Two params through two points → residual ≈ 0.
        #expect((result?.residualRMS ?? 99) < 1e-2)
    }

    @Test
    func `Summed calibration recovers a person-wide amplitude scale across two esters`() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let valerate = [(date: now, doseMg: 4.0)]
        let cypionate = [(date: now.addingTimeInterval(7 * 86_400), doseMg: 3.0)]
        let contributions = [
            PKModel.DepotContribution(injections: valerate, parameters: DepotPKTests.valerate),
            PKModel.DepotContribution(injections: cypionate, parameters: DepotPKTests.cypionate),
        ]
        /// A user who runs 1.8× the population sum, fit amplitude-only.
        func trueLevel(_ days: Double) -> Double {
            1.8 * PKModel.depotConcentrationSummed(contributions: contributions, at: now.addingTimeInterval(days * 86_400))
        }
        let measurements = [
            DepotCalibration.Measurement(date: now.addingTimeInterval(10 * 86_400), value: trueLevel(10)),
            DepotCalibration.Measurement(date: now.addingTimeInterval(17 * 86_400), value: trueLevel(17)),
        ]
        let result = DepotCalibration.calibrateSummed(contributions: contributions, measurements: measurements, fitRate: false)
        #expect(abs((result?.scale ?? 0) - 1.8) < 1e-6)
        #expect(result?.k1Scale == 1.0)
        #expect((result?.residualRMS ?? 99) < 1e-3)
    }

    @Test
    func `Summed calibration with no usable point returns nil`() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let contributions = [
            PKModel.DepotContribution(injections: [(date: now.addingTimeInterval(86_400), doseMg: 4)], parameters: DepotPKTests.valerate),
        ]
        // Measurement before the only injection → predicted 0 → nothing to fit.
        let result = DepotCalibration.calibrateSummed(
            contributions: contributions,
            measurements: [.init(date: now, value: 100)],
        )
        #expect(result == nil)
    }

    @Test
    func `Outlier detection needs at least three calibration points`() {
        #expect(!DepotCalibration.isOutlier(observed: 500, predicted: 100, residualRMS: 10, calibrationCount: 2))
        #expect(DepotCalibration.isOutlier(observed: 500, predicted: 100, residualRMS: 10, calibrationCount: 3))
        #expect(!DepotCalibration.isOutlier(observed: 105, predicted: 100, residualRMS: 10, calibrationCount: 3))
    }
}
