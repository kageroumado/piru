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

    /// `doseFormatted` with thousands separators — for stock figures, which run
    /// large (a 50,000 mg jar, 124,000 IU). Same rounding tiers as
    /// ``doseFormatted`` so it reads consistently, just grouped.
    var inventoryFormatted: String {
        let absV = Swift.abs(self)
        let fraction = absV >= 100 ? 0 : (absV >= 10 ? 1 : 2)
        return formatted(.number.precision(.fractionLength(0 ... fraction)).grouping(.automatic))
    }

    private func trimZeros(format: String) -> String {
        let s = String(format: format, self)
        guard s.contains(".") else { return s }
        // Manual trailing-zero (then trailing-dot) trim — avoids compiling an
        // NSRegularExpression on every call. doseFormatted is hit per chip label
        // and inside hot equality paths, so the regex showed up in profiles.
        var end = s.endIndex
        while end > s.startIndex, s[s.index(before: end)] == "0" {
            end = s.index(before: end)
        }
        if end > s.startIndex, s[s.index(before: end)] == "." {
            end = s.index(before: end)
        }
        return String(s[s.startIndex ..< end])
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
