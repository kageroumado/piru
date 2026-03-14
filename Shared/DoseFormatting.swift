import Foundation

extension Double {
    /// Format a dose value with sensible rounding — no false precision
    var doseFormatted: String {
        let abs = Swift.abs(self)
        if abs == 0 { return "0" }
        if abs >= 100 { return String(format: "%.0f", self) }       // 100+ → "250"
        if abs >= 10 { return trimZeros(format: "%.1f") }           // 10–99 → "44.7"
        if abs >= 1 { return trimZeros(format: "%.2f") }            // 1–9 → "3.34"
        return trimZeros(format: "%.2f")                            // <1 → "0.68"
    }

    private func trimZeros(format: String) -> String {
        let s = String(format: format, self)
        if s.contains(".") {
            let trimmed = s.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            return trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed
        }
        return s
    }
}
