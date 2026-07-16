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
    /// Substance → color hex, refreshed alongside `activeEntries`. `private(set)`
    /// like its siblings so an external write can't invalidate accessory
    /// consumers out from under the manager (all writers are internal).
    private(set) var cachedColorMap: [String: String] = [:]

    private var pruneTask: Task<Void, Never>?

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
                scheduleNextPrune()
            }
            return
        }

        // Fall back to SwiftData
        let context = ModelContext(container)
        // Recover anything potentially still active: look back 12 h rather
        // than only the current session day — a 01:30 dose must still surface
        // when the app cold-launches at 04:50, just past the day cutoff. The
        // forward bound keeps today's deliberately future-dated doses, as
        // before; `pruneCompleted()` drops whatever has already run out.
        let lookbackStart = Date.now.addingTimeInterval(-12 * 3_600)
        let endOfDay = Calendar.current.sessionDayStart(for: .now).addingTimeInterval(86_400)

        let descriptor = FetchDescriptor<DoseEntry>(
            predicate: #Predicate { entry in
                entry.timestamp >= lookbackStart && entry.timestamp < endOfDay
            },
            sortBy: [SortDescriptor(\.timestamp)],
        )

        guard let entries = try? context.fetch(descriptor), !entries.isEmpty else { return }

        let colorDescriptor = FetchDescriptor<SubstanceColor>()
        let colors = (try? context.fetch(colorDescriptor)) ?? []
        let colorMap = Self.buildColorMap(from: colors)
        cachedColorMap = colorMap

        activeEntries = entries.map { entry in
            let snapshot = DoseSnapshot(entry: entry)
            let matchedSubstance = SubstanceLibrary.lookupByNameOrAlias(snapshot.substance)
            let duration = Self.resolveDuration(substance: matchedSubstance, entry: entry)
            let hex = colorMap[snapshot.substance.lowercased()] ?? PresetColor.defaultHex
            return (snapshot: snapshot, duration: duration, colorHex: hex)
        }

        pruneCompleted()
    }

    // MARK: - Add / Remove

    func addDose(
        entry: DoseEntry,
        substance: Substance?,
        colorHex: String,
        allColors: [SubstanceColor],
    ) {
        let snapshot = DoseSnapshot(entry: entry)
        let duration = Self.resolveDuration(substance: substance, entry: entry)
        activeEntries.append((snapshot: snapshot, duration: duration, colorHex: colorHex))

        let colorMap = Self.buildColorMap(from: allColors)
        cachedColorMap = colorMap

        pruneCompleted()

        if !activeEntries.isEmpty {
            LiveActivityManager.shared.sessionDidChange()
        }
    }

    func addDoses(
        entries: [(entry: DoseEntry, substance: Substance?)],
        allColors: [SubstanceColor],
    ) {
        let colorMap = Self.buildColorMap(from: allColors)
        cachedColorMap = colorMap

        for (entry, substance) in entries {
            let snapshot = DoseSnapshot(entry: entry)
            let hex = colorMap[snapshot.substance.lowercased()] ?? PresetColor.defaultHex
            let duration = Self.resolveDuration(substance: substance, entry: entry)
            activeEntries.append((snapshot: snapshot, duration: duration, colorHex: hex))
        }

        pruneCompleted()

        if !activeEntries.isEmpty {
            LiveActivityManager.shared.sessionDidChange()
        }
    }

    /// Remove a tracked dose, matched by its stable `id`. The substance name +
    /// timestamp serve only the fallback for snapshots recovered from a running
    /// Live Activity, which carry no id (see ``DoseSnapshot/id``).
    func removeDose(
        id: UUID,
        substanceName: String,
        timestamp: Date,
        allColors: [SubstanceColor],
    ) {
        activeEntries.removeAll { item in
            if let snapshotID = item.snapshot.id {
                return snapshotID == id
            }
            return item.snapshot.substance == substanceName &&
                abs(item.snapshot.timestamp.timeIntervalSince(timestamp)) < 1
        }

        let colorMap = Self.buildColorMap(from: allColors)
        cachedColorMap = colorMap

        if activeEntries.isEmpty {
            pruneTask?.cancel()
            pruneTask = nil
            LiveActivityManager.shared.sessionCleared()
        } else {
            scheduleNextPrune()
            LiveActivityManager.shared.sessionDidChange()
        }
    }

    /// Update a tracked dose after the user edits its `DoseEntry`.
    ///
    /// The dose is matched by the entry's stable `id`, which survives edits to
    /// any field — including the timestamp. The pre-edit substance name +
    /// timestamp serve only the fallback for snapshots recovered from a running
    /// Live Activity, which carry no id (see ``DoseSnapshot/id``). When found,
    /// the snapshot and resolved duration are rebuilt from the edited entry; if
    /// no match exists — e.g. the dose had expired and been pruned but the edit
    /// moved it back into an active window — the refreshed snapshot is appended
    /// instead. Newly-expired results are pruned, keeping the session accessory
    /// and Live Activity in sync with SwiftData without waiting for an app
    /// relaunch.
    func updateDose(
        previousSubstanceName: String,
        previousTimestamp: Date,
        entry: DoseEntry,
        substance: Substance?,
        colorHex: String,
        allColors: [SubstanceColor],
    ) {
        let colorMap = Self.buildColorMap(from: allColors)
        cachedColorMap = colorMap

        let snapshot = DoseSnapshot(entry: entry)
        let duration = Self.resolveDuration(substance: substance, entry: entry)
        let hex = colorMap[snapshot.substance.lowercased()] ?? colorHex
        let updated = (snapshot: snapshot, duration: duration, colorHex: hex)

        if let index = activeEntries.firstIndex(where: { item in
            if let snapshotID = item.snapshot.id {
                return snapshotID == entry.id
            }
            return item.snapshot.substance == previousSubstanceName &&
                abs(item.snapshot.timestamp.timeIntervalSince(previousTimestamp)) < 1
        }) {
            activeEntries[index] = updated
        } else {
            activeEntries.append(updated)
        }

        pruneCompleted()

        if activeEntries.isEmpty {
            pruneTask?.cancel()
            pruneTask = nil
            LiveActivityManager.shared.sessionCleared()
        } else {
            LiveActivityManager.shared.sessionDidChange()
        }
    }

    /// Convenience for inline edits where only the entry's own fields change
    /// and the substance name is unchanged — e.g. the "Adjust Time" sheets.
    /// Resolves the substance + color and forwards to ``updateDose(previousSubstanceName:previousTimestamp:entry:substance:colorHex:allColors:)``
    /// so the session accessory and Live Activity stay in sync with SwiftData.
    func refreshEditedEntry(
        previousTimestamp: Date,
        entry: DoseEntry,
        allColors: [SubstanceColor],
    ) {
        let colorHex = allColors.first {
            $0.substance.lowercased() == entry.substance.lowercased()
        }?.hexColor ?? PresetColor.defaultHex
        updateDose(
            previousSubstanceName: entry.substance,
            previousTimestamp: previousTimestamp,
            entry: entry,
            substance: SubstanceLibrary.lookupByNameOrAlias(entry.substance),
            colorHex: colorHex,
            allColors: allColors,
        )
    }

    /// Rebuild session from a set of existing day entries (e.g. after restart from SessionDetailView).
    func restartFromEntries(
        _ doseEntries: [DoseEntry],
        allColors: [SubstanceColor],
    ) {
        let colorMap = Self.buildColorMap(from: allColors)
        cachedColorMap = colorMap

        activeEntries = doseEntries.map { entry in
            let snapshot = DoseSnapshot(entry: entry)
            let matchedSubstance = SubstanceLibrary.lookupByNameOrAlias(snapshot.substance)
            let duration = Self.resolveDuration(substance: matchedSubstance, entry: entry)
            let hex = colorMap[snapshot.substance.lowercased()] ?? PresetColor.defaultHex
            return (snapshot: snapshot, duration: duration, colorHex: hex)
        }

        pruneCompleted()
    }

    /// Prune expired entries and stop timer if empty. Call on scene phase changes.
    func refresh() {
        pruneCompleted()
    }

    /// Re-read `SubstanceColor` records and patch every active entry's stored
    /// `colorHex` (plus `cachedColorMap`) so newly-picked colors are reflected
    /// in the live activity and bottom session accessory without waiting for
    /// the next `addDose` call. Used by `ColorPickerHost` after the user
    /// selects a color for a substance that already has a tracked dose.
    func applyColorUpdates(allColors: [SubstanceColor]) {
        let colorMap = Self.buildColorMap(from: allColors)
        cachedColorMap = colorMap
        activeEntries = activeEntries.map { item in
            let newHex = colorMap[item.snapshot.substance.lowercased()] ?? item.colorHex
            return (snapshot: item.snapshot, duration: item.duration, colorHex: newHex)
        }
        if !activeEntries.isEmpty {
            LiveActivityManager.shared.sessionDidChange()
        }
    }

    /// Clear all tracked entries (e.g. when user explicitly ends session).
    func clearSession() {
        activeEntries.removeAll()
        pruneTask?.cancel()
        pruneTask = nil
    }

    // MARK: - State Building

    func buildSubstanceStates(colorMap: [String: String]) -> [ActiveSubstanceState] {
        activeEntries.compactMap { item in
            let hex = colorMap[item.snapshot.substance.lowercased()] ?? item.colorHex
            let substance = SubstanceLibrary.lookupByNameOrAlias(item.snapshot.substance)
            let doseRange = substance.flatMap {
                ActiveSubstanceState.resolveDoseRange(substance: $0, route: item.snapshot.route)
            }
            let intensity = ActiveSubstanceState.computeDoseIntensity(
                amount: item.snapshot.amount,
                doseRange: doseRange,
            )
            return ActiveSubstanceState(
                // The snapshot's resolved title, not the raw canonical string —
                // this said "Methylphenidate" on the accessory and the Lock Screen
                // for a dose the user logged as Concerta.
                name: item.snapshot.title,
                colorHex: hex,
                timestamp: item.snapshot.timestamp,
                amount: item.snapshot.amount,
                unit: item.snapshot.unit,
                routeDisplayName: item.snapshot.route.displayName,
                duration: item.duration,
                category: substance?.category,
                doseIntensity: intensity,
            )
        }
    }

    func buildContentState(colorMap: [String: String]) -> PiruActivityAttributes.ContentState {
        PiruActivityAttributes.ContentState(
            activeSubstances: buildSubstanceStates(colorMap: colorMap),
            lastUpdated: .now,
        )
    }

    // MARK: - Private

    static func resolveDuration(substance: Substance?, entry: DoseEntry) -> DurationProfile? {
        resolveDuration(substance: substance, route: entry.route, namesUnmodeledForm: entry.namesUnmodeledForm)
    }

    static func resolveDuration(
        substance: Substance?,
        route: RouteOfAdministration,
        namesUnmodeledForm: Bool,
    ) -> DurationProfile? {
        // A dose naming a form we don't model gets no window at all, matching the
        // timeline. The base profile is the wrong answer here in a way that shows:
        // a Concerta dose would open an active session counting down Ritalin's
        // ~3h24m, and the accessory would say so to the minute.
        guard !namesUnmodeledForm else { return nil }
        // `timelineDuration` (not `resolveDuration`) so a long-acting maintenance
        // med — bupropion, an SSRI, a weekly GLP-1 — never spawns a multi-day
        // "active session" with a flat countdown in the tab-bar accessory.
        return substance?.timelineDuration(for: route)
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
        scheduleNextPrune()
    }

    /// Sleep until the earliest entry expires, then prune and re-schedule.
    private func scheduleNextPrune() {
        pruneTask?.cancel()
        pruneTask = nil

        let now = Date.now
        guard let nextExpiry = activeEntries.compactMap({ item -> Date? in
            guard let duration = item.duration else { return nil }
            let end = item.snapshot.timestamp.addingTimeInterval(duration.estimatedTotalMinutes * 60)
            return end > now ? end : nil
        }).min() else { return }

        let delay = nextExpiry.timeIntervalSince(now)
        pruneTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            pruneCompleted()
        }
    }
}
