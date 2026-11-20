import SwiftUI

/// Groups notification types into the three spec sections.
nonisolated enum NotificationCategory: CaseIterable {
    case reminders
    case session
    case safety

    var types: [NotificationType] {
        switch self {
        case .reminders: [.routine, .routineFollowUp]
        case .session: [.phase, .hydration, .sleep, .checkIn]
        case .safety: [.cumulative, .inventory]
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .reminders: "Med Reminders"
        case .session: "Session Alerts"
        case .safety: "Safety & Supplies"
        }
    }

    var symbol: String {
        switch self {
        case .reminders: "repeat"
        case .session: "waveform.path.ecg"
        case .safety: "exclamationmark.triangle"
        }
    }
}
