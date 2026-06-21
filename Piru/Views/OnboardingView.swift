import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled = false
    @AppStorage("wellnessNotificationsEnabled") private var wellnessNotificationsEnabled = false
    @State private var useHealthWeight = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Header
            VStack(spacing: 12) {
                Image(systemName: "heart.text.clipboard")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)

                Text("Welcome to Piru")
                    .font(.largeTitle.weight(.bold))

                Text("A few things to set up before you start.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .padding(.bottom, 40)

            // Feature cards
            VStack(spacing: 16) {
                featureToggle(
                    icon: "bolt.heart",
                    title: "Live Activity",
                    description: "Track active substances on your Lock Screen and Dynamic Island.",
                    isOn: $liveActivityEnabled,
                )

                featureToggle(
                    icon: "heart.text.clipboard",
                    title: "Wellness Reminders",
                    description: "Get hydration and sleep nudges automatically when you log a dose.",
                    isOn: $wellnessNotificationsEnabled,
                )

                if HealthKitBodyMass.shared.isAvailable {
                    featureToggle(
                        icon: "figure",
                        title: "Use Body Weight",
                        description: "Read your weight from Apple Health so estimates fit your body — a drink hits harder the less you weigh. Read-only; change anytime in Settings.",
                        isOn: $useHealthWeight,
                    )
                    .onChange(of: useHealthWeight) { _, on in
                        guard on else { return }
                        Task {
                            let result = await HealthKitBodyMass.shared.requestAndSync()
                            // If the user flipped the toggle back off while the request was in
                            // flight, undo the write so the stored state matches the toggle.
                            if !useHealthWeight, case .updated = result {
                                UserProfileStore.shared.clearWeight()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Continue button
            Button {
                hasCompletedOnboarding = true
                dismiss()
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .interactiveDismissDisabled()
    }

    private func featureToggle(
        icon: String,
        title: LocalizedStringResource,
        description: LocalizedStringResource,
        isOn: Binding<Bool>,
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Toggle(isOn: isOn) { Text(title) }
                .labelsHidden()
                .tint(Theme.accent)
        }
        .padding(16)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
    }
}
