import Foundation

nonisolated extension Double {
    /// Format a dose value with sensible rounding — no false precision
    var doseFormatted: String {
        let abs = Swift.abs(self)
        if abs == 0 { return "0" }
        if abs >= 100 { return String(format: "%.0f", self) } // 100+ → "250"
        if abs >= 10 { return trimZeros(format: "%.1f") } // 10–99 → "44.7"
        if abs >= 1 { return trimZeros(format: "%.2f") } // 1–9 → "3.34"
        return trimZeros(format: "%.2f") // <1 → "0.68"
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

extension TimeInterval {
    /// Format a duration as "2h 8m" / "3h" / "45m". Shared by the session
    /// accessory and the entry-detail hero so the "in / left" status reads
    /// identically across the app. Negative intervals clamp to zero.
    var durationHM: String {
        let totalMinutes = max(0, Int(self / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0, minutes > 0 {
            return String(localized: "\(hours)h \(minutes)m")
        } else if hours > 0 {
            return String(localized: "\(hours)h")
        } else {
            return String(localized: "\(minutes)m")
        }
    }
}
