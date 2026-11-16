import SwiftUI

/// A profile's avatar: its photo ringed in the profile's color, or its
/// monogram or emoji, white on that color. The one place an avatar is drawn —
/// menu rows, the For chip, Settings, the shared-night marks.
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
        #if os(Android)
            letters
        #else
            if let image = avatar.photo.flatMap(ProfilePhotoCache.image(named:)) {
                ProfilePhotoCircle(image: image, color: color, diameter: diameter)
            } else {
                letters
            }
        #endif
    }

    private var letters: some View {
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

#if !os(Android)
    /// A photo filling a circle, with a thin ring in the profile's color so
    /// two similar photos still read as different people.
    struct ProfilePhotoCircle: View {
        let image: PlatformImage
        let color: ProfileColor
        let diameter: CGFloat

        var body: some View {
            Image(platformImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: diameter, height: diameter)
                .clipShape(.circle)
                .overlay {
                    Circle().strokeBorder(color.p3.color, lineWidth: min(max(diameter * 0.05, 1.5), 2.5))
                }
                .accessibilityHidden(true)
        }
    }

    /// Decoded profile photos by file name. A name is never reused for other
    /// pixels, so an entry never goes stale.
    @MainActor
    enum ProfilePhotoCache {
        private static var images: [String: PlatformImage] = [:]

        static func image(named name: String) -> PlatformImage? {
            if let cached = images[name] { return cached }
            guard let data = ProfilePhotoStore.data(named: name), let image = PlatformImage(data: data) else { return nil }
            images[name] = image
            return image
        }
    }
#endif

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
