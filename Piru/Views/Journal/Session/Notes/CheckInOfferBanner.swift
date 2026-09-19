import SwiftUI

/// Offered once per session, while a dose is still in its window: turn on timed
/// "How is it going?" prompts. Accepting stores the times on the session and
/// schedules them; dismissing records the offer so it never returns for this
/// session.
///
/// The primary button offers **this session's own times** — read off the phase
/// boundaries of what was actually taken (``CheckInLadder``), so a long session
/// is asked about several times and a short one once or twice. A fixed hourly
/// run stays reachable from the session menu; it is not what gets offered,
/// because an interval is a guess where the curve is an answer.
struct CheckInOfferBanner: View {
    let session: Session
    @Environment(\.appNavigator) private var navigator
    @State private var suggested: [Int] = []

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HStack(alignment: .top, spacing: Spacing.xl) {
                    Image(systemName: "quote.bubble")
                        .font(.piru(.title2))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Check in as it unfolds?")
                            .sectionLabel()
                        Text("A quiet prompt at a few points in the session, each opening a timestamped note. Off unless you turn it on, and you pick the times.")
                            .captionSecondary()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.secondaryLabel)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Dismiss"))
                }
                VStack(spacing: Spacing.md) {
                    Button {
                        useSuggested()
                    } label: {
                        VStack(spacing: 2) {
                            Text(suggested.isEmpty ? "Every hour" : "Use these times")
                            if !suggested.isEmpty {
                                Text(verbatim: CheckInLadder.summary(suggested))
                                    .font(.caption2.monospacedDigit())
                                    .opacity(Theme.Opacity.strong)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .skinButtonStyle(.prominent)
                    .tint(Theme.accent)
                    Button {
                        session.checkInOffered = true
                        navigator.present(.checkInSchedule(sessionID: session.id))
                    } label: {
                        Text("Pick my own times")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.regular)
                .sectionLabel()
            }
            .padding(.vertical, Spacing.xs)
        }
        .task {
            await SubstanceStore.shared.ensureAllLoaded()
            suggested = CheckInLadder.suggestedOffsets(for: session)
        }
    }

    /// Take the derived times, or fall back to the hourly run when nothing in
    /// the session models a curve to read them off.
    private func useSuggested() {
        guard !suggested.isEmpty else { return enable(.everyHour) }
        withAnimation(.smooth(duration: 0.25)) {
            session.checkInOffered = true
            session.checkInOffsetMinutes = suggested
            session.checkInIntervalMinutes = CheckInScheduler.Cadence.custom.storedMinutes
        }
        schedule()
    }

    private func enable(_ cadence: CheckInScheduler.Cadence) {
        withAnimation(.smooth(duration: 0.25)) {
            session.checkInOffered = true
            session.checkInIntervalMinutes = cadence.storedMinutes
        }
        schedule()
    }

    private func schedule() {
        Task {
            _ = await DoseNotificationManager.requestAuthorization()
            CheckInScheduler.sync(session: session)
        }
    }

    private func dismiss() {
        CheckInScheduler.recordOfferDeclined()
        withAnimation(.smooth(duration: 0.25)) { session.checkInOffered = true }
    }
}
