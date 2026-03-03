import ActivityKit
import BackgroundTasks
import Foundation

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

    private init() {
        // Resume any existing activity on app launch
        if let existing = Activity<PiruActivityAttributes>.activities.first {
            currentActivity = existing
        }
    }

    // MARK: - Public API

    func addDose(
        entry: DoseEntry,
        substance: Substance?,
        colorHex: String,
        allColors: [SubstanceColor]
    ) {
        let snapshot = DoseSnapshot(entry: entry)
        let duration = substance?.duration(for: entry.route)
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
        let colorMap = Self.buildColorMap(from: allColors)
        cachedColorMap = colorMap

        for (entry, substance) in entries {
            let snapshot = DoseSnapshot(entry: entry)
            let hex = colorMap[snapshot.substance.lowercased()] ?? "007AFF"
            let duration = substance?.duration(for: entry.route)
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
        // End any existing activity first
        if currentActivity != nil {
            endActivity()
        }

        let colorMap = Self.buildColorMap(from: allColors)
        cachedColorMap = colorMap

        activeEntries = doseEntries.map { entry in
            let snapshot = DoseSnapshot(entry: entry)
            let matchedSubstance = SubstanceLibrary.shared.lookup(snapshot.substance)
            let duration = matchedSubstance?.duration(for: entry.route)
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

    /// Whether a live activity is currently running
    var isActive: Bool {
        currentActivity != nil && !activeEntries.isEmpty
    }

    // MARK: - Background Refresh

    func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
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
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)
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
        updateTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
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
        guard !activeEntries.isEmpty, currentActivity != nil else {
            stopUpdateTimer()
            return
        }
        let state = buildContentState(colorMap: cachedColorMap)
        pushUpdate(ActivityContent(state: state, staleDate: staleDate()))
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

    private static func buildColorMap(from allColors: [SubstanceColor]) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: allColors.map { ($0.substance.lowercased(), $0.hexColor) }
        )
    }

    private func buildContentState(colorMap: [String: String]) -> PiruActivityAttributes.ContentState {
        let substanceStates: [ActiveSubstanceState] = activeEntries.compactMap { item in
            guard let duration = item.duration else { return nil }

            let boundaries = duration.phaseBoundaries
            let total = duration.estimatedTotalMinutes

            let hex = colorMap[item.snapshot.substance.lowercased()] ?? item.colorHex

            return ActiveSubstanceState(
                substanceName: item.snapshot.substance,
                colorHex: hex,
                doseTimestamp: item.snapshot.timestamp,
                amount: item.snapshot.amount,
                unit: item.snapshot.unit,
                route: item.snapshot.route.displayName,
                onsetEndMinutes: boundaries.onsetEnd,
                comeupEndMinutes: boundaries.comeupEnd,
                peakEndMinutes: boundaries.peakEnd,
                offsetEndMinutes: boundaries.offsetEnd,
                afterglowEndMinutes: duration.afterglow != nil ? boundaries.afterglowEnd : nil,
                totalMinutes: total
            )
        }

        return PiruActivityAttributes.ContentState(
            activeSubstances: substanceStates,
            lastUpdated: .now
        )
    }

    private func staleDate() -> Date? {
        activeEntries.compactMap { item -> Date? in
            guard let duration = item.duration else { return nil }
            return item.snapshot.timestamp.addingTimeInterval(duration.estimatedTotalMinutes * 60)
        }.max()
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
