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

@MainActor
@Observable
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    static let backgroundTaskIdentifier = "com.piru.app.live-activity-refresh"

    private var currentActivity: Activity<PiruActivityAttributes>?
    private var activeEntries: [(snapshot: DoseSnapshot, duration: DurationProfile?, colorHex: String)] = []
    private var updateTimer: Timer?
    private var cachedColorMap: [String: String] = [:]

    /// Whether live activities are enabled by the user in Settings.
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "liveActivityEnabled") as? Bool ?? false
    }

    private init() {
        // Resume any existing activity on app launch and recover tracked entries
        if let existing = Activity<PiruActivityAttributes>.activities.first {
            currentActivity = existing
            activeEntries = existing.content.state.activeSubstances.map { state in
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

        // If live activities are disabled, end any recovered activity
        if !isEnabled {
            endActivity()
        }
    }

    /// Recover an active session from today's SwiftData entries on app launch.
    /// Only runs if no entries were already recovered from a running Live Activity.
    func recoverSession(container: ModelContainer) {
        guard activeEntries.isEmpty else { return }

        let context = ModelContext(container)
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let endOfDay = startOfDay.addingTimeInterval(86400)

        let descriptor = FetchDescriptor<DoseEntry>(
            predicate: #Predicate { entry in
                entry.timestamp >= startOfDay && entry.timestamp < endOfDay
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )

        guard let entries = try? context.fetch(descriptor), !entries.isEmpty else { return }

        let colorDescriptor = FetchDescriptor<SubstanceColor>()
        let colors = (try? context.fetch(colorDescriptor)) ?? []
        let colorMap = Self.buildColorMap(from: colors)
        cachedColorMap = colorMap

        activeEntries = entries.map { entry in
            let snapshot = DoseSnapshot(entry: entry)
            let matchedSubstance = SubstanceLibrary.lookupByNameOrAlias(snapshot.substance)
            let duration = Self.resolveDuration(substance: matchedSubstance, route: entry.route)
            let hex = colorMap[snapshot.substance.lowercased()] ?? "007AFF"
            return (snapshot: snapshot, duration: duration, colorHex: hex)
        }

        pruneCompleted()

        if !activeEntries.isEmpty {
            startUpdateTimer()
        }
    }

    // MARK: - Public API

    func addDose(
        entry: DoseEntry,
        substance: Substance?,
        colorHex: String,
        allColors: [SubstanceColor]
    ) {
        guard isEnabled else { return }
        let snapshot = DoseSnapshot(entry: entry)
        let duration = Self.resolveDuration(substance: substance, route: entry.route)
        activeEntries.append((snapshot: snapshot, duration: duration, colorHex: colorHex))

        pruneCompleted()
        guard !activeEntries.isEmpty else { return }

        let colorMap = Self.buildColorMap(from: allColors)
        cachedColorMap = colorMap
        let state = buildContentState(colorMap: colorMap)

        if currentActivity != nil {
            startUpdateTimer()
            pushUpdate(ActivityContent(state: state, staleDate: staleDate()))
        } else {
            startActivity(state: state)
        }
    }

    func addDoses(
        entries: [(entry: DoseEntry, substance: Substance?)],
        allColors: [SubstanceColor]
    ) {
        guard isEnabled else { return }
        let colorMap = Self.buildColorMap(from: allColors)
        cachedColorMap = colorMap

        for (entry, substance) in entries {
            let snapshot = DoseSnapshot(entry: entry)
            let hex = colorMap[snapshot.substance.lowercased()] ?? "007AFF"
            let duration = Self.resolveDuration(substance: substance, route: entry.route)
            activeEntries.append((snapshot: snapshot, duration: duration, colorHex: hex))
        }

        pruneCompleted()
        guard !activeEntries.isEmpty else { return }

        let state = buildContentState(colorMap: colorMap)

        if currentActivity != nil {
            startUpdateTimer()
            pushUpdate(ActivityContent(state: state, staleDate: staleDate()))
        } else {
            startActivity(state: state)
        }
    }

    /// Remove a specific dose entry from the live activity (e.g. when user deletes it)
    func removeDose(
        substanceName: String,
        timestamp: Date,
        allColors: [SubstanceColor]
    ) {
        activeEntries.removeAll { item in
            item.snapshot.substance == substanceName &&
            abs(item.snapshot.timestamp.timeIntervalSince(timestamp)) < 1
        }

        if activeEntries.isEmpty {
            endActivity()
            return
        }

        let colorMap = Self.buildColorMap(from: allColors)
        cachedColorMap = colorMap
        let state = buildContentState(colorMap: colorMap)
        if currentActivity != nil {
            pushUpdate(ActivityContent(state: state, staleDate: staleDate()))
        }
    }

    /// Restart live activity from a set of existing day entries
    func restartFromEntries(
        _ doseEntries: [DoseEntry],
        allColors: [SubstanceColor]
    ) {
        guard isEnabled else { return }
        // End any existing activity first
        if currentActivity != nil {
            endActivity()
        }

        let colorMap = Self.buildColorMap(from: allColors)
        cachedColorMap = colorMap

        activeEntries = doseEntries.map { entry in
            let snapshot = DoseSnapshot(entry: entry)
            let matchedSubstance = SubstanceLibrary.lookupByNameOrAlias(snapshot.substance)
            let duration = Self.resolveDuration(substance: matchedSubstance, route: entry.route)
            let hex = colorMap[snapshot.substance.lowercased()] ?? "007AFF"
            return (snapshot: snapshot, duration: duration, colorHex: hex)
        }

        pruneCompleted()
        guard !activeEntries.isEmpty else { return }

        let state = buildContentState(colorMap: colorMap)
        startActivity(state: state)
    }

    func endActivity() {
        guard currentActivity != nil else { return }
        stopUpdateTimer()
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
        let state = buildContentState(colorMap: [:])
        pushEnd(ActivityContent(state: state, staleDate: nil))
        self.currentActivity = nil
        activeEntries.removeAll()
    }

    /// Stop the iOS Live Activity widget but keep tracking active substances
    func stopLiveActivity() {
        guard currentActivity != nil else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
        let state = buildContentState(colorMap: cachedColorMap)
        pushEnd(ActivityContent(state: state, staleDate: nil))
        self.currentActivity = nil
        // Keep updateTimer running for pruning; keep activeEntries for UI
    }

    /// Restart the iOS Live Activity from currently tracked entries
    func restartLiveActivity() {
        pruneCompleted()
        guard !activeEntries.isEmpty, currentActivity == nil else { return }
        let state = buildContentState(colorMap: cachedColorMap)
        startActivity(state: state)
    }

    /// Whether a live activity is currently running
    var isActive: Bool {
        currentActivity != nil && !activeEntries.isEmpty
    }

    /// Whether there are any tracked active substances (regardless of live activity state)
    var hasActiveSession: Bool {
        let now = Date.now
        return activeEntries.contains { item in
            guard let duration = item.duration else { return false }
            let endTime = item.snapshot.timestamp.addingTimeInterval(duration.estimatedTotalMinutes * 60)
            return now <= endTime
        }
    }

    /// Prune expired entries and update state. Call on scene phase changes or periodic checks.
    func refresh() {
        pruneCompleted()
    }

    /// Whether the iOS Live Activity (Lock Screen widget) is currently running
    var isLiveActivityRunning: Bool {
        currentActivity != nil
    }

    /// Active substance states for UI display (e.g. session accessory view)
    var activeSubstanceStates: [ActiveSubstanceState] {
        buildContentState(colorMap: cachedColorMap).activeSubstances
    }

    // MARK: - Background Refresh

    func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        guard isEnabled else {
            task.setTaskCompleted(success: true)
            return
        }
        scheduleBackgroundRefresh()

        task.expirationHandler = { }

        if !activeEntries.isEmpty {
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
        pruneCompleted()
        guard !activeEntries.isEmpty else {
            stopUpdateTimer()
            return
        }
        // Only push update if the iOS activity is running
        if currentActivity != nil {
            let state = buildContentState(colorMap: cachedColorMap)
            pushUpdate(ActivityContent(state: state, staleDate: staleDate()))
        }
    }

    private func startActivity(state: PiruActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let earliest = activeEntries.map(\.snapshot.timestamp).min() ?? .now
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

    /// Resolve the best available duration for a substance and route.
    /// Tries: exact route → any route. Returns nil if no duration data available.
    private static func resolveDuration(substance: Substance?, route: RouteOfAdministration) -> DurationProfile? {
        substance?.resolveDuration(for: route)
    }

    private static func buildColorMap(from allColors: [SubstanceColor]) -> [String: String] {
        allColors.hexColorMap
    }

    private func buildContentState(colorMap: [String: String]) -> PiruActivityAttributes.ContentState {
        let substanceStates: [ActiveSubstanceState] = activeEntries.compactMap { item in
            let hex = colorMap[item.snapshot.substance.lowercased()] ?? item.colorHex
            return ActiveSubstanceState(
                name: item.snapshot.substance,
                colorHex: hex,
                timestamp: item.snapshot.timestamp,
                amount: item.snapshot.amount,
                unit: item.snapshot.unit,
                routeDisplayName: item.snapshot.route.displayName,
                duration: item.duration
            )
        }

        return PiruActivityAttributes.ContentState(
            activeSubstances: substanceStates,
            lastUpdated: .now
        )
    }

    private func staleDate() -> Date? {
        // Use a short stale date (5 min) so iOS refreshes the Live Activity frequently.
        // Fall back to substance end time if all entries finish sooner.
        let shortStale = Date.now.addingTimeInterval(5 * 60)
        let substanceEnd = activeEntries.compactMap { item -> Date? in
            guard let duration = item.duration else { return nil }
            return item.snapshot.timestamp.addingTimeInterval(duration.estimatedTotalMinutes * 60)
        }.max()
        guard let end = substanceEnd else { return shortStale }
        return min(shortStale, end)
    }

    private func pruneCompleted() {
        let now = Date.now
        activeEntries.removeAll { item in
            guard let duration = item.duration else {
                return true // Remove entries without duration data
            }
            let endTime = item.snapshot.timestamp.addingTimeInterval(duration.estimatedTotalMinutes * 60)
            return now > endTime
        }

        if activeEntries.isEmpty, currentActivity != nil {
            endActivity()
        }
    }
}
