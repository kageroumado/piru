import SwiftUI

/// Offered once per session, only while a psychedelic or dissociative dose is
/// still in its window: turn on timed "How is it going?" prompts. Accepting
/// stores a cadence on the session and schedules it; dismissing records the
/// offer so it never returns for this session.
struct CheckInOfferBanner: View {
    let session: Session

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HStack(alignment: .top, spacing: Spacing.xl) {
                    Image(systemName: "quote.bubble")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Check in as it unfolds?")
                            .sectionLabel()
                        Text("A quiet prompt at a few points in the session, each opening a timestamped note. Off unless you turn it on; stops after eight hours.")
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
                        enable(.ladder)
                    } label: {
                        Text("T+30 m · 1 h · 2 h · 4 h · 6 h")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accent)
                    Button {
                        enable(.everyHour)
                    } label: {
                        Text("Every hour")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.regular)
                .sectionLabel()
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    private func enable(_ cadence: CheckInScheduler.Cadence) {
        withAnimation(.smooth(duration: 0.25)) {
            session.checkInOffered = true
            session.checkInIntervalMinutes = cadence.storedMinutes
        }
        Task {
            _ = await DoseNotificationManager.requestAuthorization()
            CheckInScheduler.sync(session: session)
        }
    }

    private func dismiss() {
        withAnimation(.smooth(duration: 0.25)) { session.checkInOffered = true }
    }
}
