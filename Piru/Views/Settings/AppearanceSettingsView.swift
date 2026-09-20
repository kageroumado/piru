import SwiftUI

/// Skin picker and light/dark override, shown as a panel over the app (see
/// ``SettingsSheet``): the picker fits the panel, and the rest scrolls under it.
struct AppearanceSettingsView: View {
    @State private var skins = SkinStore.shared
    @Environment(\.settingsPanel) private var panel

    var body: some View {
        List {
            Group {
                Section {
                    SkinWardrobe(cardWidth: Self.panelCardWidth)
                        .padding(.bottom, Spacing.md)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } footer: {
                    Text("A skin changes the app's colors, cards, and type. Your substance colors, the timeline, and every chart stay exactly as they are.")
                }

                Section {
                    SkinShopOffers()
                } footer: {
                    Text("Skins pay for Piru's development. The journal, the library, and every tool are free either way.")
                }

                if skins.current.decorations != nil {
                    Section {
                        Toggle(isOn: decorationsBinding) {
                            Label("Decorations", systemImage: "sparkles")
                        }
                        .tint(Theme.accent)
                    } footer: {
                        Text("Stars, hearts, and stickers behind everything. Off automatically with Reduce Motion.")
                    }
                }

                if skins.current == .doseWiki {
                    Section {
                        Link(destination: URL(string: "https://dose.wiki")!) {
                            Label("In partnership with dose.wiki ↗", systemImage: "hexagon")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                }

                Section {
                    Picker(selection: colorSchemeBinding) {
                        ForEach(SkinColorScheme.allCases) { scheme in
                            Text(scheme.displayName).tag(scheme)
                        }
                    } label: {
                        Label("Mode", systemImage: "circle.lefthalf.filled")
                    }
                    .pickerStyle(.menu)
                } footer: {
                    Text("Every skin has a light and a dark side. Follow System switches with iOS.")
                }
            }
            .listRowBackground(CardBackground())
        }
        .scrollContentBackground(.hidden)
        .skinBackdrop()
        .navigationTitle("Appearance")
        // A large title would cost the panel a fifth of its height.
        .inlineNavigationTitle()
        .onAppear { panel.setActive(true) }
        // A skin that was only being looked at comes off on the way out.
        .onDisappear {
            panel.setActive(false)
            skins.tryOn(nil)
        }
    }

    /// Small enough that the carousel, its caption and its button fit the panel.
    private static let panelCardWidth: CGFloat = 124

    private var decorationsBinding: Binding<Bool> {
        Binding(
            get: { skins.decorationsEnabled },
            set: { skins.setDecorationsEnabled($0) },
        )
    }

    private var colorSchemeBinding: Binding<SkinColorScheme> {
        Binding(
            get: { skins.colorScheme },
            set: { skins.setColorScheme($0) },
        )
    }
}
