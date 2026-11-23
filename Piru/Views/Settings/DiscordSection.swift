import SwiftUI

/// The community Discord server: the one invite link every screen that offers
/// it opens, and the brand color it is shown in.
enum DiscordInvite {
    static let url = URL(string: "https://discord.gg/hbpMZhPSdx")!
    static let blurple = Color(hex: "5865F2")
}

/// Settings' standing way to the Discord server, for help and suggestions. The
/// launch invite (``DiscordPromptView``) shows once; this row stays.
struct DiscordSection: View {
    var body: some View {
        Section {
            Link(destination: DiscordInvite.url) {
                HStack(spacing: Spacing.md) {
                    Label {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Discord")
                                .foregroundStyle(Color.primary)
                            Text("Help and suggestions")
                                .captionSecondary()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundStyle(DiscordInvite.blurple)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryLabel)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}
