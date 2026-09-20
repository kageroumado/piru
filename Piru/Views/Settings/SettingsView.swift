import SwiftUI

struct SettingsView: View {
    @Environment(\.appNavigator) private var navigator

    var body: some View {
        List {
            Group {
                DetailLevelSection()
                ScreensSection()
                AboutSection()
                AppVersionFooter()
            }
            .listRowBackground(CardBackground())
        }
        .themedPage()
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    navigator.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel(Text("Close"))
            }
        }
    }
}

// MARK: - Detail level

/// The one setting that lives on this page: a title and a picker, with what it
/// governs in the footer.
private struct DetailLevelSection: View {
    @State private var profileStore = UserProfileStore.shared

    var body: some View {
        Section {
            Picker(selection: profileBinding) {
                ForEach(UserProfile.allCases) { profile in
                    Label {
                        Text(profile.displayName)
                    } icon: {
                        Image(systemName: profile.icon)
                            .accessibilityHidden(true)
                    }
                    .tag(profile)
                }
            } label: {
                Label("Detail Level", systemImage: "slider.horizontal.3")
            }
        } footer: {
            Text("How much pharmacology a substance page and the Tolerance tool open with.")
        }
    }

    private var profileBinding: Binding<UserProfile> {
        Binding(
            get: { profileStore.disclosureTier },
            set: { profileStore.setDisclosureTier($0) },
        )
    }
}

// MARK: - Screens

/// The pushed screens. Bare titles: each name says what is behind it.
private struct ScreensSection: View {
    var body: some View {
        Section {
            NavigationLink {
                NotificationSettingsView()
            } label: {
                Label("Notifications", systemImage: "bell.badge")
            }
            NavigationLink {
                JournalSettingsView()
            } label: {
                Label("Journal", systemImage: "book")
            }
            NavigationLink {
                YourBodyView()
            } label: {
                Label("Your Body", systemImage: "figure.stand")
            }
            NavigationLink {
                SourcePriorityView()
            } label: {
                Label("Source Priority", systemImage: "list.number")
            }
        }
    }
}

// MARK: - About

private struct AboutSection: View {
    var body: some View {
        Section {
            NavigationLink {
                AboutView()
            } label: {
                Label("About Piru", systemImage: "info.circle")
            }
        }
    }
}

// MARK: - Version

private struct AppVersionFooter: View {
    var body: some View {
        Section {
            EmptyView()
        } footer: {
            Text(verbatim: appVersionString)
                .frame(maxWidth: .infinity, alignment: .center)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Piru \(version) (\(build))"
    }
}
