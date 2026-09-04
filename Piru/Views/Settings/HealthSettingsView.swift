import SwiftUI

/// Apple Health settings — body weight and the session heart-rate / blood-pressure overlay in one
/// clean screen. Weight lives in a **single** editable row (nudge it inline, or pull it from
/// Health); the Apple Health section owns the one combined connect action and the overlay toggle.
/// Health hands Piru weight + HR + BP through a single system sheet, so there is exactly one
/// authorization prompt here — never a separate weight-vs-vitals flow.
struct HealthSettingsView: View {
    @State private var profile = UserProfileStore.shared
    @State private var bodyMass = HealthKitBodyMass.shared
    @State private var vitals = HealthKitVitals.shared
    @AppStorage("showSessionVitals", store: UserDefaults(suiteName: "group.dev.yumeji.piru"))
    private var showSessionVitals = false

    @State private var weightKg: Double = UserProfileStore.shared.weightKg ?? UserProfileStore.defaultWeightKg
    /// Suppresses the "user edited → save as manual" side effect when *we* set the
    /// weight (a Health sync or a reset), so a pulled value keeps its provenance.
    @State private var isProgrammaticWeightChange = false
    @State private var isConnecting = false
    /// Whether "Connect" would still surface a prompt. Once everything grantable is
    /// answered, the row is hidden — tapping it would only flash an empty sheet.
    /// Nil until the first async status check resolves, so the row doesn't flicker.
    @State private var connectWouldPrompt: Bool?

    var body: some View {
        Form {
            weightSection
            if vitals.isAvailable {
                if connectWouldPrompt == true { connectSection }
                overlaySection
            } else {
                unavailableSection
            }
        }
        .themedPage()
        .navigationTitle("Apple Health")
        .inlineNavigationTitle()
        .task { connectWouldPrompt = await vitals.connectWouldPrompt() }
    }

    // MARK: - Weight (one row: shows the value, edits it, no separate status/manual sections)

    private var weightSection: some View {
        Section {
            InventoryStepperRow(value: $weightKg, unit: "kg", label: "Your body weight", stepBasis: 10)
                .onChange(of: weightKg) { _, newValue in
                    if isProgrammaticWeightChange {
                        isProgrammaticWeightChange = false
                        return
                    }
                    profile.setManualWeight(newValue)
                }
            if profile.weightKg != nil {
                Button(action: useAverageWeight) {
                    Text("Use the average (60 kg)")
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        } header: {
            Text("Your weight")
        } footer: {
            Text(weightFootnote)
        }
        .listRowBackground(CardBackground())
    }

    /// Source + why, in one line, so weight needs no second "why we ask" section.
    private var weightFootnote: LocalizedStringResource {
        switch profile.weightSource {
        case .healthKit:
            "Synced from Apple Health. Your weight sizes every dose estimate — the same dose hits harder the less you weigh."
        case .manual:
            "Entered manually. Your weight sizes every dose estimate — the same dose hits harder the less you weigh."
        case .estimated:
            "Using the average 60 kg. Set yours above so estimates fit your body — the same dose hits harder the less you weigh."
        }
    }

    // MARK: - Apple Health (access) — only while there's still something to grant

    private var connectSection: some View {
        Section {
            Button {
                Task { await connect() }
            } label: {
                HStack {
                    Label("Connect Apple Health", systemImage: "heart.text.square")
                    Spacer()
                    if isConnecting { ProgressView() }
                }
            }
            .disabled(isConnecting)
            .accessibilityValue(isConnecting ? Text("Connecting…") : Text(verbatim: ""))
        } header: {
            Text("Apple Health")
        } footer: {
            Text("Connect once to pull your body weight, heart rate, and blood pressure from Health — all read-only, on your device. Workouts come too, only so a run isn't read as a dose's effect.")
        }
        .listRowBackground(CardBackground())
    }

    // MARK: - Heart data (the session overlay)

    private var overlaySection: some View {
        Section {
            Toggle(isOn: $showSessionVitals) {
                Label("Show heart data on sessions", systemImage: "waveform.path.ecg")
            }
            .tint(Theme.accent)
            .onChange(of: showSessionVitals) { _, isOn in
                // Only prompt if there's actually something undetermined to grant;
                // otherwise just flip the overlay on (no empty-sheet flash).
                if isOn, !isConnecting, connectWouldPrompt == true { Task { await connect() } }
            }
        } header: {
            Text("Heart data")
        } footer: {
            Text("Overlays your heart rate and blood pressure on each session's timeline — read-only. If something didn't connect — blood pressure especially, which iOS doesn't always prompt for — open **Settings ▸ Privacy & Security ▸ Health ▸ Piru** and turn it on there.")
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

    // MARK: - Actions

    /// The one combined flow: a single Health sheet covering weight + heart rate +
    /// blood pressure, the overlay switched on, then a silent weight read.
    private func connect() async {
        guard !isConnecting else { return }
        isConnecting = true
        await HealthKitVitals.shared.requestFullAccess()
        showSessionVitals = true
        let result = await bodyMass.syncLatest()
        connectWouldPrompt = await vitals.connectWouldPrompt()
        isConnecting = false
        if case let .updated(kg) = result { setWeightProgrammatically(kg) }
    }

    /// Revert to the population-average default (not a personal estimate — just the
    /// fallback Piru uses when no weight is set).
    private func useAverageWeight() {
        profile.clearWeight()
        setWeightProgrammatically(UserProfileStore.defaultWeightKg)
    }

    /// Set the stepper's value without it counting as a manual edit (so a Health
    /// sync or reset doesn't flip the source to `.manual`).
    private func setWeightProgrammatically(_ kg: Double) {
        guard weightKg != kg else { return }
        isProgrammaticWeightChange = true
        weightKg = kg
    }
}

#Preview {
    NavigationStack { HealthSettingsView() }
}
