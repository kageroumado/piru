import SwiftUI

struct SettingsView: View {
    @Environment(\.appNavigator) private var navigator

    var body: some View {
        List {
            Group {
                LanguageSection()
                DetailLevelSection()
                if LocalizedSubstanceName.isAvailable {
                    SubstanceNamesSection()
                }
                ScreensSection()
                DiscordSection()
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

// MARK: - Language

/// The app's language, switched in place. Each language is named in itself so it
/// can be found from any other; System follows iOS.
private struct LanguageSection: View {
    @State private var language = AppLanguageModel.shared

    var body: some View {
        Section {
            Picker(selection: choiceBinding) {
                ForEach(AppLanguage.allCases) { choice in
                    if let name = choice.nativeName {
                        Text(verbatim: name).tag(choice)
                    } else {
                        Text("System").tag(choice)
                    }
                }
            } label: {
                Label("Language", systemImage: "globe")
            }
        } footer: {
            Text("System uses your device’s language. Widgets switch at their next refresh.")
        }
    }

    private var choiceBinding: Binding<AppLanguage> {
        Binding(
            get: { language.choice },
            set: { language.select($0) },
        )
    }
}

// MARK: - Detail level

/// A title and a picker, with what it governs in the footer.
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
            Text("How much pharmacology is shown by default on substance pages and in the Tolerance tool.")
        }
    }

    private var profileBinding: Binding<UserProfile> {
        Binding(
            get: { profileStore.disclosureTier },
            set: { profileStore.setDisclosureTier($0) },
        )
    }
}

// MARK: - Substance names

/// Shown only when the app runs in a language with localized substance names.
private struct SubstanceNamesSection: View {
    @AppStorage(LocalizedSubstanceName.englishNamesKey) private var englishNames = false

    var body: some View {
        Section {
            Toggle(isOn: $englishNames) {
                Label("English Substance Names", systemImage: "character.book.closed")
            }
        } footer: {
            Text("Show substances by their English names instead of the names used in your language. Search finds both.")
        }
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
                TabsSettingsView()
            } label: {
                Label("Tabs", systemImage: "dock.rectangle")
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
