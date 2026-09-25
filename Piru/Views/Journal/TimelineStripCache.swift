import Foundation
import SwiftUI
import Synchronization

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
        var format = 6
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
            // A pinned present keys by its exact time: a strip built for one
            // stubbed "now" is wrong for any other.
            day: DebugClock.override ?? Calendar.current.startOfDay(for: now),
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
        )
    }

    /// The key and build time alone, beside the payload, so a miss is decided
    /// by reading a few hundred bytes instead of decoding the whole strip
    /// (12 MB for a multi-year log).
    private nonisolated struct Header: Codable {
        let key: Key
        let builtAt: Date
    }

    private static let writeEpoch = Mutex(0)

    static func clear() throws {
        try writeEpoch.withLock { epoch in
            epoch += 1
            for file in [url, headerURL].compactMap(\.self) where FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
        }
    }

    private static var url: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("timeline-strip.cache")
    }

    private static var headerURL: URL? {
        url.map { $0.deletingPathExtension().appendingPathExtension("key") }
    }

    /// The cached layouts when they were built from exactly `key` within
    /// ``maxAge``, decoded off the main actor; `nil` otherwise.
    static func load(matching key: Key, now: Date = .now) async -> [TimelineDayLayout]? {
        guard let url, let headerURL else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> [TimelineDayLayout]? in
            guard let headerData = try? Data(contentsOf: headerURL),
                  let header = try? JSONDecoder().decode(Header.self, from: headerData),
                  header.key == key,
                  now.timeIntervalSince(header.builtAt) < maxAge,
                  let data = try? Data(contentsOf: url),
                  let payload = try? JSONDecoder().decode(Payload.self, from: data),
                  payload.key == key,
                  !payload.days.isEmpty
            else { return nil }
            return payload.days
        }.value
    }

    /// Write `days` as the cache for `key`, encoding off the main actor. The
    /// header is written after the payload, so a reader never trusts a key
    /// whose payload is still being replaced.
    static func save(_ days: [TimelineDayLayout], key: Key, now: Date = .now) {
        guard let url, let headerURL, !days.isEmpty else { return }
        let payload = Payload(key: key, builtAt: now, days: days)
        let epoch = writeEpoch.withLock { $0 }
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(payload),
                  let headerData = try? JSONEncoder().encode(Header(key: key, builtAt: now)) else { return }
            writeEpoch.withLock { current in
                guard current == epoch,
                      key.storeGeneration == UserDefaults(suiteName: "group.dev.yumeji.piru")?.integer(forKey: "doseLogStoreGeneration") else { return }
                try? data.write(to: url, options: .atomic)
                try? headerData.write(to: headerURL, options: .atomic)
            }
        }
    }
}

extension Color {
    /// The color as Display P3 components, the form a layout cache stores.
    /// Resolved in a default environment: cached colors are substance tints
    /// and shifts of them, which carry no appearance variants.
    nonisolated func cacheTint() -> P3Color {
        let resolved = resolve(in: EnvironmentValues())
        return Oklch(
            linearRed: Double(resolved.linearRed), green: Double(resolved.linearGreen), blue: Double(resolved.linearBlue),
        ).displayP3
    }
}
