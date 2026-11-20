import Foundation

/// Dose-stepper increments shared by the tray editor and the inline search
/// result entry.
enum DoseStepping {
    /// ≈10% of the reference dose, snapped to a 1 / 2.5 / 5 × 10ᵏ series.
    static func niceStep(for reference: Double) -> Double {
        guard reference > 0 else { return 1 }
        let raw = reference / 10
        let magnitude = pow(10, floor(log10(raw)))
        let normalized = raw / magnitude
        let snapped: Double = normalized < 1.75 ? 1 : normalized < 3.75 ? 2.5 : normalized < 7.5 ? 5 : 10
        return snapped * magnitude
    }

    /// The stepper increment: `niceStep` off the library reference dose when one is
    /// known, else a magnitude table on the amount itself. Shared by the tray editor
    /// and the watch quick-log so both nudge in the same increments.
    static func step(referenceDose: Double?, amount: Double) -> Double {
        if let referenceDose {
            return niceStep(for: referenceDose)
        }
        return switch amount {
        case ..<2: 0.25
        case ..<10: 1
        case ..<100: 5
        case ..<1_000: 25
        default: 100
        }
    }
}
