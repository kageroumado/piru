import SwiftUI

/// Skin picker and light/dark override.
struct AppearanceSettingsView: View {
    @State private var skins = SkinStore.shared

    var body: some View {
        List {
            Group {
                Section {
                    ForEach(Skin.allCases) { skin in
                        SkinRow(skin: skin, isSelected: skin == skins.current) {
                            skins.setSkin(skin)
                        }
                    }
                } header: {
                    Text("Skin")
                } footer: {
                    Text("A skin changes the app's colors, cards, and type. Your substance colors, the timeline, and every chart stay exactly as they are.")
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
        .background(Theme.background)
        .navigationTitle("Appearance")
    }

    private var colorSchemeBinding: Binding<SkinColorScheme> {
        Binding(
            get: { skins.colorScheme },
            set: { skins.setColorScheme($0) },
        )
    }
}

/// One skin in the picker: its light and dark card side by side, name, tagline,
/// and a checkmark when active.
private struct SkinRow: View {
    let skin: Skin
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                swatch
                VStack(alignment: .leading, spacing: 2) {
                    Text(skin.displayName)
                        .foregroundStyle(.primary)
                    Text(skin.tagline)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Left half rendered as the skin's light scheme, right half as dark, so the
    /// row shows both sides regardless of the current mode.
    private var swatch: some View {
        HStack(spacing: 0) {
            half.environment(\.colorScheme, .light)
            half.environment(\.colorScheme, .dark)
        }
        .frame(width: 44, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.secondaryLabel.opacity(0.35), lineWidth: 1))
        .accessibilityHidden(true)
    }

    private var half: some View {
        ZStack {
            skin.background
            Circle()
                .fill(skin.accent)
                .frame(width: 12, height: 12)
        }
    }
}
