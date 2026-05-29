import ActivityKit
import BackgroundTasks
import Foundation
import os
import SwiftData

private let logger = Logger(subsystem: "dev.yumeji.piru", category: "LiveActivity")

/// Lightweight value snapshot of a DoseEntry, decoupled from SwiftData.
struct DoseSnapshot {
    let substance: String
    let amount: Double
    let unit: String
    let route: RouteOfAdministration
    let timestamp: Date

    init(entry: DoseEntry) {
        self.substance = entry.substance
        self.amount = entry.amount
        self.unit = entry.unit
        self.route = entry.route
        self.timestamp = entry.timestamp
    }

    init(substance: String, amount: Double, unit: String, route: RouteOfAdministration, timestamp: Date) {
        self.substance = substance
        self.amount = amount
        self.unit = unit
        self.route = route
        self.timestamp = timestamp
    }
}

/// Manages the iOS Live Activity (Lock Screen / Dynamic Island widget) lifecycle.
///
/// Singleton owned by the app process. Responsibilities:
/// - Starts, updates, and ends the `Activity<PiruActivityAttributes>` widget.
/// - Drives a 60-second periodic refresh `Timer` while a session is active so the
///   widget's timeline graph and "last updated" timestamp stay current.
/// - Recovers session state across cold launches by reading the running activity's
///   `contentState` (see `recoverEntriesFromActivity`).
/// - Posts a Darwin notification so other targets (the widget extension) can
///   re-render when content changes.
/// - Schedules background app refresh via `BGTaskScheduler` to keep the widget
///   alive when the app is suspended.
///
/// Session state (which substances are active) lives in `ActiveSessionManager`;
/// this manager only owns the widget itself.
@MainActor
@Observable
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    static let backgroundTaskIdentifier = "com.piru.app.live-activity-refresh"

    private var currentActivity: Activity<PiruActivityAttributes>?
    private var updateTimer: Timer?

    /// Whether a Live Activity is started *automatically* when a session begins.
    /// This gates only auto-start; the user can always start one manually from a
    /// day/entry detail view (see `startLiveActivity()`), regardless of this flag.
    var isAutoStartEnabled: Bool {
        UserDefaults.standard.object(forKey: "liveActivityEnabled") as? Bool ?? false
    }

    private init() {
        // Resume reference to any existing activity on app launch. We deliberately
        // do NOT end it when auto-start is disabled: a manually-started activity
        // must survive relaunch, and the auto-start preference governs *creation*,
        // not teardown — tearing down here is what used to wipe the live session.
        if let existing = Activity<PiruActivityAttributes>.activities.first {
            currentActivity = existing
        }
    }

    // MARK: - Recovery

    /// Recover active entries from a running Live Activity.
    /// Called by `ActiveSessionManager.recoverSession()` on app launch.
    /// Returns entries if a Live Activity is running, nil otherwise.
    func recoverEntriesFromActivity() -> [(snapshot: DoseSnapshot, duration: DurationProfile?, colorHex: String)]? {
        guard let existing = currentActivity else { return nil }
        return existing.content.state.activeSubstances.map { state in
            let snapshot = DoseSnapshot(
                substance: state.substanceName,
                amount: state.amount,
                unit: state.unit,
                route: RouteOfAdministration.from(string: state.route),
                timestamp: state.doseTimestamp
            )
            let duration = DurationProfile(fromState: state)
            return (snapshot: snapshot, duration: duration, colorHex: state.colorHex)
        }
    }

    // MARK: - Session Notifications

    /// Called by `ActiveSessionManager` when session entries change. A *running*
    /// activity (auto or manual) is always kept up to date; a new one is only
    /// started automatically when `isAutoStartEnabled` is set.
    func sessionDidChange() {
        let session = ActiveSessionManager.shared
        guard !session.activeEntries.isEmpty else {
            if currentActivity != nil { endSession() }
            return
        }

        let state = session.buildContentState(colorMap: session.cachedColorMap)

        if currentActivity != nil {
            startUpdateTimer()
            pushUpdate(ActivityContent(state: state, staleDate: staleDate()))
        } else if isAutoStartEnabled {
            startActivity(state: state)
        }
    }

    /// Manually start (or refresh) the Live Activity for the current session,
    /// independent of the automatic-start preference. Driven by the Start button
    /// in the day/entry detail views.
    func startLiveActivity() {
        let session = ActiveSessionManager.shared
        guard !session.activeEntries.isEmpty else { return }

        let state = session.buildContentState(colorMap: session.cachedColorMap)

        if currentActivity != nil {
            startUpdateTimer()
            pushUpdate(ActivityContent(state: state, staleDate: staleDate()))
        } else {
            startActivity(state: state)
        }
    }

    /// Called by `ActiveSessionManager` when all entries have been removed.
    func sessionCleared() {
        if currentActivity != nil {
            endSession()
        }
    }

    // MARK: - Public API

    /// End the Live Activity widget AND clear all active session entries.
    func endSession() {
        guard currentActivity != nil else { return }
        stopUpdateTimer()
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
        let state = ActiveSessionManager.shared.buildContentState(colorMap: [:])
        pushEnd(ActivityContent(state: state, staleDate: nil))
        self.currentActivity = nil
        ActiveSessionManager.shared.clearSession()
    }

    /// Hide the iOS Live Activity widget while keeping the underlying session
    /// (active substances) intact, so `startLiveActivity()` can re-show it.
    func hideLiveActivity() {
        guard currentActivity != nil else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
        let state = ActiveSessionManager.shared.buildContentState(colorMap: ActiveSessionManager.shared.cachedColorMap)
        pushEnd(ActivityContent(state: state, staleDate: nil))
        self.currentActivity = nil
        // Keep session alive — only the widget is stopped
    }

    /// Whether the iOS Live Activity (Lock Screen widget) is currently running.
    var isLiveActivityRunning: Bool {
        currentActivity != nil
    }

    // MARK: - Background Refresh

    func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        // Refresh whenever an activity is live (auto-started or manual), not just
        // when auto-start is enabled — otherwise a manual activity would go stale.
        guard currentActivity != nil else {
            task.setTaskCompleted(success: true)
            return
        }
        scheduleBackgroundRefresh()

        task.expirationHandler = { }

        let session = ActiveSessionManager.shared
        if !session.activeEntries.isEmpty {
            periodicUpdate()
        } else if let currentActivity {
            // App was relaunched — push a lightweight update to force widget re-render
            var state = currentActivity.content.state
            state.lastUpdated = .now
            let stale = state.activeSubstances.map {
                $0.doseTimestamp.addingTimeInterval($0.totalMinutes * 60)
            }.max()
            pushUpdate(ActivityContent(state: state, staleDate: stale))
        }

        task.setTaskCompleted(success: true)
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.error("Failed to schedule background refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Activity Updates

    /// Push a state update to the current live activity.
    /// `nonisolated(unsafe)` is required because ActivityKit's `Activity<>` is not declared `Sendable` in this SDK.
    private func pushUpdate(_ content: ActivityContent<PiruActivityAttributes.ContentState>) {
        guard let currentActivity else { return }
        nonisolated(unsafe) let activity = currentActivity
        Task { await activity.update(content) }
    }

    /// Push a final state and end the live activity.
    /// `nonisolated(unsafe)` is required because ActivityKit's `Activity<>` is not declared `Sendable` in this SDK.
    private func pushEnd(_ content: ActivityContent<PiruActivityAttributes.ContentState>) {
        guard let currentActivity else { return }
        nonisolated(unsafe) let activity = currentActivity
        Task { await activity.end(content, dismissalPolicy: .immediate) }
    }

    // MARK: - Private

    private func startUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop, so we're already on the main actor.
            MainActor.assumeIsolated { self?.periodicUpdate() }
        }
    }

    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func periodicUpdate() {
        let session = ActiveSessionManager.shared
        session.refresh()
        guard !session.activeEntries.isEmpty else {
            stopUpdateTimer()
            return
        }
        if currentActivity != nil {
            let state = session.buildContentState(colorMap: session.cachedColorMap)
            pushUpdate(ActivityContent(state: state, staleDate: staleDate()))
        }
    }

    private func startActivity(state: PiruActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let session = ActiveSessionManager.shared
        let earliest = session.activeEntries.map(\.snapshot.timestamp).min() ?? .now
        let attributes = PiruActivityAttributes(startTime: earliest)
        let content = ActivityContent(state: state, staleDate: staleDate())

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            startUpdateTimer()
            scheduleBackgroundRefresh()
        } catch {
            logger.error("Failed to start Live Activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func staleDate() -> Date? {
        let shortStale = Date.now.addingTimeInterval(5 * 60)
        let session = ActiveSessionManager.shared
        let substanceEnd = session.activeEntries.compactMap { item -> Date? in
            guard let duration = item.duration else { return nil }
            return item.snapshot.timestamp.addingTimeInterval(duration.estimatedTotalMinutes * 60)
        }.max()
        guard let end = substanceEnd else { return shortStale }
        return min(shortStale, end)
    }
}
