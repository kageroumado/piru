import SwiftUI

/// The active profile's avatar, just before the ellipsis on every tab root
/// once a second profile exists. Its menu lists everyone, the active one
/// checked, then Manage Profiles.
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
            ProfileGlassAvatar(profile: active)
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

/// ``ProfileMenuButton`` as a toolbar item of its own, with the same fixed gap
/// after it that separates the screen's other controls. Placed by each screen
/// right before its ellipsis.
struct ProfileToolbarItem: ToolbarContent {
    /// A gap before the avatar too, for a screen whose own items come right
    /// before it without one.
    var leadingGap = false

    var body: some ToolbarContent {
        if ProfileDirectory.shared.hasMultipleProfiles {
            #if os(Android)
                // Unreachable on Android, which has one profile; SkipUI lacks
                // the shared-background modifier.
                ToolbarItem(placement: .platformTopBarTrailing) {
                    ProfileMenuButton()
                }
            #else
                if leadingGap {
                    ToolbarSpacer(.fixed, placement: .platformTopBarTrailing)
                }
                // The avatar draws its own glass (``ProfileGlassAvatar``), so the
                // toolbar's shared capsule stays off.
                ToolbarItem(placement: .platformTopBarTrailing) {
                    ProfileMenuButton()
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarSpacer(.fixed, placement: .platformTopBarTrailing)
            #endif
        }
    }
}

/// The avatar as a toolbar control: the monogram or emoji on a circle of glass
/// tinted in the profile's color, the size of a system toolbar button. The
/// glass is the avatar's own, so the image covers the whole control.
struct ProfileGlassAvatar: View {
    let profile: PiruProfile

    private var diameter: CGFloat {
        #if os(macOS)
            28
        #else
            44
        #endif
    }

    var body: some View {
        Text(verbatim: profile.avatar.text)
            .font(.system(
                size: diameter * (profile.avatar.kind == .emoji ? 0.5 : 0.4),
                weight: .semibold,
                design: .rounded,
            ))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: diameter, height: diameter)
        #if os(Android)
            .background(profile.color.p3.color, in: Circle())
        #else
            .glassEffect(.regular.tint(profile.color.p3.color).interactive(), in: .circle)
        #endif
            .contentShape(.circle)
            .accessibilityHidden(true)
    }
}
