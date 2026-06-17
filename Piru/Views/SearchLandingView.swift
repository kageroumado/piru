import SwiftData
import SwiftUI

/// The Search tab's at-rest browse screen (Apple-Music-style): recent searches,
/// recently-taken substances, a Help shortcut, and a grid of class cards. Shown
/// when the search field isn't focused; tapping the field swaps in the focused
/// activity list and raises the keyboard.
///
/// Laid out like the Library tab's browse flow — a `ScrollView` + `LazyVStack`
/// at a flush 16pt gutter — so its cards line up with the Library cards rather
/// than picking up an inset-grouped `List`'s extra section margins.
struct SearchLandingView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                RecentlySearchedGroup()
                RecentDosesGroup(limit: 3)
                HelpCard()
                ClassBrowseGroup()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }
}

/// The focused-empty state: the recent activity (searches + doses) shown above
/// the keyboard once the field has focus but nothing's typed yet — no browse
/// cards (they'd read oddly under the keyboard).
struct SearchActivityList: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                RecentlySearchedGroup()
                RecentDosesGroup(limit: 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }
}

// MARK: - Recent groups

/// Substances the user has tapped from past searches, most-recent first, with a
/// Clear button — the search-history counterpart to the dose-log "Recent". Stale
/// names that no longer resolve are dropped.
private struct RecentlySearchedGroup: View {
    @State private var history = SearchHistoryStore.shared

    private var substances: [Substance] {
        history.recent.compactMap { SubstanceLibrary.lookup($0) }
    }

    var body: some View {
        if !substances.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel("Recently Searched")
                    Spacer()
                    Button("Clear") { history.clear() }
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 4)
                SubstanceRowsCard(substances: substances)
            }
        }
    }
}

/// The most recently-taken substances from the dose log, capped to `limit`.
private struct RecentDosesGroup: View {
    var limit: Int

    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var recentEntries: [DoseEntry]

    private var substances: [Substance] {
        var seen = Set<String>()
        var result: [Substance] = []
        for entry in recentEntries {
            let key = entry.substance.lowercased()
            if seen.insert(key).inserted, let substance = SubstanceLibrary.lookup(key) {
                result.append(substance)
                if result.count >= limit { break }
            }
        }
        return result
    }

    var body: some View {
        if !substances.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Recent").padding(.horizontal, 4)
                SubstanceRowsCard(substances: substances)
            }
        }
    }
}

/// A grouped rounded card of substance rows with hairline dividers — the
/// grouped-list look at the library's 16pt gutter (an inset-grouped `List`
/// section would over-inset it). Each row pushes the substance detail.
private struct SubstanceRowsCard: View {
    let substances: [Substance]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(substances.enumerated()), id: \.element.id) { index, substance in
                if index > 0 {
                    Divider().padding(.leading, 16)
                }
                NavigationLink(value: PushRoute.substance(name: substance.name)) {
                    HStack(spacing: 8) {
                        SubstanceRowView(substance: substance)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SectionLabel: View {
    let title: LocalizedStringKey
    init(_ title: LocalizedStringKey) {
        self.title = title
    }
    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.secondaryLabel)
    }
}

// MARK: - Help card

/// Full-width gradient card opening the Help sheet — same surface recipe as the
/// Library class cards.
private struct HelpCard: View {
    @Environment(\.appNavigator) private var navigator

    /// A calm teal-blue, distinct from the Common card's cornflower and the
    /// Mind family's deep teal that share the grid below.
    private static let color = Color(red: 0.18, green: 0.48, blue: 0.60)

    var body: some View {
        Button { navigator.present(.help) } label: {
            FamilyGradientCard(color: Self.color) {
                Image(systemName: "lifepreserver")
                    .font(.system(size: 124, weight: .regular))
                    .foregroundStyle(.white.opacity(0.16))
                    .offset(x: 26, y: -4)
            } content: {
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: "lifepreserver")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(height: 28, alignment: .leading)
                    Text("Help & Safety")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Crisis resources, harm-reduction basics, and how Piru works.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.93))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 240, alignment: .leading)
                        .padding(.top, 5)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Browse by class

/// Two-per-row mini class cards reusing the Library family palette. Umbrella
/// families expand *in place*: the umbrella card is replaced by a fold-back
/// chevron card (where it was) followed by its sub-class cards — mirroring the
/// Library tab's expand-in-place umbrellas, but in a grid.
private struct ClassBrowseGroup: View {
    @Environment(\.appNavigator) private var navigator
    @State private var expandedID: String?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Browse by class").padding(.horizontal, 4)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(LibraryFamily.browsable) { family in
                    if family.id == expandedID {
                        // Fold-back card sits where the umbrella was, then its
                        // sub-classes follow.
                        ClassMiniCard(color: family.color) {
                            collapse()
                        } content: {
                            FoldBackLabel()
                        }
                        ForEach(family.subclasses) { sub in
                            ClassMiniCard(color: sub.category.color) {
                                navigator.push(.libraryCategory(sub.category))
                            } content: {
                                ClassLabel(icon: sub.category.icon, title: sub.title)
                            }
                        }
                    } else {
                        ClassMiniCard(color: family.color, molecule: family.molecule) {
                            tap(family)
                        } content: {
                            ClassLabel(icon: family.icon, title: family.title)
                        }
                    }
                }
            }
        }
    }

    private func tap(_ family: LibraryFamily) {
        if family.isUmbrella {
            withAnimation(.snappy(duration: 0.28)) { expandedID = family.id }
        } else if let route = family.source?.route {
            navigator.push(route)
        }
    }

    private func collapse() {
        withAnimation(.snappy(duration: 0.28)) { expandedID = nil }
    }
}

/// One half-width gradient class card. Single families and sub-classes navigate;
/// umbrella families and the fold-back card toggle expansion.
private struct ClassMiniCard<Content: View>: View {
    let color: Color
    var molecule: String?
    let action: () -> Void
    @ViewBuilder var content: () -> Content

    init(
        color: Color,
        molecule: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content,
    ) {
        self.color = color
        self.molecule = molecule
        self.action = action
        self.content = content
    }

    var body: some View {
        Button(action: action) {
            FamilyGradientCard(color: color, cornerRadius: 18, padding: 14) {
                if let molecule {
                    MoleculeView(key: molecule)
                        .frame(width: 116, height: 116)
                        .opacity(0.5)
                        .offset(x: 14, y: -10)
                }
            } content: {
                content()
            }
        }
        .buttonStyle(.plain)
    }
}

/// Icon-over-title content for a class / sub-class card.
private struct ClassLabel: View {
    let icon: String
    let title: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(height: 26, alignment: .leading)
            Spacer(minLength: 14)
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
    }
}

/// The fold-back card: a large chevron that collapses an expanded umbrella.
private struct FoldBackLabel: View {
    var body: some View {
        VStack {
            Spacer(minLength: 0)
            Image(systemName: "chevron.up")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 78)
    }
}
