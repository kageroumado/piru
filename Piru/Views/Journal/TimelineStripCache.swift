import Foundation
import SwiftUI

/// The strip's launch cache: the last fully built `[TimelineDayLayout]`, on
/// disk, so a launch whose dose log has not changed since the previous run
/// paints the strip from a file read off the main actor instead of rebuilding
/// it (the build was ~640 ms of main-thread work at launch).
///
/// Validity is the whole key: the persistent store generation
/// (``DoseLogService/storeGeneration``), the entry count and newest timestamp
/// (catches writes from the widget, which cannot bump the generation), the
/// display preferences the slices were laid out for, the calendar day (the
/// newest slice's "today"/"Now" geometry), and the app build. A hit is also
/// age-limited, because remaining fractions and phase states decay with the
/// clock; past ``maxAge`` the strip is rebuilt as before.
nonisolated enum TimelineStripCache {
    nonisolated struct Key: Codable, Equatable, Sendable {
        /// Bumped when the encoded layout changes shape, so a file from an
        /// older build misses instead of half-decoding.
        var format = 3
        let storeGeneration: Int
        let entryCount: Int
        let newestTimestamp: Date?
        let preferences: String
        let day: Date
        let appBuild: String
    }

    private nonisolated struct Payload: Codable {
        let key: Key
        let builtAt: Date
        let days: [TimelineDayLayout]
    }

    /// How stale a hit may be. Bubble phase and remaining-fraction readouts
    /// are what age; half an hour keeps them within the resolution the strip
    /// shows them at.
    static let maxAge: TimeInterval = 30 * 60

    static func key(storeGeneration: Int, entryCount: Int, newestTimestamp: Date?, preferences: String, now: Date) -> Key {
        Key(
            storeGeneration: storeGeneration,
            entryCount: entryCount,
            newestTimestamp: newestTimestamp,
            preferences: preferences,
            day: Calendar.current.startOfDay(for: now),
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
        )
    }

    private static var url: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("timeline-strip.cache")
    }

    /// The cached layouts when they were built from exactly `key` within
    /// ``maxAge``, decoded off the main actor; `nil` otherwise.
    static func load(matching key: Key, now: Date = .now) async -> [TimelineDayLayout]? {
        guard let url else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> [TimelineDayLayout]? in
            guard let data = try? Data(contentsOf: url),
                  let payload = try? JSONDecoder().decode(Payload.self, from: data),
                  payload.key == key,
                  now.timeIntervalSince(payload.builtAt) < maxAge,
                  !payload.days.isEmpty
            else { return nil }
            return payload.days
        }.value
    }

    /// Write `days` as the cache for `key`, encoding off the main actor.
    static func save(_ days: [TimelineDayLayout], key: Key, now: Date = .now) {
        guard let url, !days.isEmpty else { return }
        let payload = Payload(key: key, builtAt: now, days: days)
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(payload) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Remove the cache, for a store restore or a wipe.
    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

extension Color {
    /// `#RRGGBB`, the form ``Color/init(hex:)`` reads back.
    nonisolated func cacheHex() -> String {
        let platformColor = PlatformColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(UIKit)
            platformColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #elseif canImport(AppKit)
            (platformColor.usingColorSpace(.sRGB) ?? platformColor).getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return String(format: "#%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}
