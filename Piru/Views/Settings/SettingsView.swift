import SwiftUI

struct SettingsView: View {
    @State private var profileStore = UserProfileStore.shared

    @Environment(\.appNavigator) private var navigator

    var body: some View {
        List {
            Group {
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
                        Label("Disclosure Tier", systemImage: "slider.horizontal.3")
                    }

                    NavigationLink {
                        HealthSettingsView()
                    } label: {
                        Label("Apple Health", systemImage: "heart.text.square")
                    }
                } header: {
                    Text("Preferences")
                }

                Section {
                    Toggle(isOn: grapefruitBinding) {
                        Label("Grapefruit dose logging", systemImage: "carrot")
                    }
                    .tint(Theme.accent)

                    Toggle(isOn: aldh2Binding) {
                        Label("I get the alcohol flush", systemImage: "wineglass")
                    }
                    .tint(Theme.accent)

                    Picker(selection: cyp2d6Binding) {
                        ForEach(CYP2D6Status.allCases, id: \.self) { status in
                            Text(status.label).tag(status)
                        }
                    } label: {
                        Label("CYP2D6 status", systemImage: "DNA")
                    }
                } header: {
                    Text("Metabolism")
                }

                Section {
                    EmptyView()
                } footer: {
                    Text("Meds are in the Journal tab. Custom substances, colors, and units are under Yours in the Library tab. Data & Backup and the substance database are in the Tools tab.")
                }

                Section {
                    EmptyView()
                } footer: {
                    Text(verbatim: appVersionString)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryLabel)
                }
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

    // MARK: - Bindings

    private var profileBinding: Binding<UserProfile> {
        Binding(
            get: { profileStore.disclosureTier },
            set: { profileStore.setDisclosureTier($0) },
        )
    }

    private var grapefruitBinding: Binding<Bool> {
        Binding(
            get: { profileStore.grapefruitLoggingEnabled },
            set: { profileStore.setGrapefruitLoggingEnabled($0) },
        )
    }

    private var aldh2Binding: Binding<Bool> {
        Binding(
            get: { profileStore.aldh2Deficient },
            set: { profileStore.setALDH2Deficient($0) },
        )
    }

    private var cyp2d6Binding: Binding<CYP2D6Status> {
        Binding(
            get: { profileStore.cyp2d6Status },
            set: { profileStore.setCYP2D6Status($0) },
        )
    }

    // MARK: - Version

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Piru \(version) (\(build))"
    }
}

// MARK: - Notifications
