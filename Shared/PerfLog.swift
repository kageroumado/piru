import Foundation
import os

/// Lightweight main-thread timing for the performance pass. Active only in
/// `DEBUG` builds (zero-cost no-ops in release). Logs at `.notice` level
/// (persisted by `log show`, unlike `.info`) to a dedicated category, so it can
/// be read from the simulator with:
///
///     xcrun simctl spawn booted log show --last 2m \
///         --predicate 'subsystem == "dev.yumeji.piru" && category == "perf"'
///
/// Drive the app with `axe` while it runs, then read the log — the working
/// substitute for `xctrace record`, which can't capture the iOS Simulator via
/// CLI on this toolchain.
enum PerfLog {
    #if DEBUG
    nonisolated static let log = Logger(subsystem: "dev.yumeji.piru", category: "perf")
    #endif

    /// Log a pre-formatted message (keeps `os` format-interpolation out of callers).
    @inline(__always)
    nonisolated static func note(_ message: String) {
        #if DEBUG
        log.notice("\(message, privacy: .public)")
        #endif
    }

    /// Time `body`, logging elapsed milliseconds when it exceeds `thresholdMs`.
    @inline(__always)
    @discardableResult
    nonisolated static func time<T>(_ label: String, thresholdMs: Double = 1.0, _ body: () -> T) -> T {
        #if DEBUG
        let t0 = CFAbsoluteTimeGetCurrent()
        let result = body()
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        if ms >= thresholdMs {
            log.notice("\(label, privacy: .public) \(ms, format: .fixed(precision: 1), privacy: .public)ms")
        }
        return result
        #else
        return body()
        #endif
    }
}
