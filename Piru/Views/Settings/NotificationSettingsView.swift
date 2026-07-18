import SwiftData
import SwiftUI
import UIKit
import UserNotifications

/// The unified notification management screen: every notification type the app
/// can send as a row with a plain-language *why* and a real toggle, under an
/// honest OS-permission header.
///
/// What this screen lists is the contract (`Specs/notifications-system.md`
/// §Honesty): the app sends nothing that isn't controllable here. Rows are
/// grouped the way the catalog groups them — dose reminders, session alerts,
/// safety limits, supplies — plus the Live Activity switch, which lives here
/// because users look for it here even though it isn't a notification.
struct NotificationSettingsView: View {
    @State private var prefs = NotificationPreferencesStore.shared
    @State private var authStatus: UNAuthorizationStatus?
    @State private var nextFireDates: [NotificationType: Date] = [:]
    @AppStorage("liveActivityEnabled") private var autoLiveActivity = false
    @Environment(\.scenePhase) private var scenePhase

    /// Rows gray out when the OS grant is missing or everything is paused —
    /// disabled with an explanatory footer, never silently inert.
    private var rowsDisabled: Bool {
        authStatus == .denied || !prefs.masterEnabled
    }

    var body: some View {
        List {
            Group {
                NotificationPermissionSection(status: authStatus) {
                    await requestPermission()
                }

                pauseSection

                typeSection(
                    types: [.routine, .routineFollowUp],
                    header: "Dose Reminders",
                    footer: nil,
                )
                typeSection(
                    types: [.comedown, .phase, .hydration, .sleep],
                    header: "During a Session",
                    footer: nil,
                )
                typeSection(
                    types: [.cumulative],
                    header: "Safety Limits",
                    footer: nil,
                )
                typeSection(
                    types: [.inventory],
                    header: "Supplies",
                    footer: nil,
                )

                liveActivitySection
            }
            .listRowBackground(CardBackground())
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            // Returning from Settings.app after flipping the OS switch.
            if phase == .active { Task { await refresh() } }
        }
        .onChange(of: prefs.typeEnabled) {
            Task { await refreshNextFireDates() }
        }
    }

    // MARK: - Sections

    private var pauseSection: some View {
        Section {
            Toggle(isOn: pauseAllBinding) {
                Label("Pause All Notifications", systemImage: "bell.slash")
            }
            .tint(Theme.accent)
            .disabled(authStatus == .denied)
        } footer: {
            Text("Silences everything without losing your choices below.")
        }
    }

    private func typeSection(
        types: [NotificationType],
        header: LocalizedStringKey,
        footer: LocalizedStringKey?,
    ) -> some View {
        Section {
            ForEach(types) { type in
                NotificationTypeRow(
                    type: type,
                    nextFireDate: nextFireDates[type],
                    disabled: rowsDisabled,
                )
            }
        } header: {
            Text(header)
        } footer: {
            if let footer {
                Text(footer)
            }
        }
    }

    private var liveActivitySection: some View {
        Section {
            Toggle(isOn: $autoLiveActivity) {
                Label("Automatic Live Activity", systemImage: "bolt.heart")
            }
            .tint(Theme.accent)
        } header: {
            Text("Live Activity")
        } footer: {
            Text("Automatically show a Live Activity on the Lock Screen and Dynamic Island when you start tracking a substance. You can also start one manually from a day or entry's detail view.")
        }
    }

    // MARK: - Bindings

    private var pauseAllBinding: Binding<Bool> {
        Binding(
            get: { !prefs.masterEnabled },
            set: { prefs.setMasterEnabled(!$0) },
        )
    }

    // MARK: - Refresh

    private func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authStatus = settings.authorizationStatus
        await refreshNextFireDates()
    }

    /// Earliest pending fire date per type — the "Next: …" transparency line
    /// that turns the screen from a toggle wall into a window on what the app
    /// is actually about to do.
    private func refreshNextFireDates() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        var next: [NotificationType: Date] = [:]
        for request in pending {
            guard let type = NotificationType.allCases.first(where: { candidate in
                candidate.identifierPrefixes.contains { request.identifier.hasPrefix($0) }
            }) else { continue }
            let fireDate: Date? = switch request.trigger {
            case let calendar as UNCalendarNotificationTrigger: calendar.nextTriggerDate()
            case let interval as UNTimeIntervalNotificationTrigger: interval.nextTriggerDate()
            default: nil
            }
            guard let fireDate else { continue }
            next[type] = min(next[type] ?? .distantFuture, fireDate)
        }
        nextFireDates = next
    }

    private func requestPermission() async {
        _ = await DoseNotificationManager.requestAuthorization()
        await refresh()
    }
}

// MARK: - Permission header

/// One honest status row reflecting the real `UNUserNotificationCenter`
/// authorization: enabled, ask (a button triggering the single central
/// request), or denied (deep-links to Settings.app).
private struct NotificationPermissionSection: View {
    let status: UNAuthorizationStatus?
    let requestPermission: () async -> Void

    @Environment(\.openURL) private var openURL
    @State private var requesting = false

    var body: some View {
        Section {
            switch status {
            case .authorized, .provisional, .ephemeral:
                Label {
                    Text("Notifications Enabled")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            case .denied:
                Label {
                    Text("Notifications Are Off")
                } icon: {
                    Image(systemName: "bell.slash.fill")
                        .foregroundStyle(.secondary)
                }
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Label("Open Settings", systemImage: "gear")
                }
            case .notDetermined:
                Button {
                    guard !requesting else { return }
                    requesting = true
                    Task {
                        await requestPermission()
                        requesting = false
                    }
                } label: {
                    Label(requesting ? "Asking…" : "Allow Notifications", systemImage: "bell.badge")
                }
            default:
                // Still loading — keep the section stable so the list doesn't jump.
                Label {
                    Text("Checking Permission…")
                } icon: {
                    ProgressView()
                }
            }
        } footer: {
            switch status {
            case .denied:
                Text("Notifications for Piru are turned off in Settings. None of the alerts below can be delivered until they're allowed again.")
            case .notDetermined:
                Text("Piru asks the system once. You choose exactly what it's allowed to send below.")
            default:
                Text("Piru only sends the notifications listed on this screen.")
            }
        }
    }
}

// MARK: - Type row

/// One catalog row: symbol + title + toggle, with the type's one-line *why*
/// and, when something is scheduled, the next fire time.
private struct NotificationTypeRow: View {
    let type: NotificationType
    let nextFireDate: Date?
    let disabled: Bool

    @State private var prefs = NotificationPreferencesStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(isOn: enabledBinding) {
                Label(type.rowTitle, systemImage: type.rowSymbol)
            }
            .tint(Theme.accent)
            Text(type.rowWhy)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
            if let nextFireDate, prefs.isEffectivelyEnabled(type) {
                Text("Next: \(nextFireDate, format: .dateTime.weekday(.wide).hour().minute())")
                    .font(.caption2)
                    .foregroundStyle(Theme.accent)
            }
        }
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { prefs.isTypeEnabled(type) },
            set: { prefs.setEnabled(type, $0) },
        )
    }
}

// MARK: - Row catalog copy

/// The management screen's authored catalog — title, symbol, and the
/// plain-language *why it exists* shown in front of the user.
extension NotificationType {
    var rowTitle: LocalizedStringKey {
        switch self {
        case .comedown: "Comedown Alerts"
        case .hydration: "Hydration Reminders"
        case .sleep: "Sleep Reminders"
        case .phase: "Phase Alerts"
        case .cumulative: "Cumulative Dose Warnings"
        case .routine: "Routine Reminders"
        case .routineFollowUp: "Follow-Up Reminders"
        case .inventory: "Low Stock Alerts"
        }
    }

    var rowSymbol: String {
        switch self {
        case .comedown: "chart.line.downtrend.xyaxis"
        case .hydration: "drop"
        case .sleep: "moon.zzz"
        case .phase: "waveform.path.ecg"
        case .cumulative: "exclamationmark.triangle"
        case .routine: "repeat"
        case .routineFollowUp: "clock.arrow.circlepath"
        case .inventory: "archivebox"
        }
    }

    var rowWhy: LocalizedStringKey {
        switch self {
        case .comedown:
            "Warns you before a dose wears off, so the drop doesn't catch you off guard. Armed per dose from its comedown alert screen."
        case .hydration:
            "Water nudges timed to your dose — stimulants and empathogens mask thirst."
        case .sleep:
            "A wind-down reminder late into long stimulant sessions, when sleep is the best recovery."
        case .phase:
            "Timing cues at onset, come-up, and peak so you can anchor what you feel to the timeline."
        case .cumulative:
            "A heads-up when your 12-hour total of one substance reaches a heavy range. Turning this off removes a safety net."
        case .routine:
            "A daily nudge at each routine's set time so a dose never slips your mind. Tapping it opens Quick Log with the routine staged."
        case .routineFollowUp:
            "Asks again a little later if a routine still isn't logged — like snooze for an alarm. Set the cadence on each routine."
        case .inventory:
            "A heads-up when something you track runs low or out — before the empty bottle surprises you."
        }
    }
}
