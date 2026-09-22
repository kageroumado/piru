import Foundation

/// The clock the vertical timeline reads, so a DEBUG launch can pin "now".
///
/// `-piruNow 9:41` makes today 9:41 the present: the Now tag, the strip's live
/// edge, each dose's elapsed time and the `week` persona's seed all agree with
/// a status bar overridden to the same time. A full ISO 8601 date is accepted
/// too. Release builds always read the wall clock.
nonisolated enum DebugClock {
    /// The pinned present, or `nil` for the wall clock.
    static let override: Date? = {
        #if DEBUG
            guard let raw = UserDefaults.standard.string(forKey: "piruNow") else { return nil }
            if let date = ISO8601DateFormatter().date(from: raw) { return date }
            let parts = raw.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { return nil }
            return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: .now)
        #else
            return nil
        #endif
    }()

    static var now: Date {
        override ?? .now
    }
}
