import Foundation
import GRDB
import os
import Synchronization
#if canImport(UIKit)
    import UIKit
#endif

/// Keeps GRDB connections from holding a file lock at the moment iOS suspends
/// the process, which RunningBoard punishes with a `0xdead10cc` kill — the
/// dominant crash signature across TestFlight builds 21 through 52.
///
/// Every GRDB connection that can take a lock is opened with
/// `observesSuspensionNotifications`; this type posts GRDB's suspend and resume
/// notifications at the lifecycle edges. A suspended connection interrupts the
/// statement in flight, releases its lock, and refuses new locks until resumed.
/// The user-prefs store runs in WAL mode, so its reads keep working while
/// suspended; only writes throw, and those are user-driven foreground work.
///
/// The substance databases need none of this: they are opened `immutable`, so
/// SQLite never locks them at all (see `SubstanceStore.immutableSQLiteURI(for:)`).
///
/// Background execution that reads or writes a suspended connection wraps
/// itself in ``withResumed(_:)`` — the BGTask refresh of the Live Activity does —
/// so the work runs unsuspended and the connection is back to suspended before
/// the task completes and the process is parked.
nonisolated enum DatabaseSuspension {
    private static let state = Mutex(false)

    /// Whether the last posted notification was a suspend.
    static var isSuspended: Bool {
        state.withLock { $0 }
    }

    /// Observe the app's background/foreground transitions. Call once at launch.
    static func install() {
        #if canImport(UIKit) && !os(watchOS)
            let center = NotificationCenter.default
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil,
            ) { _ in suspend() }
            center.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil,
            ) { _ in resume() }
        #endif
    }

    /// Release and refuse database locks until ``resume()``.
    static func suspend() {
        let changed = state.withLock { suspended -> Bool in
            guard !suspended else { return false }
            suspended = true
            return true
        }
        guard changed else { return }
        NotificationCenter.default.post(name: Database.suspendNotification, object: nil)
        Logger.databaseSuspension.debug("Databases suspended")
    }

    /// Allow database locks again.
    static func resume() {
        let changed = state.withLock { suspended -> Bool in
            guard suspended else { return false }
            suspended = false
            return true
        }
        guard changed else { return }
        NotificationCenter.default.post(name: Database.resumeNotification, object: nil)
        Logger.databaseSuspension.debug("Databases resumed")
    }

    /// Run background work with the databases resumed, then restore the prior
    /// state. A BGTask handler that lands while the app is suspended in the
    /// background reads through this so its queries run instead of throwing, and
    /// the locks are released again before the task reports completion.
    static func withResumed<T>(_ body: () async throws -> T) async rethrows -> T {
        let wasSuspended = isSuspended
        if wasSuspended { resume() }
        defer { if wasSuspended { suspend() } }
        return try await body()
    }
}
