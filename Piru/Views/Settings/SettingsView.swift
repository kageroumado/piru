import SwiftUI

struct SettingsView: View {
    @Environment(\.appNavigator) private var navigator

    var body: some View {
        List {
            Group {
                PreferencesSection()
                YourBodySection()

                Section {
                    EmptyView()
                } footer: {
                    Text("Meds are in the Journal tab. Custom substances, colors, and units are under Yours in the Library tab. Data & Backup and the substance database are in the Tools tab.")
                }

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

// MARK: - Preferences

/// The pushed preference screens plus the disclosure tier, each row captioned
/// with what it governs. The tier's caption is the live summary of the chosen
/// tier, so the row states what the page currently opens with.
private struct PreferencesSection: View {
    @State private var profileStore = UserProfileStore.shared

    var body: some View {
        Section {
            NavigationLink {
                NotificationSettingsView()
            } label: {
                CaptionedRowLabel(
                    title: "Notifications",
                    systemImage: "bell.badge",
                    caption: Text("Which alerts Piru sends, when it asks again, and when it stays quiet."),
                )
            }

            NavigationLink {
                JournalSettingsView()
            } label: {
                CaptionedRowLabel(
                    title: "Journal",
                    systemImage: "book",
                    caption: Text("Where a day begins and how the timeline stacks its curves."),
                )
            }

            NavigationLink {
                AppearanceSettingsView()
            } label: {
                CaptionedRowLabel(
                    title: "Appearance",
                    systemImage: "paintbrush",
                    caption: Text("Skins, decorations, and light or dark."),
                )
            }

            HStack(spacing: Spacing.md) {
                CaptionedRowLabel(
                    title: "Disclosure Tier",
                    systemImage: "slider.horizontal.3",
                    caption: Text(profileStore.disclosureTier.summary),
                )
                Spacer(minLength: 0)
                Picker("Disclosure Tier", selection: profileBinding) {
                    ForEach(UserProfile.allCases) { profile in
                        Label {
                            Text(profile.displayName)
                        } icon: {
                            Image(systemName: profile.icon)
                                .accessibilityHidden(true)
                        }
                        .tag(profile)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            NavigationLink {
                HealthSettingsView()
            } label: {
                CaptionedRowLabel(
                    title: "Apple Health",
                    systemImage: "heart.text.square",
                    caption: Text("Heart rate and blood pressure on each session's timeline, read from Health."),
                )
            }
        } header: {
            Text("Preferences")
        }
    }

    private var profileBinding: Binding<UserProfile> {
        Binding(
            get: { profileStore.disclosureTier },
            set: { profileStore.setDisclosureTier($0) },
        )
    }
}

// MARK: - Your Body

private struct YourBodySection: View {
    var body: some View {
        Section {
            NavigationLink {
                YourBodyView()
            } label: {
                CaptionedRowLabel(
                    title: "Your Body",
                    systemImage: "figure.stand",
                    caption: Text("Your weight and metabolism, and what each one changes in the estimates."),
                )
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
