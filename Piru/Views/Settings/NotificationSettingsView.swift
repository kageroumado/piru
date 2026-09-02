import SwiftData
import SwiftUI
import UIKit
import UserNotifications

/// The unified notification management screen: every notification type the app
/// can send, grouped into three navigable sections with per-type detail sheets.
struct NotificationSettingsView: View {
    @State private var prefs = NotificationPreferencesStore.shared
    @State private var authStatus: UNAuthorizationStatus?
    @State private var nextFireDates: [NotificationType: Date] = [:]
    @AppStorage("liveActivityEnabled") private var autoLiveActivity = false
    @Environment(\.scenePhase) private var scenePhase

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

                liveActivitySection

                categorySummarySection(
                    category: .reminders,
                    header: "Dose Reminders",
                    footer: "Reminders fire at each med's times. Quiet meds share one reminder per time of day. Logging a dose clears its follow-ups.",
                )
                categorySummarySection(
                    category: .session,
                    header: "During a Session",
                    footer: "Timed from the typical onset and duration of each dose you log, for its substance and route. These are estimates from published data — Piru doesn't sense anything.",
                )
                categorySummarySection(
                    category: .safety,
                    header: "Safety & Supplies",
                    footer: "Totals include scheduled meds, as-needed doses, and everything else — the safety net doesn't care why you took it.",
                )

                quietHoursSection
            }
            .listRowBackground(CardBackground())
        }
        .themedPage()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
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

    private func categorySummarySection(
        category: NotificationCategory,
        header: LocalizedStringKey,
        footer: LocalizedStringKey,
    ) -> some View {
        Section {
            NavigationLink {
                NotificationTypeDetailSheet(
                    category: category,
                    nextFireDates: nextFireDates,
                    disabled: rowsDisabled,
                )
            } label: {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Label(category.title, systemImage: category.symbol)
                    let summary = enabledSummary(for: category)
                    Text(summary)
                        .captionSecondary()
                }
            }
            .disabled(rowsDisabled)
            .opacity(rowsDisabled ? 0.55 : 1)
        } header: {
            Text(header)
        } footer: {
            Text(footer)
        }
    }

    private func enabledSummary(for category: NotificationCategory) -> String {
        let types = category.types
        let enabled = types.filter { prefs.isTypeEnabled($0) }
        if enabled.count == types.count {
            return String(localized: "All on")
        } else if enabled.isEmpty {
            return String(localized: "All off")
        } else {
            let names = enabled.map { String(localized: $0.shortTitle) }
            return names.joined(separator: ", ")
        }
    }

    private var quietHoursSection: some View {
        Section {
            Toggle(isOn: quietHoursBinding) {
                Label("Quiet Hours", systemImage: "moon")
            }
            .tint(Theme.accent)
            .disabled(authStatus == .denied)
            if prefs.quietHoursEnabled {
                DatePicker(
                    "Start",
                    selection: quietTimeBinding(\.quietHoursStartMinutes, apply: { start in
                        prefs.setQuietHours(enabled: true, startMinutes: start)
                    }),
                    displayedComponents: .hourAndMinute,
                )
                .accessibilityLabel(Text("Start time"))
                DatePicker(
                    "End",
                    selection: quietTimeBinding(\.quietHoursEndMinutes, apply: { end in
                        prefs.setQuietHours(enabled: true, endMinutes: end)
                    }),
                    displayedComponents: .hourAndMinute,
                )
                .accessibilityLabel(Text("End time"))
            }
        } header: {
            Text("Quiet Hours")
        } footer: {
            Text("Session nudges, re-asks, and next-dose reminders inside this window stay silent. Routine reminders at times you set, and cumulative dose warnings, still come through.")
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
            Text("Show a Live Activity on your Lock Screen when tracking starts. You can also start one from any session.")
        }
    }

    // MARK: - Bindings

    private var pauseAllBinding: Binding<Bool> {
        Binding(
            get: { !prefs.masterEnabled },
            set: { prefs.setMasterEnabled(!$0) },
        )
    }

    private var quietHoursBinding: Binding<Bool> {
        Binding(
            get: { prefs.quietHoursEnabled },
            set: { prefs.setQuietHours(enabled: $0) },
        )
    }

    private func quietTimeBinding(
        _ keyPath: KeyPath<NotificationPreferencesStore, Int>,
        apply: @escaping (Int) -> Void,
    ) -> Binding<Date> {
        Binding(
            get: {
                let minutes = prefs[keyPath: keyPath]
                return Calendar.current.date(
                    bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now,
                ) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                apply((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            },
        )
    }

    // MARK: - Refresh

    private func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authStatus = settings.authorizationStatus
        await refreshNextFireDates()
    }

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

// MARK: - Notification Category

/// Groups notification types into the three spec sections.
nonisolated enum NotificationCategory {
    case reminders
    case session
    case safety

    var types: [NotificationType] {
        switch self {
        case .reminders: [.routine, .routineFollowUp, .nextDose]
        case .session: [.comedown, .phase, .hydration, .sleep, .checkIn]
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

// MARK: - Detail Sheet

/// Drill-in for a notification category: per-type toggles with explanations,
/// per-type Time Sensitive delivery, and (for reminders) the editable Ask Again
/// cadence — the sole editor of `NotificationPreferences.askAgainDefaultMinutes`.
struct NotificationTypeDetailSheet: View {
    let category: NotificationCategory
    let nextFireDates: [NotificationType: Date]
    let disabled: Bool

    @State private var prefs = NotificationPreferencesStore.shared
    @Query private var notificationPreferences: [NotificationPreferences]

    var body: some View {
        List {
            Group {
                typesSection

                if category.types.contains(where: \.supportsTimeSensitive) {
                    timeSensitiveSection
                }

                if category == .reminders {
                    askAgainSection
                }
            }
            .listRowBackground(CardBackground())
        }
        .themedPage()
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var typesSection: some View {
        Section {
            ForEach(category.types) { type in
                NotificationTypeRow(
                    type: type,
                    nextFireDate: nextFireDates[type],
                    disabled: disabled,
                )
            }
        } footer: {
            Text(category.sectionFooter)
        }
    }

    private var timeSensitiveSection: some View {
        Section {
            ForEach(category.types.filter(\.supportsTimeSensitive)) { type in
                Toggle(isOn: timeSensitiveBinding(type)) {
                    Label(type.rowTitle, systemImage: type.rowSymbol)
                }
                .tint(Theme.accent)
            }
        } header: {
            Text("Time Sensitive")
        } footer: {
            Text("Time Sensitive notifications can break through Focus modes and the notification summary. Turn off any you'd rather have wait.")
        }
        .disabled(disabled)
    }

    private var askAgainSection: some View {
        Section {
            let cadence = notificationPreferences.first?.askAgainDefaultMinutes ?? [10]
            ForEach(Array(cadence.enumerated()), id: \.offset) { index, _ in
                HStack {
                    Text("Re-ask \(index + 1)")
                    Spacer()
                    Picker("", selection: askAgainMinutesBinding(index: index)) {
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("15 min").tag(15)
                        Text("20 min").tag(20)
                        Text("30 min").tag(30)
                        Text("45 min").tag(45)
                        Text("60 min").tag(60)
                    }
                    .labelsHidden()
                }
            }
            Button {
                addReask()
            } label: {
                Label("Add Re-ask", systemImage: "plus.circle")
            }
            .disabled(cadence.count >= 4)
            if cadence.count > 1 {
                Button(role: .destructive) {
                    removeLastReask()
                } label: {
                    Label("Remove Last", systemImage: "minus.circle")
                }
            }
        } header: {
            Text("Ask Again")
        } footer: {
            Text("If a dose isn't logged, ask again after these intervals. Applies to every med. A med can override or opt out in its own settings. Re-asks never scold — they just ask.")
        }
    }

    // MARK: - Bindings

    private func timeSensitiveBinding(_ type: NotificationType) -> Binding<Bool> {
        Binding(
            get: { prefs.isTimeSensitiveEnabled(type) },
            set: { prefs.setTimeSensitive(type, $0) },
        )
    }

    private func askAgainMinutesBinding(index: Int) -> Binding<Int> {
        Binding(
            get: {
                let cadence = notificationPreferences.first?.askAgainDefaultMinutes ?? [10]
                return index < cadence.count ? cadence[index] : 10
            },
            set: { newValue in
                guard let record = notificationPreferences.first else { return }
                var cadence = record.askAgainDefaultMinutes
                if index < cadence.count {
                    cadence[index] = newValue
                    record.askAgainDefaultMinutes = cadence
                }
            },
        )
    }

    private func addReask() {
        guard let record = notificationPreferences.first else { return }
        var cadence = record.askAgainDefaultMinutes
        let last = cadence.last ?? 10
        cadence.append(min(last + 10, 60))
        record.askAgainDefaultMinutes = cadence
    }

    private func removeLastReask() {
        guard let record = notificationPreferences.first else { return }
        var cadence = record.askAgainDefaultMinutes
        guard cadence.count > 1 else { return }
        cadence.removeLast()
        record.askAgainDefaultMinutes = cadence
    }
}

extension NotificationCategory {
    var sectionFooter: LocalizedStringKey {
        switch self {
        case .reminders:
            "Quiet meds' reminders arrive silently — no buzz, no lock-screen wake. If you use iOS Scheduled Summary, they batch there."
        case .session:
            "Comedown alerts are armed per dose in Ramp-Down."
        case .safety:
            "Turning off the cumulative dose warning removes a safety net."
        }
    }
}

// MARK: - Permission header

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
                        .foregroundStyle(Color.successText)
                        .accessibilityHidden(true)
                }
            case .denied:
                Label {
                    Text("Notifications Are Off")
                } icon: {
                    Image(systemName: "bell.slash.fill")
                        .foregroundStyle(Theme.secondaryLabel)
                        .accessibilityHidden(true)
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
            .accessibilityHint(Text(type.rowWhy))
            Text(type.rowWhy)
                .captionSecondary()
                .accessibilityHidden(true)
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

extension NotificationType {
    var rowTitle: LocalizedStringKey {
        switch self {
        case .comedown: "Comedown Alerts"
        case .hydration: "Hydration Reminders"
        case .sleep: "Sleep Reminders"
        case .phase: "Phase Alerts"
        case .cumulative: "Cumulative Dose Warnings"
        case .routine: "Med Reminders"
        case .routineFollowUp: "Ask Again"
        case .nextDose: "Next-Dose Window"
        case .inventory: "Low Stock Alerts"
        case .checkIn: "Check-ins"
        }
    }

    var shortTitle: LocalizedStringResource {
        switch self {
        case .comedown: "Comedown"
        case .hydration: "Hydration"
        case .sleep: "Sleep"
        case .phase: "Phase"
        case .cumulative: "Cumulative"
        case .routine: "Reminders"
        case .routineFollowUp: "Ask Again"
        case .nextDose: "Next-Dose"
        case .inventory: "Low Stock"
        case .checkIn: "Check-ins"
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
        case .nextDose: "timer"
        case .inventory: "archivebox"
        case .checkIn: "quote.bubble"
        }
    }

    var rowWhy: LocalizedStringKey {
        switch self {
        case .comedown:
            "Warns you before a dose wears off, so the drop doesn't catch you off guard. Turned on per dose from its comedown alert screen."
        case .hydration:
            "Water nudges timed to your dose — stimulants and empathogens mask thirst."
        case .sleep:
            "A wind-down reminder late into long stimulant sessions, when sleep is the best recovery."
        case .phase:
            "Timing cues at onset, come-up, and peak so you can anchor what you feel to the timeline."
        case .cumulative:
            "A heads-up when your 12-hour total of one substance reaches a heavy range. Turning this off removes a safety net."
        case .routine:
            "A nudge at each med's set time so a dose never slips your mind. Tapping it opens Quick Log with that time's meds staged."
        case .routineFollowUp:
            "Asks again a little later if a med still isn't logged — like snooze for an alarm. Adjustable per med."
        case .nextDose:
            "After you log a med you've opted in, a nudge when its next dose window opens. An estimate, not medical advice — opt in per med."
        case .inventory:
            "A heads-up when something you track runs low or out — before the empty bottle surprises you."
        case .checkIn:
            "\"How is it going?\" at set points in a session, opening a timestamped note. Turned on per session; off unless you ask."
        }
    }
}
