import SwiftUI

/// A profile's avatar: its monogram or emoji, white on the profile's color.
/// The one place an avatar is drawn — toolbar, menu, Settings, the Journal's
/// subtitle dot.
struct ProfileAvatarView: View {
    let avatar: ProfileAvatar
    let color: ProfileColor
    var diameter: CGFloat = 30

    init(avatar: ProfileAvatar, color: ProfileColor, diameter: CGFloat = 30) {
        self.avatar = avatar
        self.color = color
        self.diameter = diameter
    }

    init(_ profile: PiruProfile, diameter: CGFloat = 30) {
        self.init(avatar: profile.avatar, color: profile.color, diameter: diameter)
    }

    var body: some View {
        Text(verbatim: avatar.text)
            .font(.system(
                size: diameter * (avatar.kind == .emoji ? 0.58 : 0.44),
                weight: .semibold,
                design: .rounded,
            ))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: diameter, height: diameter)
            .background(color.p3.color, in: Circle())
            .accessibilityHidden(true)
    }
}

/// The avatar as a bitmap, for a `Menu` row: menus draw only images and text,
/// so a view in a row's label would be dropped.
@MainActor
enum ProfileAvatarImage {
    private static var cache: [Key: Image] = [:]

    private struct Key: Hashable {
        let avatar: ProfileAvatar
        let color: ProfileColor
        let diameter: CGFloat
    }

    static func image(for profile: PiruProfile, diameter: CGFloat = 24) -> Image {
        let key = Key(avatar: profile.avatar, color: profile.color, diameter: diameter)
        if let cached = cache[key] { return cached }
        let renderer = ImageRenderer(content: ProfileAvatarView(profile, diameter: diameter))
        renderer.scale = 3
        let image = renderer.platformImage.map { Image(platformImage: $0).renderingMode(.original) }
            ?? Image(systemName: "person.crop.circle")
        cache[key] = image
        return image
    }
}
