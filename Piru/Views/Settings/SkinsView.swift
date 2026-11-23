import SwiftUI

/// The Skins sheet: a short panel over the app, opened from the `•••` menu on
/// every tab, from the Tools tab's Skins card, and once by the app itself.
///
/// Trying a skin on re-dresses the whole app, so the best preview of a skin is
/// the app itself: the panel leaves the screen behind it in view, undimmed and
/// still scrollable, and the person watches their own journal change as the
/// carousel moves. Pulled up to full height, the same list goes on to every
/// skin at once.
struct SkinsSheet: View {
    @State private var detent: PresentationDetent = Self.panel

    /// Tall enough for the carousel, its caption, its dots and its button.
    private static let panel: PresentationDetent = .height(486)

    var body: some View {
        NavigationStack {
            SkinsView(isExpanded: detent == .large) { detent = .large }
        }
        .presentationDetents([Self.panel, .large], selection: $detent)
        .presentationBackgroundInteraction(.enabled(upThrough: Self.panel))
        .onAppear { SkinsPickerRecord.markSeen() }
        // A skin that was only being looked at comes off when the sheet goes.
        .onDisappear { SkinStore.shared.tryOn(nil) }
    }
}

/// Whether this person has had the Skins picker in front of them. The app
/// raises it once for whoever has not (``LaunchSheetModifier``).
enum SkinsPickerRecord {
    private static let key = "skinsPickerSeen"

    static var seen: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: key)
    }
}

/// How the full-height picker lays every skin out.
enum SkinGridLayout: String, CaseIterable, Identifiable {
    /// Pictures only, four across: all of them in one screen.
    case grid
    /// Two across, each with its name and what it costs.
    case large
    /// One row each.
    case list

    static let storageKey = "skinsGridLayout"

    var id: String {
        rawValue
    }

    var title: LocalizedStringResource {
        switch self {
        case .grid: "Grid"
        case .large: "Large"
        case .list: "List"
        }
    }

    var systemImage: String {
        switch self {
        case .grid: "square.grid.3x3"
        case .large: "rectangle.grid.2x2"
        case .list: "list.bullet"
        }
    }

    fileprivate var columns: Int {
        switch self {
        case .grid: 4
        case .large: 2
        case .list: 1
        }
    }
}

/// The picker with the skin in front, then every skin at once, the shop, and
/// the decoration and light/dark settings. The picker fits the panel; the rest
/// scrolls under it.
struct SkinsView: View {
    /// Whether the sheet stands at full height.
    let isExpanded: Bool
    /// Pulls the sheet up to full height.
    let expand: () -> Void

    @State private var skins = SkinStore.shared
    @State private var shop = SkinShop.shared
    @State private var focused: Skin = SkinStore.shared.current
    /// Whether the carousel and its button are on screen. Once they scroll
    /// away, the bar at the foot of the sheet stands in for them.
    @State private var wardrobeVisible = true
    /// Set by the All Skins button, so the list goes to the grid once the
    /// sheet has grown.
    @State private var opensGrid = false
    @AppStorage(SkinGridLayout.storageKey) private var layout: SkinGridLayout = .grid
    @Environment(\.appNavigator) private var navigator

    private enum Anchor {
        static let offer = "offer"
        static let grid = "grid"
    }

    private var showsOffer: Bool {
        shop.ownsEverything || shop.everythingProduct != nil
    }

    /// The row the All Skins button brings to the top: the offer that sits
    /// over the grid, so the grid's header lands under it and in view. A
    /// section header cannot be scrolled to, only a row.
    private var allSkinsTarget: AnyHashable {
        if showsOffer { Anchor.offer } else if layout == .list { Skin.available[0] } else { Anchor.grid }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Group {
                    Section {
                        SkinWardrobe(focused: $focused, use: wear, cardWidth: Self.panelCardWidth)
                            .padding(.bottom, Spacing.md)
                            .onScrollVisibilityChange(threshold: 0.3) { wardrobeVisible = $0 }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    } footer: {
                        Text("Substance colors, the timeline and charts stay the same.")
                    }

                    if showsOffer {
                        Section { SkinEverythingOffer().id(Anchor.offer) }
                    }

                    Section {
                        if layout == .list {
                            ForEach(Skin.available) { skin in
                                SkinListRow(skin: skin, isFocused: skin == focused) { select(skin) }
                            }
                        } else {
                            SkinGrid(columns: layout.columns, showsCaptions: layout == .large, focused: focused, select: select)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .id(Anchor.grid)
                        }
                    } header: {
                        HStack {
                            Text("All Skins")
                            Spacer()
                            Picker("Layout", selection: $layout) {
                                ForEach(SkinGridLayout.allCases) { layout in
                                    Image(systemName: layout.systemImage)
                                        .accessibilityLabel(Text(layout.title))
                                        .tag(layout)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: Self.layoutPickerWidth)
                        }
                    } footer: {
                        Text("Buy once, keep forever. Skins keep Piru independent: no ads, no subscription, and every feature free.")
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

                    Section { SkinRestoreButton() }

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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isExpanded, !wardrobeVisible {
                    SkinActionBar(skin: focused, use: wear)
                }
            }
            .onChange(of: isExpanded) { _, expanded in
                guard expanded, opensGrid else { return }
                opensGrid = false
                withAnimation { proxy.scrollTo(allSkinsTarget, anchor: .top) }
                // The jump takes the carousel out of the list without a
                // visibility change being reported for it.
                wardrobeVisible = false
            }
        }
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
            if !isExpanded {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        opensGrid = true
                        expand()
                    } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                    .accessibilityLabel(Text("All Skins"))
                }
            }
        }
    }

    /// Small enough that the carousel, its caption, its dots and its button
    /// fit the panel.
    private static let panelCardWidth: CGFloat = 124
    private static let layoutPickerWidth: CGFloat = 132

    /// Puts a skin from the grid in front and on the app. The carousel may be
    /// scrolled out of the list by then, so the try-on cannot wait for it.
    private func select(_ skin: Skin) {
        focused = skin
        skins.tryOn(skin)
    }

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

// MARK: - Every skin at once

/// Every skin as a tile, `columns` across.
///
/// Plain stacks rather than a lazy grid: the whole grid is one self-sizing
/// `List` row, where a lazy grid leaves rows undrawn after its column count
/// changes, and eighteen tiles are few enough to build at once.
private struct SkinGrid: View {
    let columns: Int
    let showsCaptions: Bool
    let focused: Skin
    let select: (Skin) -> Void

    @State private var width: CGFloat = 0

    private enum Metrics {
        static let spacing: CGFloat = 10
        static let rowSpacing: CGFloat = 14
    }

    private var rows: [[Skin]] {
        let skins = Skin.available
        return stride(from: 0, to: skins.count, by: columns).map { Array(skins[$0 ..< min($0 + columns, skins.count)]) }
    }

    var body: some View {
        let tile = max(0, (width - Metrics.spacing * CGFloat(columns - 1)) / CGFloat(columns))
        VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
            if tile > 0 {
                ForEach(rows, id: \.first) { row in
                    HStack(alignment: .top, spacing: Metrics.spacing) {
                        ForEach(row) { skin in
                            SkinTile(skin: skin, width: tile, isFocused: skin == focused, showsCaption: showsCaptions) {
                                select(skin)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
    }
}

/// One skin in the grid: its miniature, ringed when it is the one in front,
/// with a mark for the skin being worn or one still to be bought.
private struct SkinTile: View {
    let skin: Skin
    let width: CGFloat
    let isFocused: Bool
    let showsCaption: Bool
    let action: () -> Void

    private enum Metrics {
        static let ring: CGFloat = 3
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.sm) {
                SkinPreviewCard(skin: skin, width: width)
                    .overlay(alignment: .bottomTrailing) {
                        SkinTileMark(skin: skin)
                            .padding(Spacing.sm)
                    }
                    .overlay {
                        if isFocused {
                            RoundedRectangle(cornerRadius: SkinPreviewCard.cornerRadius(width: width), style: .continuous)
                                .strokeBorder(Theme.accent, lineWidth: Metrics.ring)
                        }
                    }
                if showsCaption {
                    VStack(spacing: 0) {
                        Text(skin.displayName)
                            .font(.piru(.subheadline, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        SkinStatus(skin: skin)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isFocused ? .isSelected : [])
    }
}

/// A check on the skin being worn, a lock on one still to be bought.
private struct SkinTileMark: View {
    let skin: Skin
    @State private var skins = SkinStore.shared
    @State private var shop = SkinShop.shared

    var body: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(Spacing.xs)
                .background(.black.opacity(0.55), in: Circle())
                .accessibilityHidden(true)
        }
    }

    private var systemImage: String? {
        if skin == skins.chosen { "checkmark" } else if !shop.owns(skin) { "lock.fill" } else { nil }
    }
}

/// One skin as a row: a small miniature, the name, and what it costs.
private struct SkinListRow: View {
    let skin: Skin
    let isFocused: Bool
    let action: () -> Void

    @State private var skins = SkinStore.shared

    private enum Metrics {
        static let thumbnail: CGFloat = 40
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xl) {
                SkinPreviewCard(skin: skin, width: Metrics.thumbnail)
                Text(skin.displayName)
                    .font(.piru(.body, weight: isFocused ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: Spacing.md)
                if skin == skins.chosen {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryLabel)
                        .accessibilityLabel(Text("Wearing this skin"))
                }
                SkinStatus(skin: skin)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(CardBackground().overlay { if isFocused { Theme.accent.opacity(0.14) } })
        .accessibilityAddTraits(isFocused ? .isSelected : [])
    }
}

/// The skin in front and its button, at the foot of the full-height sheet
/// while the carousel is scrolled away.
private struct SkinActionBar: View {
    let skin: Skin
    let use: (Skin) -> Void

    var body: some View {
        VStack(spacing: Spacing.xs) {
            SkinCaption(skin: skin)
            SkinPrimaryAction(skin: skin, use: use)
                .padding(.horizontal, Spacing.xxxl)
        }
        .padding(.top, Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}
