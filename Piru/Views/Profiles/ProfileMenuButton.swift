import SwiftUI

/// The active profile's avatar at the leading edge of every tab root once a
/// second profile exists. Its menu lists everyone, the active one
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

/// ``ProfileMenuButton`` as a toolbar item of its own at the leading edge,
/// apart from the screen's trailing controls.
struct ProfileToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        if ProfileDirectory.shared.hasMultipleProfiles {
            #if os(macOS)
                // The avatar draws its own glass (``ProfileGlassAvatar``), so the
                // toolbar's shared capsule stays off.
                ToolbarItem(placement: .platformTopBarLeading) {
                    ProfileMenuButton()
                }
                .sharedBackgroundVisibility(.hidden)
            #else
                ToolbarItem(placement: .platformTopBarLeading) {
                    ProfileMenuButton()
                }
            #endif
        }
    }
}

/// The avatar as a toolbar control: the photo, or the monogram or emoji on a
/// circle in the profile's color.
///
/// On a phone it fills the toolbar's own glass circle. The bar lays the label
/// out at its 36-point content height, so the avatar is drawn at the circle's
/// full 44 points and hangs over that slot by 4 points a side. Keep it inside
/// the bar's glass: given its own glass or a 44-point frame, the menu's close
/// animation clips it to 36 points and cuts off its top and bottom.
struct ProfileGlassAvatar: View {
    let profile: PiruProfile

    var body: some View {
        #if os(macOS)
            Group {
                if let image = profile.avatar.photo.flatMap(ProfilePhotoCache.image(named:)) {
                    // The photo is the glass's content and covers it; the
                    // glass still gives the press response and the rim.
                    ProfilePhotoCircle(image: image, color: profile.color, diameter: Self.diameter)
                        .glassEffect(.regular.interactive(), in: .circle)
                } else {
                    letters
                        .glassEffect(.regular.tint(profile.color.p3.color).interactive(), in: .circle)
                }
            }
            .contentShape(.circle)
            .accessibilityHidden(true)
        #elseif os(Android)
            letters
                .background(profile.color.p3.color, in: Circle())
                .accessibilityHidden(true)
        #else
            Group {
                if let image = profile.avatar.photo.flatMap(ProfilePhotoCache.image(named:)) {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: Self.diameter, height: Self.diameter)
                } else {
                    // An image, which the bar sizes as an icon; any other view
                    // it pads into a wider capsule.
                    ProfileAvatarImage.image(for: profile, diameter: Self.diameter)
                }
            }
            .clipShape(.circle)
            .padding(-Layout.overhang)
            .accessibilityHidden(true)
        #endif
    }

    private enum Layout {
        /// How far the avatar reaches past the bar's 36-point content slot to
        /// fill its 44-point glass circle.
        static let overhang: CGFloat = 4
    }

    private static var diameter: CGFloat {
        #if os(macOS)
            28
        #elseif os(Android)
            34
        #else
            44
        #endif
    }

    private var letters: some View {
        Text(verbatim: profile.avatar.text)
            .font(.system(
                size: Self.diameter * (profile.avatar.kind == .emoji ? 0.5 : 0.4),
                weight: .semibold,
                design: .rounded,
            ))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: Self.diameter, height: Self.diameter)
    }
}
