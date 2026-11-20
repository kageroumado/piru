import Foundation

/// The "if you stop now" recovery math behind the Tolerance tool's curves and axis. A class's
/// tolerance is a right-shift `S = exp(Σ sₗ)` over its recovery layers (acute, adaptive, deep,
/// synthesis); with no further dosing each layer decays on its own time constant, and the gauge
/// reads `S` through the saturating ``PDModel/responseFraction(shiftFactor:representativeOccupancy:occupancyCap:)``.
enum ToleranceRecovery {
    /// One recovery layer: its current ln-shift contribution `s` and its decay time constant `tau`, in minutes.
    typealias Layer = (s: Double, tau: Double)

    /// The total right-shift `S(t) = exp(Σ sₗ·e^(−t/τₗ))` after `minutes` with no further dosing,
    /// summed in layer order.
    nonisolated static func shiftFactor(layers: [Layer], afterMinutes minutes: Double) -> Double {
        exp(layers.reduce(0) { $0 + $1.s * exp(-minutes / $1.tau) })
    }

    /// The shift `S` at which tolerance reads `target` (∈ [0, 1]) on the gauge. Tolerance is
    /// `1 − response` and `response = (r + 1) / (r + S)` with `r = O / (1 − O)`, so this solves
    /// `S = (r + 1) / (1 − target) − r`, never below 1. `occupancyCap` is the class's
    /// mechanism-aware cap, the same one the gauge applies, so the axis and the curve agree.
    nonisolated static func targetShift(toTolerance target: Double, occupancy: Double, occupancyCap: Double?) -> Double {
        // The cap must stay strictly below 1: occupancy == 1 makes the ratio
        // divide by zero and floods the axis math with infinity.
        let cap = min(occupancyCap ?? 0.999_999, 0.999_999)
        let clamped = min(cap, max(0, occupancy))
        let ratio = clamped / (1 - clamped)
        let responseTarget = max(0.000_001, 1 - target)
        return max(1, (ratio + 1) / responseTarget - ratio)
    }

    /// Minutes for tolerance to decay to `target` if dosing stops now: `0` when it already reads at or
    /// below `target`, `nil` when ``PDModel/shiftDecayMinutes(layers:toShift:)`` has no answer.
    nonisolated static func minutes(
        toTolerance target: Double, layers: [Layer], occupancy: Double, occupancyCap: Double?,
    ) -> Double? {
        let shift = targetShift(toTolerance: target, occupancy: occupancy, occupancyCap: occupancyCap)
        return PDModel.shiftDecayMinutes(layers: layers, toShift: shift)
    }
}
