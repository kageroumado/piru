import SwiftUI

/// One-time invite to the community Discord, shown on launch until the user
/// either closes it (reappears next launch) or taps "Never show again" (which
/// sets `discordPromptDismissedForever`).
struct DiscordPromptView: View {
    @AppStorage("discordPromptDismissedForever") private var dismissedForever = false
    @Environment(\.dismiss) private var dismiss

    private static let discordURL = URL(string: "https://discord.gg/hbpMZhPSdx")!
    private static let blurple = Color(hex: "5865F2")

    var body: some View {
        VStack(spacing: 18) {
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

            Text("Join the community")
                .font(.title2.weight(.bold))

            Text("Have feedback, questions, or want to discuss the app? Join our Discord — we'd love to hear from you.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            Link(destination: Self.discordURL) {
                Label("Join Discord", systemImage: "arrow.up.right")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Self.blurple, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .simultaneousGesture(TapGesture().onEnded {
                // Joining is strong intent — don't nag again.
                dismissedForever = true
            })

            Button("Never show again") {
                dismissedForever = true
                dismiss()
            }
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryLabel)
            .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
