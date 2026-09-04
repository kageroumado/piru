import Foundation

// MARK: - Label

/// One entry in the idle dock's center-label fallback list. The list is
/// ordered by the user; the first label whose condition holds is shown, and
/// when none does the dock shows ``DockLabel/unavailable``.
nonisolated enum DockLabel: Hashable, Codable, Identifiable {
    /// Always applies. The user's string, stored verbatim.
    case text(String)
    /// Applies while the current hour is inside `startHour..<endHour`
    /// (wrapping past midnight when `endHour <= startHour`; equal hours mean
    /// the whole day).
    case timed(String, startHour: Int, endHour: Int)
    /// A live timer — applies while it has something to count.
    case timer(DockTimer)
    /// "2 due", or "Memantine due" when exactly one med fits. Applies while a
    /// med slot is due.
    case due

    /// What the dock shows when no label applies.
    static let unavailable = "—"

    /// Free-text labels are clipped here so they fit the idle bar.
    static let maxTextLength = 24

    /// How long a last dose keeps counting; past this the timer falls through.
    static let sinceLastDoseWindow: TimeInterval = 24 * 60 * 60

    static var defaultLabels: [DockLabel] {
        [.due, .timer(.untilNextMed)]
    }

    var id: Self {
        self
    }

    /// Resolves the ordered list to what the dock shows.
    @MainActor
    static func resolve(_ labels: [DockLabel], in context: DockLabelContext) -> String {
        for label in labels {
            if let resolved = label.resolved(in: context) { return resolved }
        }
        return unavailable
    }

    /// This label's text when its condition holds, `nil` otherwise.
    @MainActor
    func resolved(in context: DockLabelContext) -> String? {
        switch self {
        case let .text(string):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed

        case let .timed(string, startHour, endHour):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let hour = context.calendar.component(.hour, from: context.now)
            return Self.hour(hour, isWithin: startHour, endHour) ? trimmed : nil

        case let .timer(timer):
            return timer.resolved(in: context)

        case .due:
            switch context.dueMedNames.count {
            case 0: return nil
            case 1: return String(localized: "\(context.dueMedNames[0]) due")
            default: return String(localized: "\(context.dueMedNames.count) due")
            }
        }
    }

    private static func hour(_ hour: Int, isWithin startHour: Int, _ endHour: Int) -> Bool {
        if startHour == endHour { return true }
        if startHour < endHour { return hour >= startHour && hour < endHour }
        return hour >= startHour || hour < endHour
    }
}

/// The two live timers a dock label can count.
nonisolated enum DockTimer: String, Hashable, Codable, CaseIterable {
    case sinceLastDose
    case untilNextMed

    @MainActor
    func resolved(in context: DockLabelContext) -> String? {
        switch self {
        case .sinceLastDose:
            guard let dose = context.lastDose else { return nil }
            let elapsed = context.now.timeIntervalSince(dose.timestamp)
            guard elapsed >= 0, elapsed <= DockLabel.sinceLastDoseWindow else { return nil }
            return String(localized: "\(elapsed.durationHM) since \(dose.name)")

        case .untilNextMed:
            guard let med = context.nextMed else { return nil }
            let remaining = med.at.timeIntervalSince(context.now)
            guard remaining >= 0 else { return nil }
            return String(localized: "Next: \(med.name) in \(remaining.durationHM)")
        }
    }
}

// MARK: - Context

/// Everything a label's condition can depend on, gathered once per dock
/// refresh so resolution itself is pure.
nonisolated struct DockLabelContext: Hashable {
    var now: Date = .now
    var calendar: Calendar = .current
    /// The most recent logged dose, by display name.
    var lastDose: DockDoseRef?
    /// The next scheduled med slot that has not been taken.
    var nextMed: DockMedRef?
    /// Display names of the meds due right now, in due order.
    var dueMedNames: [String] = []
}

nonisolated struct DockDoseRef: Hashable {
    var name: String
    var timestamp: Date
}

nonisolated struct DockMedRef: Hashable {
    var name: String
    var at: Date
}
