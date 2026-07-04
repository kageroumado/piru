import SwiftUI

/// Body-weight step. Weight is the denominator that turns a dose into an exposure, so getting it
/// right makes every estimate personal. The value starts pre-filled at the population average, and
/// the +/- stepper (the same control used in Inventory and quick-log) lets the user nudge it to
/// their real weight without ever opening the keyboard — or they can pull it from Apple Health.
/// "Continue" saves whatever is shown; "I'll set this later" keeps the estimated average.
struct OnboardingWeightStep: View {
    @Environment(\.onboardingNav) private var nav
    @State private var health = HealthKitBodyMass.shared

    @State private var weightKg: Double = UserProfileStore.shared.weightKg ?? UserProfileStore.defaultWeightKg
    /// The kilograms Apple Health returned, if any — so an unchanged Health value keeps its
    /// provenance (launch auto-sync) while a nudged value becomes a manual entry.
    @State private var healthValue: Double?
    @State private var connecting = false
    @State private var noReadNote = false
    @State private var error: String?

    var body: some View {
        OnboardingLayout(
            title: "Your body weight",
            subtitle: "The same dose hits harder the less you weigh. Set yours so estimates fit your body — otherwise Piru assumes an average adult, about 60 kg.",
        ) {
            OnboardingIconHero(symbol: "figure")
        } mid: {
            VStack(spacing: 14) {
                InventoryStepperRow(value: $weightKg, unit: "kg", stepBasis: 10)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .themeCapsule()

                connectButton

                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                } else if healthValue != nil {
                    syncNote
                } else if noReadNote {
                    noReadFallback
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
        } footer: {
            OnboardingPrimaryButton(title: "Continue", action: saveAndAdvance)
            OnboardingSecondaryButton(title: "I'll Set This Later", action: nav.advance)
        }
    }

    private var connectButton: some View {
        Button {
            Task { await connectHealth() }
        } label: {
            HStack(spacing: 8) {
                if connecting {
                    ProgressView()
                } else {
                    Image(systemName: "heart.text.square.fill")
                }
                Text(healthValue == nil ? "Use Apple Health" : "Re-read from Health")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .tint(Theme.accent)
        .disabled(connecting)
    }

    private var syncNote: some View {
        Label("Synced from Apple Health, and kept up to date. Check the number looks right.", systemImage: "checkmark.circle")
            .font(.footnote)
            .foregroundStyle(Theme.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var noReadFallback: some View {
        Text("Couldn't read a weight from Health — you may not have granted access, or haven't logged one there. Set it above instead.")
            .font(.footnote)
            .foregroundStyle(Theme.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func connectHealth() async {
        connecting = true
        noReadNote = false
        error = nil
        let result = await health.requestAndSync()
        connecting = false
        switch result {
        case let .updated(kg):
            healthValue = kg
            weightKg = kg
        case .noData, .unavailable:
            noReadNote = true
        }
    }

    private func saveAndAdvance() {
        guard UserProfileStore.weightRangeKg.contains(weightKg) else {
            error = String(localized: "Enter a weight between 20 and 300 kg.")
            return
        }
        if let healthValue, abs(healthValue - weightKg) < 0.05 {
            UserProfileStore.shared.setHealthKitWeight(weightKg)
        } else {
            UserProfileStore.shared.setManualWeight(weightKg)
        }
        nav.advance()
    }
}

#Preview {
    OnboardingWeightStep()
        .background(Theme.background)
}
