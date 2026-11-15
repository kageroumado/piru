import SwiftUI

/// Overlapping avatars for the people in a shared session: up to three, then
/// "+N" for the rest.
struct ProfileAvatarStack: View {
    let profiles: [PiruProfile]
    var diameter: CGFloat = 18

    private static let maxShown = 3

    var body: some View {
        HStack(spacing: -diameter * 0.3) {
            ForEach(profiles.prefix(Self.maxShown)) { profile in
                ProfileAvatarView(profile, diameter: diameter)
                    .padding(1.5)
                    .background(Theme.background, in: Circle())
            }
            if profiles.count > Self.maxShown {
                Text(verbatim: "+\(profiles.count - Self.maxShown)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                    .padding(.leading, diameter * 0.4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Shared with \(profiles.map(\.name).formatted(.list(type: .and)))"))
    }
}

/// The Journal's mark on a shared session: the other people in it, read from
/// ``SharedExperienceStore/participantsBySession`` (no fetch). Draws nothing
/// for a session only this profile had.
struct SharedSessionMark: View {
    let sessionID: UUID
    var diameter: CGFloat = 18

    @Environment(\.profileDirectory) private var directory

    var body: some View {
        let ids = SharedExperienceStore.shared.participantsBySession[sessionID] ?? []
        if !ids.isEmpty {
            ProfileAvatarStack(profiles: ids.compactMap(directory.profile(id:)), diameter: diameter)
        }
    }
}

extension View {
    /// Keep ``SharedExperienceStore``'s Journal index current: re-read on every
    /// dose-log commit, profile change and switch. Hosted by the Journal.
    func refreshesSharedSessionMarks() -> some View {
        modifier(SharedSessionIndexRefresh())
    }
}

private struct SharedSessionIndexRefresh: ViewModifier {
    @Environment(\.profileDirectory) private var directory

    func body(content: Content) -> some View {
        content.task(id: TaskKey(
            revision: DoseLogService.shared.revision,
            active: directory.activeProfileID,
            profiles: directory.profiles.map(\.id),
        )) {
            await SharedExperienceStore.shared.refreshIndex()
        }
    }

    private struct TaskKey: Hashable {
        let revision: Int
        let active: UUID
        let profiles: [UUID]
    }
}
