import SwiftUI

/// A dismissible one-row offer of the vitals overlay to users who never opted in —
/// its "Turn On" surfaces the same single combined Health sheet as everywhere
/// else. Owns its own opt-in state: flipping `showSessionVitals` (an app-group
/// `@AppStorage` the detail view also reads) re-runs the detail's vitals task,
/// and `didOfferSessionVitals` retires the banner.
struct VitalsOfferBanner: View {
    /// Opt-in: overlay Apple Health heart rate / blood pressure on the session.
    /// Stored in the app-group suite so it's consistent app-wide.
    @AppStorage(HealthKitVitals.overlayKey, store: HealthKitVitals.settingsStore)
    private var showSessionVitals = false
    /// One-time discovery flag: set once the user turns the overlay on OR dismisses
    /// the banner, after which it never reappears. Main-app UI state, so the default
    /// suite (not the app group) is fine.
    @AppStorage("didOfferSessionVitals") private var didOfferSessionVitals = false
    /// Drives the banner's connect button while its Health sheet is up.
    @State private var isConnectingVitals = false

    var body: some View {
        Section {
            HStack(spacing: Spacing.lg) {
                Image(systemName: "heart.text.square")
                    .foregroundStyle(VitalsPalette.heart)
                    .accessibilityHidden(true)
                Text("Heart rate on this graph")
                Spacer(minLength: Spacing.md)
                if isConnectingVitals {
                    ProgressView().controlSize(.mini)
                } else {
                    Button("Turn On") {
                        Task { await enableVitalsFromOffer() }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.accent)
                }
                Button(action: dismissVitalsOffer) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryLabel)
                        .minimumHitTarget()
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Dismiss"))
            }
        }
    }

    /// Turn the overlay on from the banner: the same single combined Health sheet
    /// (weight + heart rate + blood pressure), then flip the overlay on and record
    /// that we've offered so the banner never returns.
    private func enableVitalsFromOffer() async {
        guard !isConnectingVitals else { return }
        isConnectingVitals = true
        // Skip the request (and its empty-sheet flash) if access is already decided.
        if await HealthKitVitals.shared.connectWouldPrompt() {
            await HealthKitVitals.shared.requestFullAccess()
        }
        _ = await HealthKitBodyMass.shared.syncLatest()
        isConnectingVitals = false
        didOfferSessionVitals = true
        showSessionVitals = true
    }

    /// Dismiss the banner for good — showing it counts as having offered, whether
    /// or not they turned it on.
    private func dismissVitalsOffer() {
        withAnimation(.smooth(duration: 0.25)) { didOfferSessionVitals = true }
    }
}
