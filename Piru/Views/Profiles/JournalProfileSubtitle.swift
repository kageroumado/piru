import SwiftUI

extension View {
    /// "Alice's journal" under the Journal's large title, with a dot in her
    /// color, whenever the open journal is not the owner's: the line that stops
    /// a dose landing in the wrong person's journal.
    func journalProfileSubtitle(enabled: Bool) -> some View {
        modifier(JournalProfileSubtitle(enabled: enabled))
    }
}

private struct JournalProfileSubtitle: ViewModifier {
    @Environment(\.profileDirectory) private var directory
    let enabled: Bool

    func body(content: Content) -> some View {
        let profile = directory.activeProfile
        if enabled, !profile.isOwner {
            #if os(iOS)
                content.toolbar {
                    ToolbarItem(placement: .largeSubtitle) {
                        JournalOwnerLabel(profile: profile)
                    }
                }
            #elseif os(macOS)
                content.navigationSubtitle(Text("\(profile.name)'s journal"))
            #else
                // Android has one profile, so never another's journal.
                content
            #endif
        } else {
            content
        }
    }
}

/// The dot and the name, read as one element.
private struct JournalOwnerLabel: View {
    let profile: PiruProfile

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(profile.color.p3.color)
                .frame(width: 8, height: 8)
            Text("\(profile.name)'s journal")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .accessibilityElement(children: .combine)
    }
}
