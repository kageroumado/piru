import SwiftUI
import UIKit

/// Settings for the optional heart-rate / blood-pressure overlay on sessions.
///
/// Mirrors ``BodyWeightView`` and is built around the HealthKit read-permission
/// gotcha (see ``HealthKitVitals``): iOS never tells us whether read access is
/// granted, so we can't show a reliable status and it can break silently. The
/// defences here: we request access when the toggle is turned on **and** whenever
/// this screen appears while enabled (harmless — the sheet only shows the first
/// time each type is undetermined), expose an explicit "Connect Apple Health"
/// button the user can tap to force the prompt, and always offer a deep link to
/// Settings ▸ Health so a user whose data is missing can check/re-grant.
struct SessionVitalsView: View {
    @AppStorage("showSessionVitals", store: UserDefaults(suiteName: "group.dev.yumeji.piru"))
    private var showSessionVitals = false
    @State private var health = HealthKitVitals.shared
    @State private var isRequesting = false

    var body: some View {
        Form {
            toggleSection
            if showSessionVitals, health.isAvailable { accessSection }
            whySection
            if !health.isAvailable { unavailableSection }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Heart Rate")
        .navigationBarTitleDisplayMode(.inline)
        // Re-request on appear when already enabled: the sheet only surfaces the
        // first time (undetermined types), so this catches a persisted-on toggle
        // whose original request never happened, without nagging afterwards.
        .task {
            if showSessionVitals, health.isAvailable { await health.requestAccess() }
        }
    }

    private var toggleSection: some View {
        Section {
            Toggle(isOn: $showSessionVitals) {
                Label("Show on sessions", systemImage: "heart.text.square")
            }
            .tint(Theme.accent)
            .disabled(!health.isAvailable)
            .onChange(of: showSessionVitals) { _, isOn in
                if isOn { Task { await health.requestAccess() } }
            }
        } footer: {
            Text("Overlays your Apple Watch heart rate — and any blood-pressure readings — on each session's timeline, and shows how your heart responded to each dose. Read-only; you can turn Piru's access off anytime in Settings ▸ Health ▸ Data Access. With no data for a session, nothing is shown.")
        }
        .listRowBackground(CardBackground())
    }

    /// Explicit access controls. Because iOS won't report read-permission status,
    /// there's no green "granted" checkmark to show — instead we give the user the
    /// two actions that always work: re-request the prompt, and jump to Settings.
    private var accessSection: some View {
        Section {
            Button {
                Task {
                    isRequesting = true
                    await health.requestAccess()
                    isRequesting = false
                }
            } label: {
                HStack {
                    Label("Connect Apple Health", systemImage: "heart.text.square")
                    Spacer()
                    if isRequesting { ProgressView() }
                }
            }
            .disabled(isRequesting)

            Button("Open Health Settings") { openHealthSettings() }
                .font(.subheadline)
        } footer: {
            Text("Not seeing your heart rate on a session? Apple doesn't tell apps whether read access was granted, so tap Connect to (re)request it, or open Settings ▸ Health ▸ Data Access ▸ Piru and switch Heart Rate and Blood Pressure on.")
        }
        .listRowBackground(CardBackground())
    }

    private func openHealthSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var whySection: some View {
        Section {
            Text("A modelled curve predicts what a dose *should* do; your heart rate shows what your body *actually* did — stimulants and alcohol both raise it, so seeing the two together turns a prediction into a record. A blood-pressure reading is worth attaching too: you often take one *because* you felt off.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryLabel)
        } header: {
            Text("Why we ask")
        }
        .listRowBackground(CardBackground())
    }

    private var unavailableSection: some View {
        Section {
            Text("Apple Health isn't available on this device.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .listRowBackground(CardBackground())
    }
}

#Preview {
    NavigationStack { SessionVitalsView() }
}
