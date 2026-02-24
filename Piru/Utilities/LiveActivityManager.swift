import ActivityKit
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

    private var currentActivity: Activity<PiruActivityAttributes>?
    private var activeEntries: [(snapshot: DoseSnapshot, duration: DurationProfile?, colorHex: String)] = []

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

        let state = buildContentState(allColors: allColors)

        if let currentActivity {
            Task {
                await currentActivity.update(
                    ActivityContent(state: state, staleDate: staleDate())
                )
            }
        } else {
            startActivity(state: state)
        }
    }

    func addDoses(
        entries: [(entry: DoseEntry, substance: Substance?)],
        allColors: [SubstanceColor]
    ) {
        let colorMap = Dictionary(
            uniqueKeysWithValues: allColors.map { ($0.substance.lowercased(), $0.hexColor) }
        )

        for (entry, substance) in entries {
            let snapshot = DoseSnapshot(entry: entry)
            let hex = colorMap[snapshot.substance.lowercased()] ?? "007AFF"
            let duration = substance?.duration(for: entry.route)
            activeEntries.append((snapshot: snapshot, duration: duration, colorHex: hex))
        }

        pruneCompleted()
        guard !activeEntries.isEmpty else { return }

        let state = buildContentState(allColors: allColors)

        if let currentActivity {
            Task {
                await currentActivity.update(
                    ActivityContent(state: state, staleDate: staleDate())
                )
            }
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

        let state = buildContentState(allColors: allColors)
        if let currentActivity {
            Task {
                await currentActivity.update(
                    ActivityContent(state: state, staleDate: staleDate())
                )
            }
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

        let colorMap = Dictionary(
            uniqueKeysWithValues: allColors.map { ($0.substance.lowercased(), $0.hexColor) }
        )

        activeEntries = doseEntries.map { entry in
            let snapshot = DoseSnapshot(entry: entry)
            let matchedSubstance = SubstanceLibrary.search(snapshot.substance).first {
                $0.name.lowercased() == snapshot.substance.lowercased()
            }
            let duration = matchedSubstance?.duration(for: entry.route)
            let hex = colorMap[snapshot.substance.lowercased()] ?? "007AFF"
            return (snapshot: snapshot, duration: duration, colorHex: hex)
        }

        pruneCompleted()
        guard !activeEntries.isEmpty else { return }

        let state = buildContentState(allColors: allColors)
        startActivity(state: state)
    }

    func endActivity() {
        guard let currentActivity else { return }
        let state = buildContentState(allColors: [])
        Task {
            await currentActivity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        self.currentActivity = nil
        activeEntries.removeAll()
    }

    /// Whether a live activity is currently running
    var isActive: Bool {
        currentActivity != nil && !activeEntries.isEmpty
    }

    // MARK: - Private

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
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }

    private func buildContentState(allColors: [SubstanceColor]) -> PiruActivityAttributes.ContentState {
        let colorMap = Dictionary(
            uniqueKeysWithValues: allColors.map { ($0.substance.lowercased(), $0.hexColor) }
        )

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
