import SwiftUI

/// The active profile's avatar, leading the trailing toolbar group on every
/// tab root once a second profile exists. Its menu lists everyone, the active
/// one checked, then Manage Profiles.
struct ProfileMenuButton: View {
    @Environment(\.profileDirectory) private var directory
    @Environment(\.appNavigator) private var navigator

    var body: some View {
        let active = directory.activeProfile
        Menu {
            Picker(selection: selection) {
                ForEach(directory.profiles) { profile in
                    Label {
                        Text(verbatim: profile.name)
                    } icon: {
                        ProfileAvatarImage.image(for: profile)
                    }
                    .tag(profile.id)
                }
            } label: {
                Text("Profiles")
            }
            .pickerStyle(.inline)
            Section {
                Button("Manage Profiles…") {
                    guard navigator.sheetStack.isEmpty else { return }
                    navigator.present(.profiles)
                }
            }
        } label: {
            ProfileAvatarView(active, diameter: 36)
        }
        .menuOrder(.fixed)
        .accessibilityLabel(Text("Profile: \(active.name)"))
        .accessibilityInputLabels([Text(verbatim: active.name), Text("Profile")])
    }

    private var selection: Binding<UUID> {
        Binding(
            get: { directory.activeProfileID },
            set: { id in Task(name: "Switch profile") { await ProfileSwitcher.switchTo(id) } },
        )
    }
}

/// Puts ``ProfileMenuButton`` first in a tab root's trailing toolbar group,
/// with a gap after it so it reads as its own control.
struct ProfileToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        if ProfileDirectory.shared.hasMultipleProfiles {
            #if os(Android)
                // Unreachable on Android, which has one profile; SkipUI lacks
                // the shared-background modifier.
                ToolbarItem(placement: .platformTopBarTrailing) {
                    ProfileMenuButton()
                }
            #else
                // The avatar is its own round control: no glass capsule around it.
                ToolbarItem(placement: .platformTopBarTrailing) {
                    ProfileMenuButton()
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarSpacer(.fixed, placement: .platformTopBarTrailing)
            #endif
        }
    }
}
