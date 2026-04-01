import Foundation
import SwiftData

/// Tracks which substances are currently active (being metabolized),
/// independent of whether the iOS Live Activity widget is running.
///
/// This is the source of truth for the tab bar session accessory.
/// `LiveActivityManager` reads from this manager for Live Activity updates.
@MainActor
@Observable
final class ActiveSessionManager {
    static let shared = ActiveSessionManager()

    private(set) var activeEntries: [(snapshot: DoseSnapshot, duration: DurationProfile?, colorHex: String)] = []
    var cachedColorMap: [String: String] = [:]

    private var pruneTimer: Timer?

    private init() {}

    // MARK: - Computed State

    /// Whether any tracked substances are still within their duration window.
    var hasActiveSession: Bool {
        let now = Date.now
        return activeEntries.contains { item in
            guard let duration = item.duration else { return false }
            let endTime = item.snapshot.timestamp.addingTimeInterval(duration.estimatedTotalMinutes * 60)
            return now <= endTime
        }
    }

    /// Active substance states for UI display (e.g. session accessory view).
    var activeSubstanceStates: [ActiveSubstanceState] {
        buildSubstanceStates(colorMap: cachedColorMap)
    }

    // MARK: - Session Recovery

    /// Recover an active session on app launch.
    /// First tries to recover from a running Live Activity, then falls back to SwiftData.
    func recoverSession(container: ModelContainer) {
        guard activeEntries.isEmpty else { return }

        // Try recovering from a running Live Activity first
        if let recoveredEntries = LiveActivityManager.shared.recoverEntriesFromActivity() {
            activeEntries = recoveredEntries
            if !activeEntries.isEmpty {
                startPruneTimer()
            }
            return
        }

        // Fall back to SwiftData
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
            startPruneTimer()
        }
    }

    // MARK: - Add / Remove

    func addDose(
        entry: DoseEntry,
        substance: Substance?,
        colorHex: String,
        allColors: [SubstanceColor]
    ) {
        let snapshot = DoseSnapshot(entry: entry)
        let duration = Self.resolveDuration(substance: substance, route: entry.route)
        activeEntries.append((snapshot: snapshot, duration: duration, colorHex: colorHex))

        let colorMap = Self.buildColorMap(from: allColors)
        cachedColorMap = colorMap

        pruneCompleted()

        if !activeEntries.isEmpty {
            startPruneTimer()
            LiveActivityManager.shared.sessionDidChange()
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
            let duration = Self.resolveDuration(substance: substance, route: entry.route)
            activeEntries.append((snapshot: snapshot, duration: duration, colorHex: hex))
        }

        pruneCompleted()

        if !activeEntries.isEmpty {
            startPruneTimer()
            LiveActivityManager.shared.sessionDidChange()
        }
    }

    func removeDose(
        substanceName: String,
        timestamp: Date,
        allColors: [SubstanceColor]
    ) {
        activeEntries.removeAll { item in
            item.snapshot.substance == substanceName &&
            abs(item.snapshot.timestamp.timeIntervalSince(timestamp)) < 1
        }

        let colorMap = Self.buildColorMap(from: allColors)
        cachedColorMap = colorMap

        if activeEntries.isEmpty {
            stopPruneTimer()
            LiveActivityManager.shared.sessionCleared()
        } else {
            LiveActivityManager.shared.sessionDidChange()
        }
    }

    /// Rebuild session from a set of existing day entries (e.g. after restart from DayDetailView).
    func restartFromEntries(
        _ doseEntries: [DoseEntry],
        allColors: [SubstanceColor]
    ) {
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

        if !activeEntries.isEmpty {
            startPruneTimer()
        }
    }

    /// Prune expired entries and stop timer if empty. Call on scene phase changes.
    func refresh() {
        pruneCompleted()
    }

    /// Clear all tracked entries (e.g. when user explicitly ends session).
    func clearSession() {
        activeEntries.removeAll()
        stopPruneTimer()
    }

    // MARK: - State Building

    func buildSubstanceStates(colorMap: [String: String]) -> [ActiveSubstanceState] {
        activeEntries.compactMap { item in
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
    }

    func buildContentState(colorMap: [String: String]) -> PiruActivityAttributes.ContentState {
        PiruActivityAttributes.ContentState(
            activeSubstances: buildSubstanceStates(colorMap: colorMap),
            lastUpdated: .now
        )
    }

    // MARK: - Private

    static func resolveDuration(substance: Substance?, route: RouteOfAdministration) -> DurationProfile? {
        substance?.resolveDuration(for: route)
    }

    static func buildColorMap(from allColors: [SubstanceColor]) -> [String: String] {
        allColors.hexColorMap
    }

    private func pruneCompleted() {
        let now = Date.now
        activeEntries.removeAll { item in
            guard let duration = item.duration else { return true }
            let endTime = item.snapshot.timestamp.addingTimeInterval(duration.estimatedTotalMinutes * 60)
            return now > endTime
        }

        if activeEntries.isEmpty {
            stopPruneTimer()
        }
    }

    private func startPruneTimer() {
        guard pruneTimer == nil else { return }
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pruneCompleted()
            }
        }
    }

    private func stopPruneTimer() {
        pruneTimer?.invalidate()
        pruneTimer = nil
    }
}
