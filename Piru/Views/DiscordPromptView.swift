import SwiftUI

/// A one-time invite to the community Discord, shown once the user is engaged (see
/// `DiscordInviteModifier`). Closing or joining both retire it — there's no repeat nag.
struct DiscordPromptView: View {
    @AppStorage("discordPromptDismissedForever") private var dismissedForever = false
    @Environment(\.dismiss) private var dismiss

    private static let discordURL = URL(string: "https://discord.gg/hbpMZhPSdx")!
    private static let blurple = Color(hex: "5865F2")

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                .accessibilityLabel("Close")
            }

            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 54))
                .foregroundStyle(Self.blurple)
                .padding(.top, 4)
                .accessibilityHidden(true)

            Text("Join the community")
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)

            Text("Have feedback, questions, or want to discuss the app? Join our Discord — we'd love to hear from you.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            Spacer(minLength: 12)

            Link(destination: Self.discordURL) {
                Label("Join Discord", systemImage: "arrow.up.right")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Self.blurple, in: Capsule())
                    .foregroundStyle(.white)
            }
            .simultaneousGesture(TapGesture().onEnded {
                // Joining is strong intent — don't nag again.
                dismissedForever = true
            })
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
    }
}
