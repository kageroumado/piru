import ActivityKit
import BackgroundTasks
import Foundation
import SwiftData

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
/// Session state (which substances are active) lives in `ActiveSessionManager`.
/// This manager only handles starting, updating, and ending the Live Activity widget.
@MainActor
@Observable
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    static let backgroundTaskIdentifier = "com.piru.app.live-activity-refresh"

    private var currentActivity: Activity<PiruActivityAttributes>?
    private var updateTimer: Timer?

    /// Whether live activities are enabled by the user in Settings.
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "liveActivityEnabled") as? Bool ?? false
    }

    private init() {
        // Resume reference to any existing activity on app launch
        if let existing = Activity<PiruActivityAttributes>.activities.first {
            currentActivity = existing
        }

        // If live activities are disabled, end any recovered activity
        if !isEnabled, currentActivity != nil {
            endActivity()
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

    /// Called by `ActiveSessionManager` when session entries change.
    /// Starts or updates the Live Activity if enabled.
    func sessionDidChange() {
        guard isEnabled else { return }

        let session = ActiveSessionManager.shared
        guard !session.activeEntries.isEmpty else {
            endActivity()
            return
        }

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
            endActivity()
        }
    }

    // MARK: - Public API

    /// End the Live Activity and clear the session.
    func endActivity() {
        guard currentActivity != nil else { return }
        stopUpdateTimer()
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
        let state = ActiveSessionManager.shared.buildContentState(colorMap: [:])
        pushEnd(ActivityContent(state: state, staleDate: nil))
        self.currentActivity = nil
        ActiveSessionManager.shared.clearSession()
    }

    /// Stop the iOS Live Activity widget but keep tracking active substances.
    func stopLiveActivity() {
        guard currentActivity != nil else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
        let state = ActiveSessionManager.shared.buildContentState(colorMap: ActiveSessionManager.shared.cachedColorMap)
        pushEnd(ActivityContent(state: state, staleDate: nil))
        self.currentActivity = nil
        // Keep session alive — only the widget is stopped
    }

    /// Restart the iOS Live Activity from currently tracked entries.
    func restartLiveActivity() {
        guard isEnabled else { return }
        ActiveSessionManager.shared.refresh()
        let session = ActiveSessionManager.shared
        guard !session.activeEntries.isEmpty, currentActivity == nil else { return }
        let state = session.buildContentState(colorMap: session.cachedColorMap)
        startActivity(state: state)
    }

    /// Whether the iOS Live Activity (Lock Screen widget) is currently running.
    var isLiveActivityRunning: Bool {
        currentActivity != nil
    }

    // MARK: - Background Refresh

    func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        guard isEnabled else {
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
            print("Failed to schedule background refresh: \(error)")
        }
    }

    // MARK: - Activity Updates

    /// Push a state update to the current live activity.
    /// Centralises the `nonisolated(unsafe)` workaround for `Activity` not being `Sendable`.
    private func pushUpdate(_ content: ActivityContent<PiruActivityAttributes.ContentState>) {
        guard let currentActivity else { return }
        nonisolated(unsafe) let activity = currentActivity
        Task { await activity.update(content) }
    }

    private func pushEnd(_ content: ActivityContent<PiruActivityAttributes.ContentState>) {
        guard let currentActivity else { return }
        nonisolated(unsafe) let activity = currentActivity
        Task { await activity.end(content, dismissalPolicy: .immediate) }
    }

    // MARK: - Private

    private func startUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.periodicUpdate()
            }
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
            print("Failed to start Live Activity: \(error)")
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
