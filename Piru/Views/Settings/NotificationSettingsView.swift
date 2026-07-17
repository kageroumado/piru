import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Live Activity and reminder toggles, grouped away from the main Settings
/// screen for progressive disclosure.
struct NotificationSettingsView: View {
    @AppStorage("liveActivityEnabled") private var autoLiveActivity = false
    @AppStorage("wellnessNotificationsEnabled") private var wellnessNotificationsEnabled = false
    @AppStorage("phaseNotificationsEnabled") private var phaseNotificationsEnabled = false

    var body: some View {
        List {
            Group {
                Section {
                    Toggle(isOn: $autoLiveActivity) {
                        Label("Automatic Live Activity", systemImage: "bolt.heart")
                    }
                    .tint(Theme.accent)
                } footer: {
                    Text("Automatically show a Live Activity on the Lock Screen and Dynamic Island when you start tracking a substance. You can also start one manually from a day or entry's detail view.")
                }

                Section {
                    Toggle(isOn: $wellnessNotificationsEnabled) {
                        Label("Wellness Reminders", systemImage: "heart.text.clipboard")
                    }
                    .tint(Theme.accent)
                    Toggle(isOn: $phaseNotificationsEnabled) {
                        Label("Phase Notifications", systemImage: "bell.badge.waveform")
                    }
                    .tint(Theme.accent)
                } footer: {
                    Text("Wellness reminders send hydration and sleep nudges automatically. Phase notifications alert you at onset, come-up, and peak — requires a substance with duration data.")
                }
            }
            .listRowBackground(CardBackground())
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Journal
