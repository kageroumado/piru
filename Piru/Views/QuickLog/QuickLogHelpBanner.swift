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
                    .font(.piru(.title2))
                    .foregroundStyle(.infoText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Take a breath.")
                        .cardTitle()
                    Text("You don't have to do this alone. Help is one tap away.")
                        .captionSecondary()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(HelpView.services(for: HelpView.regionCode)) { service in
                    helpBannerLink(service)
                }
            }

            Text("Breathe slowly. 4 seconds in, hold for 4, out for 4.")
                .captionSecondary()
        }
        .padding(14)
        .background(Color.infoAccent.opacity(Theme.Opacity.hairline))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
    }

    @ViewBuilder
    private func helpBannerLink(_ service: HelpView.EmergencyService) -> some View {
        if let destination = URL(string: service.url) {
            Link(destination: destination) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: service.systemImage)
                        .font(.caption)
                        .foregroundStyle(.infoText)
                        .accessibilityHidden(true)
                    Text(verbatim: "\(String(localized: service.title)): \(service.detail)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}
