import SwiftUI

/// The Skins sheet: a short panel over the app, opened from the `•••` menu on
/// every tab.
///
/// Trying a skin on re-dresses the whole app, so the best preview of a skin is
/// the app itself: the panel leaves the screen behind it in view, undimmed and
/// still scrollable, and the person watches their own journal change as the
/// carousel moves. The detents are fixed and the sheet opens at the panel —
/// nothing here resizes it, so nothing can knock it to full height.
struct SkinsSheet: View {
    @State private var detent: PresentationDetent = Self.panel

    /// Tall enough for the carousel, its caption and its button; everything
    /// under them scrolls, or the panel can be pulled up to full height.
    private static let panel: PresentationDetent = .height(452)

    var body: some View {
        NavigationStack { SkinsView() }
            .presentationDetents([Self.panel, .large], selection: $detent)
            .presentationBackgroundInteraction(.enabled(upThrough: Self.panel))
            // A skin that was only being looked at comes off when the sheet goes.
            .onDisappear { SkinStore.shared.tryOn(nil) }
    }
}

/// Skin picker, decorations, and the light/dark override. The picker fits the
/// panel; the rest scrolls under it.
struct SkinsView: View {
    @State private var skins = SkinStore.shared
    @Environment(\.appNavigator) private var navigator

    var body: some View {
        List {
            Group {
                Section {
                    SkinWardrobe(use: wear, cardWidth: Self.panelCardWidth)
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

                // Always in the list, switched off for a skin with nothing to
                // decorate. Rows that come and go with the skin in front resize
                // the list under the carousel while it is being swiped.
                Section {
                    Toggle(isOn: decorationsBinding) {
                        Label("Decorations", systemImage: "sparkles")
                    }
                    .tint(Theme.accent)
                    .disabled(skins.current.decorations == nil)
                } footer: {
                    Text("Stars, hearts, and stickers behind everything. Off automatically with Reduce Motion.")
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

                // Last, so that it arriving with a partner's skin moves nothing
                // above it.
                if let partner {
                    Section {
                        Link(destination: partner.url) {
                            Label { Text(partner.title) } icon: { Image(systemName: "hexagon") }
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                }
            }
            .listRowBackground(CardBackground())
        }
        .scrollContentBackground(.hidden)
        .skinBackdrop()
        .navigationTitle("Skins")
        // A large title would cost the panel a fifth of its height.
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    navigator.dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(Text("Close"))
            }
        }
    }

    /// Small enough that the carousel, its caption and its button fit the panel.
    private static let panelCardWidth: CGFloat = 124

    /// Closes the sheet, then wears the skin. Choosing a skin re-creates the
    /// app's root so navigation bars pick up the new title face, and a sheet
    /// still open across that comes back at full height — so it goes first.
    private func wear(_ skin: Skin) {
        navigator.dismiss()
        skins.setSkin(skin)
    }

    /// The encyclopedia a partnership skin is drawn from, and where it lives.
    private var partner: (title: LocalizedStringResource, url: URL)? {
        switch skins.current {
        case .doseWiki: ("In partnership with dose.wiki ↗", URL(string: "https://dose.wiki")!)
        case .substanceWiki: ("In partnership with substance.wiki ↗", URL(string: "https://substance.wiki")!)
        default: nil
        }
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
