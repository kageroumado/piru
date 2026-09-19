import SwiftUI

/// What Piru is and what its numbers are, followed by the way to the Get Help
/// sheet, which stacks over Settings.
struct AboutDisclaimerSection: View {
    @Environment(\.appNavigator) private var navigator

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Text("Piru is a personal record and a general reference, provided as is and without warranty of any kind. It is not medical advice and not a medical device, and it is not for diagnosis, treatment, dosing decisions or emergencies.")
                Text("Reference content is compiled from third-party, community and curated sources and may be incomplete, outdated or wrong. Every curve, level and estimate is an illustrative model, not a measurement.")
                Text("Nothing in Piru encourages or facilitates the use, acquisition or possession of any substance, and you alone are responsible for complying with the laws that apply to you. Piru is for adults 18 and over. Use of Piru is subject to the Terms of Use.")
                Text("Piru does not monitor emergencies. If someone is in danger, call your local emergency number.")
            }
            .fixedSize(horizontal: false, vertical: true)

            Button {
                navigator.present(.help)
            } label: {
                Label("Get Help", systemImage: "lifepreserver")
            }
        }
    }
}
