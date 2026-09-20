import SwiftUI

/// Skin picker and light/dark override.
struct AppearanceSettingsView: View {
    @State private var skins = SkinStore.shared

    var body: some View {
        List {
            Group {
                Section {
                    SkinWardrobe()
                        .padding(.vertical, Spacing.xl)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Skin")
                } footer: {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("A skin changes the app's colors, cards, and type. Your substance colors, the timeline, and every chart stay exactly as they are.")
                        Text("Skins pay for Piru's development. The journal, the library, and every tool are free either way.")
                    }
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
        // A skin that was only being looked at comes off on the way out.
        .onDisappear { skins.tryOn(nil) }
    }

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
