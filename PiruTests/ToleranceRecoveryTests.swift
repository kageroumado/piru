import Foundation
import Testing
@testable import Piru

/// Pins the Tolerance tool's recovery math to the values it produces for three classes of input:
/// an opioid-like class with three engaged layers, a capped entactogen-like class whose synthesis pool
/// is engaged, and a faint class already below its target.
@Suite("Tolerance recovery math")
@MainActor
struct ToleranceRecoveryTests {
    private struct Case {
        let layers: [ToleranceRecovery.Layer]
        let occupancy: Double
        let cap: Double?
        let minutes: Double
        let target: Double
        let initialShift: Double
        let shiftAfter: Double
        let targetShift: Double
        let recoveryMinutes: Double
        let toleranceAfter: Double
    }

    private static let cases: [Case] = [
        Case(
            layers: [(0.4, 360), (0.8, 10_080), (0.1, 129_600), (0.0, 20_160)],
            occupancy: 0.6, cap: nil, minutes: 1_440, target: 0.05,
            initialShift: 3.6692966676192453, shiftAfter: 2.224925905767417,
            targetShift: 1.1315789473684215, recoveryMinutes: 29_274.605094213213,
            toleranceAfter: 0.3288457104263004,
        ),
        Case(
            layers: [(1.2, 240), (0.3, 4_320), (0.0, 129_600), (0.9, 40_320)],
            occupancy: 0.8, cap: 0.5, minutes: 10_080, target: 0.05,
            initialShift: 11.023176380641601, shiftAfter: 2.0751061212034903,
            targetShift: 1.1052631578947367, recoveryMinutes: 88_558.45865346608,
            toleranceAfter: 0.3496159413135085,
        ),
        Case(
            layers: [(0.02, 120), (0.01, 4_320), (0.0, 129_600), (0.0, 20_160)],
            occupancy: 0.3, cap: nil, minutes: 60, target: 0.10,
            initialShift: 1.030454533953517, shiftAfter: 1.0222363061320028,
            targetShift: 1.1587301587301586, recoveryMinutes: 0,
            toleranceAfter: 0.01532684559098263,
        ),
    ]

    private static func close(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) <= 1e-9 * max(1, abs(expected))
    }

    @Test(arguments: 0 ..< 3)
    func `The shift factor decays each layer on its own time constant`(index: Int) {
        let c = Self.cases[index]
        #expect(Self.close(ToleranceRecovery.shiftFactor(layers: c.layers, afterMinutes: 0), c.initialShift))
        #expect(Self.close(ToleranceRecovery.shiftFactor(layers: c.layers, afterMinutes: c.minutes), c.shiftAfter))
    }

    @Test(arguments: 0 ..< 3)
    func `The gauge inversion gives the shift at the target tolerance`(index: Int) {
        let c = Self.cases[index]
        let shift = ToleranceRecovery.targetShift(toTolerance: c.target, occupancy: c.occupancy, occupancyCap: c.cap)
        #expect(Self.close(shift, c.targetShift))
        let tolerance = 1 - PDModel.responseFraction(
            shiftFactor: shift, representativeOccupancy: c.occupancy, occupancyCap: c.cap,
        )
        #expect(abs(tolerance - c.target) < 1e-9)
    }

    @Test(arguments: 0 ..< 3)
    func `Recovery minutes match the pinned forecast`(index: Int) {
        let c = Self.cases[index]
        let minutes = ToleranceRecovery.minutes(
            toTolerance: c.target, layers: c.layers, occupancy: c.occupancy, occupancyCap: c.cap,
        )
        #expect(Self.close(minutes, c.recoveryMinutes))
    }

    @Test(arguments: 0 ..< 3)
    func `Tolerance after the pinned interval matches`(index: Int) {
        let c = Self.cases[index]
        let shift = ToleranceRecovery.shiftFactor(layers: c.layers, afterMinutes: c.minutes)
        let tolerance = 1 - PDModel.responseFraction(
            shiftFactor: shift, representativeOccupancy: c.occupancy, occupancyCap: c.cap,
        )
        #expect(Self.close(tolerance, c.toleranceAfter))
    }
}
