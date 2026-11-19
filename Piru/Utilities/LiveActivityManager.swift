#if os(iOS)
    import ActivityKit
    import BackgroundTasks
#endif
import Foundation
import os
import SwiftData

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
    /// - Drives a phase-boundary-aligned refresh `Timer` while a session is active so
    ///   the widget's phase label and countdown target stay current. The graph's
    ///   now rail, the rings and the Elapsed clock are time-driven views that
    ///   advance without a push.
    /// - Recovers session state across cold launches by reading the running activity's
    ///   `contentState` (see `recoverEntriesFromActivity`), and re-arms every update
    ///   source for an adopted activity (see `resumeIfRunning`).
    /// - Posts a Darwin notification so other targets (the widget extension) can
    ///   re-render when content changes.
    /// - Schedules background app refresh via `BGTaskScheduler` to keep the widget
    ///   alive when the app is suspended, and to end it once its doses run out.
    /// - Takes cards with nothing left to show off the Lock Screen on every wake
    ///   (see `endFinishedActivities(canReplace:releasingDismissed:now:)`).
    ///
    /// Nothing ends an activity, or changes its phase label, while the app is
    /// suspended and no refresh is granted: ActivityKit offers a locally driven
    /// activity no scheduled update or end; only a push server could send one.
    /// Its stale date is the one change that lands without the app, so it is
    /// set at the last dose's end, where the extension collapses the card to a
    /// single "Session complete" row.
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
        /// Ends sent to ActivityKit and not yet confirmed. The background
        /// refresh awaits them before completing its task, or iOS can suspend
        /// the process with the activity still on the Lock Screen.
        @ObservationIgnored private var pendingEnds: [Task<Void, Never>] = []

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
        func recoverEntriesFromActivity() -> [(snapshot: DoseSnapshot, duration: DurationProfile?, tint: P3Color)]? {
            guard let existing = currentActivity,
                  existing.activityState == .active || existing.activityState == .stale,
                  !existing.content.state.activeSubstances.isEmpty
            else { return nil }
            return existing.content.state.activeSubstances.map { state in
                let snapshot = DoseSnapshot(
                    substance: state.canonicalName,
                    amount: state.amount,
                    unit: state.unit,
                    route: RouteOfAdministration.from(string: state.route),
                    timestamp: state.doseTimestamp,
                )
                let duration = DurationProfile(fromState: state)
                return (snapshot: snapshot, duration: duration, tint: state.tint)
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

            let replacesCapped = endFinishedActivities(canReplace: true)
            let state = session.buildContentState(colorMap: session.cachedColorMap)

            if currentActivity != nil {
                startUpdateTimer()
                scheduleBackgroundRefresh()
                pushUpdate(ActivityContent(state: state, staleDate: Self.staleDate(for: state)))
            } else if isAutoStartEnabled || replacesCapped {
                startActivity(state: state)
            }
        }

        /// Re-arm every update source for an activity that is already on the
        /// Lock Screen: a fresh push (so the phase label and the countdown's
        /// target boundary are current, and ``staleDate(for:)`` is measured from
        /// now), the foreground tick, and the background refresh.
        ///
        /// Called on cold launch after session recovery and whenever the app
        /// returns to the foreground. Without it an adopted activity has no
        /// update source at all — `init` only takes the reference — so the
        /// widget keeps the label and boundary of its last push until the user
        /// logs another dose.
        ///
        /// It is also where a card left behind while the app was suspended
        /// comes off the Lock Screen: one whose doses all ran out, one
        /// ActivityKit ended, or one this process no longer tracks
        /// (``endFinishedActivities(canReplace:releasingDismissed:now:)``).
        ///
        /// Only a running activity is refreshed. A new one is started only to
        /// replace an activity ActivityKit ended at its eight-hour cap
        /// mid-session, so a widget the user dismissed stays dismissed across a
        /// relaunch.
        func resumeIfRunning() {
            let session = ActiveSessionManager.shared
            session.refresh()
            let replacesCapped = endFinishedActivities(canReplace: true)
            guard !session.activeEntries.isEmpty else {
                stopUpdateTimer()
                return
            }
            let state = session.buildContentState(colorMap: session.cachedColorMap)
            if replacesCapped, currentActivity == nil {
                startActivity(state: state)
                return
            }
            guard currentActivity != nil else { return }
            startUpdateTimer()
            scheduleBackgroundRefresh()
            pushUpdate(ActivityContent(state: state, staleDate: Self.staleDate(for: state)))
        }

        /// Manually start (or refresh) the Live Activity for the current session,
        /// independent of the automatic-start preference. Driven by the Start button
        /// in the day/entry detail views.
        func startLiveActivity() {
            let session = ActiveSessionManager.shared
            guard !session.activeEntries.isEmpty else { return }

            // A held activity the user dismissed, or ActivityKit ended, takes
            // no updates; let it go so the button starts a fresh one.
            endFinishedActivities(canReplace: true, releasingDismissed: true)
            let state = session.buildContentState(colorMap: session.cachedColorMap)

            if currentActivity != nil {
                startUpdateTimer()
                pushUpdate(ActivityContent(state: state, staleDate: Self.staleDate(for: state)))
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

        /// End every Piru activity as a profile switch begins: the activity
        /// shows the previous person's doses, and nothing would update it
        /// again. The next profile's session starts its own the usual way.
        func endForProfileSwitch() {
            stopUpdateTimer()
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
            currentActivity = nil
            for activity in Activity<PiruActivityAttributes>.activities {
                nonisolated(unsafe) let ending = activity
                pendingEnds.append(Task { await ending.end(nil, dismissalPolicy: .immediate) })
            }
        }

        func deleteJournalActivities() async {
            stopUpdateTimer()
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
            currentActivity = nil
            for activity in Activity<PiruActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
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
            if currentActivity != nil {
                scheduleBackgroundRefresh()
            }

            // Complete the BGTask only after the activity update or end has
            // actually landed — completing while a fire-and-forget call is still
            // in flight lets iOS suspend the process before the Lock Screen
            // changes. The refresh resolves substances, so it runs with the
            // databases resumed and hands the locks back before the task completes.
            let work = Task {
                await DatabaseSuspension.withResumed {
                    await self.performBackgroundUpdate()
                }
                task.setTaskCompleted(success: !Task.isCancelled)
            }
            task.expirationHandler = { @Sendable in
                work.cancel()
            }
        }

        /// The background refresh: shrink or end the session by what has run
        /// out, repaint what is left, and take finished cards off the Lock Screen.
        ///
        /// iOS often launches the app into the background for this task with no
        /// session in memory: recovery runs from the root view's launch task,
        /// which a background launch need not reach. The running activity's own
        /// content is then the only record of the session, so it decides whether
        /// the activity is repainted or ended.
        private func performBackgroundUpdate() async {
            let session = ActiveSessionManager.shared
            // Pruning ends the activity (`sessionCleared`) when the last dose
            // has run out, and shrinks it (`sessionDidChange`) when one has.
            session.refresh()
            if currentActivity != nil, !session.activeEntries.isEmpty {
                let state = session.buildContentState(colorMap: session.cachedColorMap)
                await pushUpdateAwaiting(ActivityContent(state: state, staleDate: Self.staleDate(for: state)))
            } else if let currentActivity, session.activeEntries.isEmpty,
                      !currentActivity.content.state.hasRunOut() {
                // Same content, pushed again so the phase label is redrawn at
                // the current time.
                var state = currentActivity.content.state
                state.lastUpdated = .now
                await pushUpdateAwaiting(ActivityContent(state: state, staleDate: Self.staleDate(for: state)))
            }
            // A new activity can't be requested from the background, so an
            // activity ActivityKit capped is left for the next foreground to replace.
            endFinishedActivities(canReplace: false)
            await awaitPendingEnds()
        }

        /// Asks for the refresh at the next phase boundary any active substance
        /// crosses (the session's end included), floored at two minutes. iOS
        /// grants a suspended app only a handful of these a day, and none at all
        /// in Low Power Mode or after the user swipes the app away, so each one
        /// is aimed at the moment the display actually changes. The one that
        /// lands after the last dose runs out ends the activity while the app
        /// is asleep; when none lands, the card has already collapsed to its
        /// "Session complete" row at its stale date.
        func scheduleBackgroundRefresh() {
            let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
            request.earliestBeginDate = Date(timeIntervalSinceNow: max(2 * 60, nextChangeInterval()))
            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                Logger.liveActivity.error("Failed to schedule background refresh: \(error.localizedDescription, privacy: .public)")
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
            pendingEnds.append(Task { await activity.end(content, dismissalPolicy: .immediate) })
        }

        /// Returns once every end sent so far has landed.
        private func awaitPendingEnds() async {
            let ends = pendingEnds
            pendingEnds.removeAll()
            for end in ends {
                await end.value
            }
        }

        // MARK: - Finished Activities

        /// What to do with one Live Activity that is on, or was on, the screen.
        enum Disposition: Equatable {
            /// Leave it as it is.
            case keep
            /// Take it off the screen now.
            case end
            /// Take it off the screen and put up a fresh one for the session.
            case replace
            /// Stop tracking it; the user already removed it.
            case release
        }

        /// The part of `ActivityState` the decision reads.
        enum Lifecycle {
            /// `.active` or `.stale`: on screen and still updatable.
            case running
            /// On the Lock Screen with its content frozen.
            case ended
            /// Off the screen.
            case dismissed
            /// A state this build doesn't know.
            case other

            init(_ state: ActivityState) {
                switch state {
                case .active, .stale: self = .running
                case .ended: self = .ended
                case .dismissed: self = .dismissed
                default: self = .other
                }
            }
        }

        /// Decide one activity's fate.
        ///
        /// - A running activity this manager holds stays until its content has
        ///   run out with no session in memory to replace it. With a session
        ///   in memory, pruning ends it instead; with content still running and
        ///   no session, recovery has yet to run and will refresh it.
        /// - Any other running activity is a leftover: the manager runs one at
        ///   a time and ends each one it lets go of, so nothing updates it again.
        /// - An ended activity's content is frozen. ActivityKit ends one at its
        ///   eight-hour cap and leaves it on the Lock Screen for up to four
        ///   more hours. One this manager held, with doses still running, is
        ///   replaced when `canReplace` (a new activity can only be requested in
        ///   the foreground); every other one comes off the screen.
        /// - A held activity the user dismissed is let go when the user asks for
        ///   the card again, so that start requests a fresh one rather than
        ///   updating a card nobody can see.
        static func disposition(
            lifecycle: Lifecycle,
            isHeld: Bool,
            contentHasRunOut: Bool,
            sessionIsEmpty: Bool,
            canReplace: Bool,
        ) -> Disposition {
            switch lifecycle {
            case .running:
                guard isHeld else { return .end }
                return sessionIsEmpty && contentHasRunOut ? .end : .keep
            case .ended:
                guard isHeld, !contentHasRunOut, !sessionIsEmpty else { return .end }
                return canReplace ? .replace : .keep
            case .dismissed:
                return isHeld ? .release : .keep
            case .other:
                return .keep
            }
        }

        /// Apply ``disposition(lifecycle:isHeld:contentHasRunOut:sessionIsEmpty:canReplace:)``
        /// to every Piru activity ActivityKit still lists. Decisions and the
        /// release of the held activity happen now; the ends are queued in
        /// ``pendingEnds``.
        ///
        /// A held activity the user dismissed is let go only when
        /// `releasingDismissed` (the Start button). Held, it keeps automatic
        /// starts from putting the card straight back when a dose runs out or
        /// a color changes.
        ///
        /// - Returns: whether the held activity was ended for a replacement,
        ///   which the caller then requests.
        @discardableResult
        private func endFinishedActivities(
            canReplace: Bool,
            releasingDismissed: Bool = false,
            now: Date = .now,
        ) -> Bool {
            let sessionIsEmpty = ActiveSessionManager.shared.activeEntries.isEmpty
            var replaces = false
            for activity in Activity<PiruActivityAttributes>.activities {
                let isHeld = activity.id == currentActivity?.id
                let disposition = Self.disposition(
                    lifecycle: Lifecycle(activity.activityState),
                    isHeld: isHeld,
                    contentHasRunOut: activity.content.state.hasRunOut(at: now),
                    sessionIsEmpty: sessionIsEmpty,
                    canReplace: canReplace,
                )
                switch disposition {
                case .keep:
                    continue
                case .release:
                    if releasingDismissed { releaseCurrentActivity() }
                    continue
                case .replace:
                    replaces = true
                case .end:
                    break
                }
                if isHeld { releaseCurrentActivity() }
                nonisolated(unsafe) let ending = activity
                pendingEnds.append(Task { await ending.end(nil, dismissalPolicy: .immediate) })
            }
            return replaces
        }

        /// Stop tracking the held activity and every update source aimed at it.
        private func releaseCurrentActivity() {
            stopUpdateTimer()
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
            currentActivity = nil
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
        ///
        /// With no session in memory (the app launched into the background for
        /// its refresh task) the held activity's content stands in for it, so
        /// the next refresh is still aimed at that content's next boundary or end.
        private func nextChangeInterval() -> TimeInterval {
            let now = Date.now
            let session = ActiveSessionManager.shared
            let boundaries: [Date] = if session.activeEntries.isEmpty {
                currentActivity?.content.state.activeSubstances.flatMap(\.phaseChangeDates) ?? []
            } else {
                session.activeEntries.flatMap { item -> [Date] in
                    guard let duration = item.duration else { return [] }
                    let start = item.snapshot.timestamp
                    let bounds = duration.phaseBoundaries
                    return [
                        bounds.onsetEnd, bounds.comeupEnd, bounds.peakEnd,
                        bounds.offsetEnd, bounds.afterglowEnd,
                    ].map { start.addingTimeInterval($0 * 60) }
                }
            }
            guard let next = boundaries.filter({ $0 > now }).min() else { return Self.maximumTick }
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
                pushUpdate(ActivityContent(state: state, staleDate: Self.staleDate(for: state)))
            }
            // The tick is one-shot; re-arm it for the *next* boundary.
            startUpdateTimer()
        }

        private func startActivity(state: PiruActivityAttributes.ContentState) {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

            let attributes = PiruActivityAttributes()
            let content = ActivityContent(state: state, staleDate: Self.staleDate(for: state))

            do {
                currentActivity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil,
                )
                startUpdateTimer()
                scheduleBackgroundRefresh()
            } catch {
                Logger.liveActivity.error("Failed to start Live Activity: \(error.localizedDescription, privacy: .public)")
            }
        }

        /// When the pushed content should be treated as out of date.
        ///
        /// ActivityKit gives an app no way to schedule an arbitrary future re-render:
        /// the view is redrawn on a content update, and once more when it goes stale.
        /// That single stale re-render is the only repaint that happens while the app
        /// is suspended, so it is spent on **the moment the last curve runs out**: the
        /// Lock Screen card collapses to its "Session complete" row there, whether or
        /// not the app wakes to end the activity. Phase boundaries before the end are
        /// repainted by the app's own pushes (the foreground tick and the background
        /// refresh); spending the stale repaint on one of them leaves a suspended
        /// app's card showing the finished graph forever.
        ///
        /// Read from the pushed state rather than the session, so it marks the end
        /// the card draws (zero-order and filled-in phases included) and works for a
        /// repaint of the activity's own content with no session in memory.
        static func staleDate(for state: PiruActivityAttributes.ContentState) -> Date? {
            state.endDate?.addingTimeInterval(boundaryRepaintLag)
        }

        /// How long after the end the stale repaint is set. The view reads the
        /// clock when it draws, so a repaint landing exactly on the end could
        /// still draw the last phase.
        static let boundaryRepaintLag: TimeInterval = 1
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
        func resumeIfRunning() {}
        func sessionCleared() {}
        func startLiveActivity() {}
        func hideLiveActivity() {}
        func endForProfileSwitch() {}
        func deleteJournalActivities() async {}
        func recoverEntriesFromActivity() -> [(snapshot: DoseSnapshot, duration: DurationProfile?, tint: P3Color)]? {
            nil
        }
    }
#endif
