import SwiftUI

/// What Piru is for, where its data comes from, how reference text is written,
/// and where a person's own data lives. The disclaimer leads, as body text.
struct AboutView: View {
    var body: some View {
        List {
            Group {
                AboutDisclaimerSection()
                AboutSourcesSection(sources: AppSources.all)
                AboutOpenSourceSection()
                AboutLicensesSection()
                AboutAIContentSection()
                AboutPrivacySection()
            }
            .listRowBackground(CardBackground())
        }
        .themedPage()
        .navigationTitle("About Piru")
        .inlineNavigationTitle()
    }
}

// MARK: - AI-assisted content

private struct AboutAIContentSection: View {
    var body: some View {
        Section {
            Text("Some reference text was drafted with AI assistance and reviewed before publication. AI output is not treated as evidence. Quantitative and safety-critical claims are checked against identified sources, which are listed on each substance page.")
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("AI-Assisted Content")
        }
    }
}

#Preview {
    NavigationStack { AboutView() }
}
