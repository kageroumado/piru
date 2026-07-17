import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Query(sort: \SubstanceColor.substance) private var substanceColors: [SubstanceColor]
    @Query(sort: \DailyDoseItem.sortOrder) private var dailyDoseItems: [DailyDoseItem]
    @State private var customSubstanceStore = CustomSubstanceStore.shared
    @State private var profileStore = UserProfileStore.shared

    @Environment(\.appNavigator) private var navigator

    var body: some View {
        List {
            Group {
                Section {
                    NavigationLink {
                        RoutinesSettingsView()
                    } label: {
                        // The count is rendered through `Text`'s LocalizedStringKey
                        // path so automatic grammar agreement runs; `String(localized:)`
                        // here left the raw `^[…](inflect: true)` markup on screen.
                        HStack {
                            Label("Routines", systemImage: "repeat")
                            Spacer()
                            Text("^[\(dailyDoseItems.count) item](inflect: true)")
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }

                    NavigationLink {
                        CustomSubstancesListView()
                    } label: {
                        countRow(
                            "My Substances",
                            systemImage: "flask",
                            value: "\(customSubstanceStore.all.count)",
                        )
                    }

                    NavigationLink {
                        SubstanceColorsListView()
                    } label: {
                        HStack {
                            Label("Substance Colors", systemImage: "paintpalette")
                            Spacer()
                            if substanceColors.isEmpty {
                                Text("None yet")
                                    .foregroundStyle(Theme.secondaryLabel)
                            } else {
                                colorsPreview
                            }
                        }
                    }
                } header: {
                    Text("Substances")
                } footer: {
                    Text("Create or personalize substances — adjust dose ranges, duration, and units to match your own data and tolerance.")
                }

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
                } footer: {
                    Text(UserProfileStore.shared.disclosureTier.summary)
                }

                Section {
                    Toggle(isOn: smokesBinding) {
                        Label("I smoke tobacco regularly", systemImage: "smoke")
                    }
                    .tint(Theme.accent)

                    Toggle(isOn: grapefruitBinding) {
                        Label("Grapefruit dose logging", systemImage: "carrot")
                    }
                    .tint(Theme.accent)

                    Toggle(isOn: aldh2Binding) {
                        Label("I get the alcohol flush", systemImage: "wineglass")
                    }
                    .tint(Theme.accent)
                } header: {
                    Text("Metabolism")
                } footer: {
                    Text("Tobacco smoke speeds up CYP1A2, so it lowers the levels of some drugs (like caffeine and olanzapine). Grapefruit slows down CYP3A4, raising the levels of others — turn on grapefruit logging to mark it on individual doses of affected substances. The alcohol flush (facial redness, fast heartbeat, nausea after a little alcohol) signals the ALDH2 variant — turn it on to see acetaldehyde, the toxic by-product it lets build up, on alcohol entries. All three are shown only where they actually change a drug's levels or risk.")
                }

                Section("Data") {
                    NavigationLink {
                        DataStorageView()
                    } label: {
                        Label("Data & Backup", systemImage: "lock.icloud")
                    }

                    NavigationLink {
                        SubstanceDatabaseView()
                    } label: {
                        countRow(
                            "Substance Database",
                            systemImage: "books.vertical",
                            value: "\(SubstanceStore.shared.count)",
                        )
                    }
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
        .scrollContentBackground(.hidden)
        .background(Theme.background)
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

    // MARK: - Row Helpers

    private func countRow(_ title: LocalizedStringKey, systemImage: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    // MARK: - Bindings

    private var profileBinding: Binding<UserProfile> {
        Binding(
            get: { profileStore.disclosureTier },
            set: { profileStore.setDisclosureTier($0) },
        )
    }

    private var smokesBinding: Binding<Bool> {
        Binding(
            get: { profileStore.smokesTobacco },
            set: { profileStore.setSmokesTobacco($0) },
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

    // MARK: - Version

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Piru \(version) (\(build))"
    }

    // MARK: - Colors Preview

    private var colorsPreview: some View {
        HStack(spacing: -4) {
            ForEach(substanceColors.prefix(5)) { sc in
                Circle()
                    .fill(sc.color)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(.background, lineWidth: 1.5))
            }
            if substanceColors.count > 5 {
                Text("+\(substanceColors.count - 5)")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
                    .padding(.leading, 6)
            }
        }
    }
}

// MARK: - Notifications
