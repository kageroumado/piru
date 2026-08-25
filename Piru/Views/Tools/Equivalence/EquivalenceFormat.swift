import Foundation

/// Shared readout formatting for the equivalence tools.
enum EquivalenceFormat {
    /// Two significant figures below 10, integer at or above — a dose-scale
    /// readout (0.25 mg … 30 mg) without implying false precision.
    static func mg(_ value: Double) -> String {
        if value <= 0 { return "0" }
        if value >= 10 { return String(Int(value.rounded())) }
        if value >= 1 { return String(format: "%.1f", value) }
        return String(format: "%.2g", value)
    }
}
