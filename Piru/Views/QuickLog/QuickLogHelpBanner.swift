import SwiftUI

// MARK: - Help Banner

/// Crisis-support banner surfaced inside the dock when the search query matches
/// a distress keyword — emergency numbers plus a grounding cue. Shown in place
/// of substance results so someone in trouble lands on help, not a dose list.
struct QuickLogHelpBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack(spacing: Spacing.lg) {
                Image(systemName: "hand.raised.fill")
                    .font(.title2)
                    .foregroundStyle(.infoText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Take a breath.")
                        .cardTitle()
                    Text("You're going to be okay. This feeling is temporary.")
                        .captionSecondary()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                helpBannerLink(title: "Emergency: 911", url: "tel:911")
                helpBannerLink(title: "Poison Control: 1-800-222-1222", url: "tel:18002221222")
                helpBannerLink(title: "Crisis Lifeline: 988", url: "tel:988")
                helpBannerLink(title: "Crisis Text: HOME to 741741", url: "sms:741741&body=HOME")
            }

            Text("Breathe slowly. 4 seconds in, hold for 4, out for 4. You are safe.")
                .captionSecondary()
        }
        .padding(14)
        .background(Color.infoAccent.opacity(Theme.Opacity.hairline))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
    }

    @ViewBuilder
    private func helpBannerLink(title: LocalizedStringKey, url: String) -> some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "phone.fill")
                        .font(.caption)
                        .foregroundStyle(.infoText)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}
