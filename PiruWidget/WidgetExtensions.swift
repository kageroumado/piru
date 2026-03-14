import Foundation

extension Double {
    var doseFormatted: String {
        let abs = Swift.abs(self)
        if abs == 0 { return "0" }
        if abs >= 100 { return String(format: "%.0f", self) }
        if abs >= 10 { return trimZeros(format: "%.1f") }
        if abs >= 1 { return trimZeros(format: "%.2f") }
        return trimZeros(format: "%.2f")
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
