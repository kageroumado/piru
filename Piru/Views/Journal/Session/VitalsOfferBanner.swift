import SwiftUI

/// A dismissible info card (styled like the note row) that introduces the vitals
/// overlay to users who never opted in — its "Turn On" surfaces the same single
/// combined Health sheet as everywhere else. Owns its own opt-in state: flipping
/// `showSessionVitals` (an app-group `@AppStorage` the detail view also reads)
/// re-runs the detail's vitals task, and `didOfferSessionVitals` retires the banner.
struct VitalsOfferBanner: View {
    /// Opt-in: overlay Apple Health heart rate / blood pressure on the session.
    /// Stored in the app-group suite so it's consistent app-wide.
    @AppStorage("showSessionVitals", store: UserDefaults(suiteName: "group.dev.yumeji.piru"))
    private var showSessionVitals = false
    /// One-time discovery flag: set once the user turns the overlay on OR dismisses
    /// the banner, after which it never reappears. Main-app UI state, so the default
    /// suite (not the app group) is fine.
    @AppStorage("didOfferSessionVitals") private var didOfferSessionVitals = false
    /// Drives the banner's connect button while its Health sheet is up.
    @State private var isConnectingVitals = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "heart.text.square")
                        .font(.title2)
                        .foregroundStyle(VitalsPalette.heart)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("See your heart rate here")
                            .font(.subheadline.weight(.semibold))
                        Text("Connect Apple Health to overlay how your body responded to each dose — read-only.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button(action: dismissVitalsOffer) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.secondaryLabel)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Dismiss"))
                }
                Button {
                    Task { await enableVitalsFromOffer() }
                } label: {
                    HStack(spacing: 8) {
                        if isConnectingVitals { ProgressView().controlSize(.mini) }
                        Text(isConnectingVitals ? "Connecting…" : "Turn On Apple Health")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.regular)
                .tint(Theme.accent)
                .disabled(isConnectingVitals)
            }
            .padding(.vertical, 4)
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
