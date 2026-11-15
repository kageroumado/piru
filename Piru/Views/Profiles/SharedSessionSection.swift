import SwiftUI

/// The session screen's "With Alice and Bob": below your own entries, each
/// other person in the shared experience with their avatar, name, doses and a
/// small curve of their own doses in their profile color. Tapping a person
/// opens a read-only peek of their session. Draws nothing until someone else
/// in the experience has logged a dose.
struct SharedSessionSection: View {
    let experienceID: UUID
    /// Read by the session screen's model; `nil` until the first read lands,
    /// when the store's cache answers if it is still current.
    let participants: [SharedParticipant]?

    @Environment(\.profileDirectory) private var directory

    var body: some View {
        let shown = participants ?? SharedExperienceStore.shared.cachedParticipants(for: experienceID) ?? []
        if !shown.isEmpty {
            Section {
                ForEach(shown) { participant in
                    if let profile = directory.profile(id: participant.id) {
                        SharedParticipantRow(profile: profile, participant: participant, experienceID: experienceID)
                    }
                }
            } header: {
                Text(verbatim: SharedExperienceStore.sectionTitle(names: shown.compactMap { directory.profile(id: $0.id)?.name }))
            }
        }
    }
}

/// One person in ``SharedSessionSection``: avatar and name, a line per dose,
/// and their curve.
private struct SharedParticipantRow: View {
    let profile: PiruProfile
    let participant: SharedParticipant
    let experienceID: UUID

    @Environment(\.appNavigator) private var navigator
    @AppStorage("stackRedoses", store: UserDefaults(suiteName: AppIdentity.appGroup)) private var stackRedoses = true

    var body: some View {
        Button {
            navigator.present(.sharedSessionPeek(experienceID: experienceID, profileID: profile.id))
        } label: {
            HStack(spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.md) {
                        ProfileAvatarView(profile, diameter: 22)
                        Text(verbatim: profile.name)
                            .font(.headline)
                    }
                    ForEach(participant.doseLines.enumerated(), id: \.offset) { _, line in
                        Text(verbatim: line)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Spacing.md)
                if !participant.personStates.isEmpty || !participant.personMarkers.isEmpty {
                    TimelineGraphView(
                        substances: participant.personStates,
                        currentTime: .now,
                        compact: true,
                        markers: participant.personMarkers,
                        stackRedoses: stackRedoses,
                        showNowIndicator: false,
                        dayBounded: true,
                    )
                    .equatable()
                    .frame(width: 72, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.input))
                    .allowsHitTesting(false)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.tertiaryLabel)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Shows \(profile.name)'s session"))
    }
}
