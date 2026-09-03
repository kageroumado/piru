#if os(iOS)
    import ActivityKit
    import BackgroundTasks
#endif
import Foundation
import os
import SwiftData

private let logger = Logger(subsystem: "dev.yumeji.piru", category: "LiveActivity")

/// Lightweight value snapshot of a DoseEntry, decoupled from SwiftData.
struct DoseSnapshot {
    /// The source entry's stable ``DoseEntry/id``, used by
    /// `ActiveSessionManager` to match a snapshot back to its entry exactly.
    /// `nil` only for snapshots rebuilt from a running Live Activity
    /// (``LiveActivityManager/recoverEntriesFromActivity()``) —
    /// `PiruActivityAttributes` deliberately carries no entry references, so
    /// those snapshots fall back to substance + timestamp matching.
    let id: UUID?
    let substance: String
    let amount: Double
    let unit: String
    let route: RouteOfAdministration
    let timestamp: Date
    /// What to call this dose (``DoseTitle``), resolved once here. The Live
    /// Activity and the tab-bar accessory render off the snapshot rather than the
    /// entry, so without this they show the raw canonical string — a dose logged
    /// as Concerta reading "Methylphenidate" on the Lock Screen.
    let title: String

    init(entry: DoseEntry) {
        self.id = entry.id
        self.substance = entry.substance
        self.amount = entry.amount
        self.unit = entry.unit
        self.route = entry.route
        self.timestamp = entry.timestamp
        self.title = DoseTitle.resolve(for: entry)
    }

    init(
        id: UUID? = nil,
        substance: String,
        amount: Double,
        unit: String,
        route: RouteOfAdministration,
        timestamp: Date,
        title: String? = nil,
    ) {
        self.id = id
        self.substance = substance
        self.amount = amount
        self.unit = unit
        self.route = route
        self.timestamp = timestamp
        // Recovered from a running Live Activity, which carries no entry
        // reference — the substance string is all there is.
        self.title = title ?? substance
    }
}

#if os(iOS)
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
            // not teardown. Never tear down the activity here: it wipes the live
            // session out from under the user.
            //
            // Only a *running* activity counts. ActivityKit keeps `.ended` and
            // `.dismissed` activities in `activities` until the user clears them (up
            // to 4 h), and an ended activity's `content.state` is frozen at the moment
            // it ended — `update()` on it is a no-op, so it can never catch up.
            // Adopting one would make `recoverSession` resurrect that frozen dose list
            // on every cold launch, silently replacing the real session. `.stale` is
            // kept: it's still on screen and still updatable, just past its `staleDate`.
            currentActivity = Activity<PiruActivityAttributes>.activities.first {
                $0.activityState == .active || $0.activityState == .stale
            }
        }

        // MARK: - Recovery

        /// Recover active entries from a running Live Activity.
        /// Called by `ActiveSessionManager.recoverSession()` on app launch.
        /// Returns entries only when an activity is genuinely running and carries
        /// substances; `nil` otherwise, so the caller falls through to SwiftData.
        ///
        /// The `activityState` re-check is not redundant with `init`'s: the activity
        /// can end (user dismissal, system expiry) while the process is alive, and
        /// `currentActivity` is only cleared on the paths *we* drive.
        ///
        /// **Do not add an unmodeled-form check here, and do not thread the flag
        /// through `PiruActivityAttributes` to make one possible.** There is no
        /// `DoseEntry` at this point, so the check looks missing — but it has already
        /// run, one layer up and permanently. A dose whose form the app declines to
        /// model resolves a `nil` duration
        /// (``ActiveSessionManager/resolveDuration(substance:route:namesUnmodeledForm:)``),
        /// and `pruneCompleted` drops every `nil`-duration entry from `activeEntries`
        /// as a *membership* rule rather than an expiry one. `buildSubstanceStates`
        /// maps over what survives, so an `ActiveSubstanceState` can only exist for a
        /// dose the guard already let through, and the phase boundaries recovered
        /// below are that same permitted profile read back.
        ///
        /// The one unmodeled form that does reach here is a named ER product with an
        /// authored `product_durations` envelope, which is modeled after all — and it
        /// recovers its own envelope, not the base ladder's.
        func recoverEntriesFromActivity() -> [(snapshot: DoseSnapshot, duration: DurationProfile?, colorHex: String)]? {
            guard let existing = currentActivity,
                  existing.activityState == .active || existing.activityState == .stale,
                  !existing.content.state.activeSubstances.isEmpty
            else { return nil }
            return existing.content.state.activeSubstances.map { state in
                let snapshot = DoseSnapshot(
                    substance: state.substanceName,
                    amount: state.amount,
                    unit: state.unit,
                    route: RouteOfAdministration.from(string: state.route),
                    timestamp: state.doseTimestamp,
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

            // Complete the BGTask only after the activity update has actually
            // landed — completing while a fire-and-forget update is still in
            // flight lets iOS suspend the process before the widget refreshes.
            let work = Task {
                await self.performBackgroundUpdate()
                task.setTaskCompleted(success: !Task.isCancelled)
            }
            task.expirationHandler = { @Sendable in
                work.cancel()
            }
        }

        /// Awaited variant of the refresh push, driven by `handleBackgroundRefresh`.
        private func performBackgroundUpdate() async {
            let session = ActiveSessionManager.shared
            if !session.activeEntries.isEmpty {
                session.refresh()
                guard !session.activeEntries.isEmpty else {
                    stopUpdateTimer()
                    return
                }
                guard currentActivity != nil else { return }
                let state = session.buildContentState(colorMap: session.cachedColorMap)
                await pushUpdateAwaiting(ActivityContent(state: state, staleDate: staleDate()))
            } else if let currentActivity {
                // App was relaunched — push a lightweight update to force widget re-render
                var state = currentActivity.content.state
                state.lastUpdated = .now
                let stale = state.activeSubstances.map {
                    $0.doseTimestamp.addingTimeInterval($0.totalMinutes * 60)
                }.max()
                await pushUpdateAwaiting(ActivityContent(state: state, staleDate: stale))
            }
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

        /// Awaitable counterpart of ``pushUpdate(_:)`` for callers that must not
        /// return until the update has landed (the BGTask refresh path).
        private func pushUpdateAwaiting(_ content: ActivityContent<PiruActivityAttributes.ContentState>) async {
            guard let currentActivity else { return }
            nonisolated(unsafe) let activity = currentActivity
            await activity.update(content)
        }

        /// Push a final state and end the live activity.
        /// `nonisolated(unsafe)` is required because ActivityKit's `Activity<>` is not declared `Sendable` in this SDK.
        private func pushEnd(_ content: ActivityContent<PiruActivityAttributes.ContentState>) {
            guard let currentActivity else { return }
            nonisolated(unsafe) let activity = currentActivity
            Task { await activity.end(content, dismissalPolicy: .immediate) }
        }

        // MARK: - Private

        /// Schedule the next foreground push for when the display will actually
        /// change, instead of every 60 s regardless.
        ///
        /// A flat one-minute tick spent the (finite, undocumented) ActivityKit update
        /// budget on repaints that mostly showed the same phase and a near-identical
        /// curve — and it is the budget running out that produces the "sometimes it
        /// just doesn't update" reports. Firing on the next phase boundary means an
        /// hour-long quiet stretch costs one update instead of sixty, leaving budget
        /// for the moments that matter. Clamped so a boundary seconds away doesn't
        /// spin and a distant one still refreshes periodically.
        private func startUpdateTimer() {
            updateTimer?.invalidate()
            let delay = min(max(nextChangeInterval(), Self.minimumTick), Self.maximumTick)
            updateTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                // Timer fires on the main run loop, so we're already on the main actor.
                MainActor.assumeIsolated { self?.periodicUpdate() }
            }
        }

        /// Seconds until the next phase boundary across every active substance, or
        /// ``maximumTick`` when nothing is pending.
        private func nextChangeInterval() -> TimeInterval {
            let now = Date.now
            let next = ActiveSessionManager.shared.activeEntries.flatMap { item -> [Date] in
                guard let duration = item.duration else { return [] }
                let start = item.snapshot.timestamp
                let bounds = duration.phaseBoundaries
                return [
                    bounds.onsetEnd, bounds.comeupEnd, bounds.peakEnd,
                    bounds.offsetEnd, bounds.afterglowEnd,
                ].map { start.addingTimeInterval($0 * 60) }
            }
            .filter { $0 > now }
            .min()
            guard let next else { return Self.maximumTick }
            return next.timeIntervalSince(now)
        }

        private static let minimumTick: TimeInterval = 30
        private static let maximumTick: TimeInterval = 15 * 60

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
            // The tick is one-shot; re-arm it for the *next* boundary.
            startUpdateTimer()
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
                    pushType: nil,
                )
                startUpdateTimer()
                scheduleBackgroundRefresh()
            } catch {
                logger.error("Failed to start Live Activity: \(error.localizedDescription, privacy: .public)")
            }
        }

        /// When the pushed content should be treated as out of date.
        ///
        /// ActivityKit gives an app no way to schedule an arbitrary future re-render:
        /// the view is redrawn on a content update, and once more when it goes stale.
        /// That single stale re-render is the only scheduled repaint available, so it
        /// is spent where the display actually changes — **the next phase boundary any
        /// active substance crosses** — rather than on a flat five-minute tick that
        /// usually lands mid-phase and repaints nothing new.
        ///
        /// Bounded on both sides: never sooner than ``minimumStale`` (so a dose logged
        /// seconds before a boundary can't burn the budget on an instant repaint),
        /// never later than ``maximumStale`` (so a long quiet stretch still refreshes
        /// eventually), and never past the session's own end.
        private func staleDate() -> Date? {
            let now = Date.now
            let session = ActiveSessionManager.shared

            let sessionEnd = session.activeEntries.compactMap { item -> Date? in
                guard let duration = item.duration else { return nil }
                return item.snapshot.timestamp.addingTimeInterval(duration.estimatedTotalMinutes * 60)
            }.max()

            // Every phase boundary still ahead of us, across every active substance.
            let nextBoundary = session.activeEntries.flatMap { item -> [Date] in
                guard let duration = item.duration else { return [] }
                let start = item.snapshot.timestamp
                let bounds = duration.phaseBoundaries
                return [
                    bounds.onsetEnd, bounds.comeupEnd, bounds.peakEnd,
                    bounds.offsetEnd, bounds.afterglowEnd,
                ].map { start.addingTimeInterval($0 * 60) }
            }
            .filter { $0 > now }
            .min()

            let target = nextBoundary ?? now.addingTimeInterval(Self.maximumStale)
            let clamped = min(
                max(target, now.addingTimeInterval(Self.minimumStale)),
                now.addingTimeInterval(Self.maximumStale),
            )
            guard let sessionEnd else { return clamped }
            return min(clamped, sessionEnd)
        }

        /// Floor on ``staleDate`` — a boundary closer than this isn't worth a repaint.
        private static let minimumStale: TimeInterval = 60
        /// Ceiling on ``staleDate`` — the display should never claim freshness for
        /// longer than this, however quiet the session.
        private static let maximumStale: TimeInterval = 30 * 60
    }
#else
    @MainActor
    @Observable
    final class LiveActivityManager {
        static let shared = LiveActivityManager()
        static let backgroundTaskIdentifier = "com.piru.app.live-activity-refresh"

        var isAutoStartEnabled: Bool {
            false
        }
        var isLiveActivityRunning: Bool {
            false
        }

        func sessionDidChange() {}
        func sessionCleared() {}
        func startLiveActivity() {}
        func hideLiveActivity() {}
        func recoverEntriesFromActivity() -> [(snapshot: DoseSnapshot, duration: DurationProfile?, colorHex: String)]? {
            nil
        }
        func handleBackgroundRefresh(_: Any) {}
    }
#endif
