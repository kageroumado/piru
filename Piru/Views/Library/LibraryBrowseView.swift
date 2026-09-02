import SwiftData
import SwiftUI

/// The Library tab's browse surface: a flow of bold effect-family cards in
/// place of the old flat category list. Single cards push straight to a
/// substance list; umbrella cards expand in place into their sub-classes.
struct LibraryBrowseView: View {
    @Query(sort: \FavoriteSubstance.createdAt, order: .reverse) private var favorites: [FavoriteSubstance]
    @State private var expanded: Set<String> = []

    /// Resolved once the batch cache is warm, not per `body`. `visibleFamilies`
    /// calls `SubstanceLibrary.substances(in:)` for ~12 families and
    /// `favoriteSubstances` does a lookup per favorite — both are batch-cache
    /// dict hits once warm, but recomputing them on every body pass (and risking
    /// a cold full resolve on the main thread the first time) is wasted work.
    @State private var visibleFamilies: [LibraryFamily] = []
    @State private var favoriteSubstances: [Substance] = []
    /// Gates the card flow on the batch cache being warm, so the screen never
    /// flashes a half-built list (or pays a cold resolve in `body`). The browse
    /// data resolves off-main on its own connection, so this placeholder is
    /// brief — and it never blocks the rest of the UI.
    @State private var loaded = false

    var body: some View {
        ScrollView {
            if loaded {
                LazyVStack(spacing: Spacing.xl) {
                    LibraryYoursCard(
                        favorites: favoriteSubstances,
                        isExpanded: expanded.contains("yours"),
                        toggle: { toggle("yours") },
                    )
                    ForEach(visibleFamilies) { family in
                        LibraryFamilyCard(
                            family: family,
                            isExpanded: expanded.contains(family.id),
                            toggle: { toggle(family.id) },
                        )
                    }
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.xs)
                .padding(.bottom, 28)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
            }
        }
        .themedPage()
        .task {
            // Resolve against the warmed batch cache so the ~12 category counts
            // and favorite lookups are dict hits, not a cold main-thread resolve.
            await SubstanceStore.shared.ensureAllLoaded()
            // Families with empty sub-classes / single cards pruned, so a category
            // with nothing browsable never shows a dead card.
            visibleFamilies = LibraryFamily.browsable
            // Warm each card's exemplar line here (in the task) rather than on
            // first render: resolving it materializes the source's whole
            // substance list, so doing it per card inside `body` would repeat
            // that for every card on every render. After this the cards just
            // read the memo.
            for family in visibleFamilies {
                _ = LibraryFamily.exemplars(for: family.source)
            }
            rebuildFavorites()
            loaded = true
        }
        .onChange(of: favoritesSignature) { rebuildFavorites() }
    }

    /// Favorite identities, not just `count`, so a same-count swap still rebuilds
    /// the resolved favorite cards.
    private var favoritesSignature: Int {
        var hasher = Hasher()
        for favorite in favorites {
            hasher.combine(favorite.substance)
        }
        return hasher.finalize()
    }

    private func rebuildFavorites() {
        // Exact canonical lookup only. Alias fallback was tempting (so a favorite
        // under a since-merged name like "Magnesium" still resolves), but some
        // aliases are polluted in the data — "magnesium" is also an alias of
        // Salicylic acid — so it mis-resolves. Paired with `total =
        // favoriteSubstances.count` this keeps the card's count honest instead.
        favoriteSubstances = favorites.compactMap { SubstanceLibrary.resolveFull($0.substance) }
    }

    private func toggle(_ id: String) {
        withAnimation(.snappy(duration: 0.3)) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }
}

// MARK: - Gradient Surface

/// The Library's signature card surface: a category-tinted diagonal gradient
/// with a faint hero graphic (molecule or glyph) bleeding off the top-trailing
/// edge, rounded and shadowed. Shared by the family cards, the favorites card,
/// and the Search screen's class mini-cards so the recipe lives in one place.
struct FamilyGradientCard<Hero: View, Content: View>: View {
    let color: Color
    var cornerRadius: CGFloat = 22
    var padding: CGFloat = 16
    @ViewBuilder var hero: () -> Hero
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            // White text on a light gradient. The colours are deliberately vivid
            // and ungated (see `design-system/color/build_l2_scales.py`), so
            // legibility comes from lifting the text off the fill rather than
            // from darkening the fill — which for orange and green means brown.
            // Same treatment the count and chevron already used, a touch
            // stronger since this carries the title and blurb.
            .shadow(color: .black.opacity(0.32), radius: 3, x: 0, y: 1)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topTrailing) { hero() }
            .background(
                LinearGradient(
                    colors: [color, color.mix(with: .white, by: 0.35)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing,
                ),
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: color.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Family Card

/// One family card. Single families are a single navigation link; umbrella
/// families grow in place — their chips slide down and enlarge into described,
/// tappable sub-rows within the same gradient surface.
private struct LibraryFamilyCard: View {
    let family: LibraryFamily
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        if family.isUmbrella {
            umbrella
        } else if let source = family.source {
            NavigationLink(value: source.route) {
                surface {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        header(chevron: "chevron.right", count: groupCount)
                        if family.highlightsRisk {
                            riskBadge.padding(.top, 5)
                        } else {
                            exemplarsLine.padding(.top, 5)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var umbrella: some View {
        surface {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Button(action: toggle) {
                    header(chevron: "chevron.down", rotates: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))

                if isExpanded {
                    VStack(spacing: Spacing.md) {
                        ForEach(family.subclasses) { sub in
                            NavigationLink(value: sub.route) {
                                LibrarySubclassRow(sub: sub)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    // Scale+fade grows the rows in place as a transform — the laid-out
                    // views never re-flow mid-flight (which is what made the matched-
                    // geometry morph flash a one-line description at the boundary).
                    .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
                } else {
                    FlowLayout(spacing: Spacing.sm) {
                        ForEach(family.subclasses) { sub in
                            chip(sub)
                        }
                    }
                    .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: Pieces

    /// `chevron` is the trailing affordance: `chevron.right` on cards that push a
    /// screen (Apple's "navigates" cue), `chevron.down` (with `rotates`) on the
    /// expand-in-place umbrellas. The umbrella's pushing sub-rows keep their own
    /// right chevron.
    private func header(chevron: String?, rotates: Bool = false, count: Int? = nil) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Image(systemName: family.icon)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(height: 28, alignment: .leading)
                    .accessibilityHidden(true)
                Text(family.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Text(family.blurb)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.93))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 210, alignment: .leading)
            }
            Spacer(minLength: 8)
            HStack(spacing: Spacing.sm) {
                // Group size, like the inner sub-rows show. Only on navigating
                // cards — umbrellas expand to reveal their sub-rows' own counts.
                if let count {
                    Text("\(count)")
                        .sectionLabel()
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.9))
                }
                if let chevron {
                    Image(systemName: chevron)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .rotationEffect(.degrees(rotates && isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
            }
            .padding(.top, Spacing.xs)
            // Lift the count/chevron off the molecule skeleton behind them.
            .shadow(color: .black.opacity(0.22), radius: 2.5, x: 0, y: 1)
        }
    }

    /// Substance count for a single navigating card (nil for umbrellas). Reads
    /// the cheap histogram for categories so a card's count never forces the
    /// full per-category `Substance` materialization.
    private var groupCount: Int? {
        switch family.source {
        case let .category(category): SubstanceLibrary.categorySummary()[category] ?? 0
        case let .tag(tag): SubstanceLibrary.tagSummary()[tag] ?? 0
        case nil: nil
        }
    }

    private var exemplarsLine: some View {
        Text(LibraryFamily.exemplars(for: family.source).joined(separator: " · "))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
            .lineLimit(1)
            .frame(maxWidth: 220, alignment: .leading)
    }

    private var riskBadge: some View {
        Label("Highest overdose risk", systemImage: "exclamationmark.triangle.fill")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.black.opacity(0.22), in: Capsule())
    }

    private func chip(_ sub: LibrarySubclass) -> some View {
        Text(sub.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 5)
            .background(.white.opacity(0.22), in: Capsule())
    }

    // MARK: Surface

    private func surface(@ViewBuilder _ content: @escaping () -> some View) -> some View {
        FamilyGradientCard(color: family.color) {
            // Anchored to the header (top-trailing in both states with one fixed
            // offset) so expanding doesn't slide it down — only the card grows
            // beneath it. Faint, lightly blurred when expanded so the rows read.
            MoleculeView(key: family.molecule)
                .frame(width: 178, height: 178)
                .opacity(isExpanded ? 0.22 : 0.5)
                .blur(radius: isExpanded ? 3 : 0)
                .offset(x: 20, y: -16)
        } content: {
            content()
        }
    }
}

// MARK: - Sub-class Row

/// An expanded umbrella's sub-class: icon, name, one-line description, the
/// substance count, and a trailing chevron so it reads as tappable.
private struct LibrarySubclassRow: View {
    let sub: LibrarySubclass

    private var count: Int {
        SubstanceLibrary.categorySummary()[sub.category] ?? 0
    }

    var body: some View {
        HStack(spacing: Spacing.xl) {
            Image(systemName: sub.category.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.24), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(sub.title)
                    .sectionLabel()
                    .foregroundStyle(.white)
                Text(sub.blurb)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Text("\(count)")
                .sectionLabel()
                .foregroundStyle(.white.opacity(0.92))
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(Theme.Opacity.strong))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.17), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(.white.opacity(Theme.Opacity.tintActive), lineWidth: 0.5),
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Yours Card (favorites · colors · custom substances · custom units)

/// The user's own layer over the library as one umbrella card in the family
/// style: a gradient surface with a star hero that expands in place into four
/// sub-rows — favorites, substance colors, custom substances, custom units — each pushing its
/// own list. Always present, counts included, so each row has somewhere to go
/// before it has anything to count.
private struct LibraryYoursCard: View {
    let favorites: [Substance]
    let isExpanded: Bool
    let toggle: () -> Void

    @Query(sort: \SubstanceColor.substance) private var substanceColors: [SubstanceColor]

    /// Raspberry — distinct from the warm Stimulants orange and the cool Common blue.
    private static let accent = Color(red: 0.85, green: 0.26, blue: 0.47)

    private var customCount: Int {
        CustomSubstanceStore.shared.all.count
    }

    private var rows: [LibraryYoursSubRow.Model] {
        [
            .init(
                id: "favorites",
                icon: "star.fill",
                title: "Favorites",
                blurb: favorites.isEmpty
                    ? Text("Star a substance to keep it here")
                    : Text(verbatim: favorites.prefix(3).map(\.displayTitle).joined(separator: " · ")),
                count: favorites.count,
                route: .libraryFavorites,
            ),
            .init(
                id: "colors",
                icon: "paintpalette.fill",
                title: "Colors",
                blurb: Text("A color for every substance you log"),
                count: substanceColors.count,
                route: .libraryColors,
            ),
            .init(
                id: "custom",
                icon: "sparkles",
                title: "Custom Substances",
                blurb: Text("Substances you added or customized"),
                count: customCount,
                route: .libraryCustom,
            ),
            .init(
                id: "units",
                icon: "ruler.fill",
                title: "Custom Units",
                blurb: Text("Units you defined for your doses"),
                count: CustomUnitStore.shared.all.count,
                route: .libraryUnits,
            ),
        ]
    }

    var body: some View {
        FamilyGradientCard(color: Self.accent) {
            Image(systemName: "star.fill")
                .font(.system(size: 152))
                .foregroundStyle(.white.opacity(isExpanded ? 0.08 : 0.16))
                .rotationEffect(.degrees(8))
                .offset(x: 30, y: -18)
                .accessibilityHidden(true)
        } content: {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Button(action: toggle) {
                    header.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))

                if isExpanded {
                    VStack(spacing: Spacing.md) {
                        ForEach(rows) { row in
                            NavigationLink(value: row.route) {
                                LibraryYoursSubRow(model: row)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
                } else {
                    FlowLayout(spacing: Spacing.sm) {
                        ForEach(rows) { row in
                            chip(row)
                        }
                    }
                    .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(height: 28, alignment: .leading)
                    .accessibilityHidden(true)
                Text("Yours")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Text("Favorites, colors, units, and the substances you added.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.93))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 210, alignment: .leading)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.down")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.9))
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .accessibilityHidden(true)
                .padding(.top, Spacing.xs)
                .shadow(color: .black.opacity(0.22), radius: 2.5, x: 0, y: 1)
        }
    }

    private func chip(_ row: LibraryYoursSubRow.Model) -> some View {
        HStack(spacing: 5) {
            Text(row.title)
            Text("\(row.count)")
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.75))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 5)
        .background(.white.opacity(0.22), in: Capsule())
    }
}

/// One expanded row of the Yours card, in the family sub-row recipe: an icon
/// tile, title and blurb, the count, and the push chevron.
private struct LibraryYoursSubRow: View {
    struct Model: Identifiable {
        let id: String
        let icon: String
        let title: LocalizedStringKey
        let blurb: Text
        let count: Int
        let route: PushRoute
    }

    let model: Model

    var body: some View {
        HStack(spacing: Spacing.xl) {
            Image(systemName: model.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.24), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(model.title)
                    .sectionLabel()
                    .foregroundStyle(.white)
                model.blurb
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Text("\(model.count)")
                .sectionLabel()
                .foregroundStyle(.white.opacity(0.92))
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(Theme.Opacity.strong))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.17), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(.white.opacity(Theme.Opacity.tintActive), lineWidth: 0.5),
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
