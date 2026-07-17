import SwiftUI

// MARK: - Pre-typing suggestions

/// The pre-typing search surface: effect-family pills over one-tap suggestion
/// rows (a selected family's most known substances, or the user's recents).
///
/// The browse selection (`selectedFamilyID`, `browseResults`) is owned by
/// ``QuickLogDock`` — its handlers reset it when search exits — so it arrives
/// as bindings the pills edit in place.
struct DockSuggestions: View {
    let families: [LibraryFamily]
    @Binding var selectedFamilyID: String?
    @Binding var browseResults: [Substance]
    var content: QuickLogContentModel
    let onStage: (QuickLogStagePayload) -> Void
    let onStageDraft: (QuickLogStagePayload) -> Void

    var body: some View {
        if !families.isEmpty {
            familyPills
        }
        if let family = families.first(where: { $0.id == selectedFamilyID }) {
            DockGroupedCard {
                QuickLogSearchResults(
                    // Browsing a family names no product — there's no query to
                    // have matched an alias with, so these rows title canonically.
                    results: browseResults.map { .library(SubstanceMatch(substance: $0, matchedAlias: nil)) },
                    onAdd: onStage,
                    onAddDraft: onStageDraft,
                    onCreateCustom: nil,
                )
            }
            .id(family.id)
        } else if !content.cachedCards.isEmpty {
            DockGroupedCard {
                QuickLogSearchResults(
                    results: content.cachedCards.prefix(6).map { .recent($0) },
                    onAdd: onStage,
                    onAddDraft: onStageDraft,
                    onCreateCustom: nil,
                )
            }
        }
    }

    /// Horizontally scrolling effect-family filter pills (Library taxonomy).
    private var familyPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(families) { family in
                    DockFamilyPill(family: family, isSelected: selectedFamilyID == family.id) {
                        withAnimation(.snappy) {
                            if selectedFamilyID == family.id {
                                selectedFamilyID = nil
                                browseResults = []
                            } else {
                                selectedFamilyID = family.id
                                browseResults = Self.substances(for: family)
                            }
                        }
                    }
                }
            }
            // Bleed to the sheet edges so the row scrolls edge-to-edge while
            // resting pills align with the cards.
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
    }

    /// The most recognizable substances of one family, by curated popularity —
    /// umbrellas union their sub-classes.
    static func substances(for family: LibraryFamily) -> [Substance] {
        let list: [Substance] = switch family.source {
        case let .category(category): SubstanceLibrary.substances(in: category)
        case let .tag(tag): SubstanceLibrary.substances(taggedWith: tag)
        case nil: family.subclasses.flatMap { SubstanceLibrary.substances(in: $0.category) }
        }
        return Array(
            list
                .sorted {
                    $0.popularity != $1.popularity
                        ? $0.popularity > $1.popularity
                        : $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
                }
                .prefix(20),
        )
    }
}

/// One effect-family filter pill. Takes its selected state as a plain `Bool`
/// so only the pills whose selection actually flips re-render.
struct DockFamilyPill: View {
    let family: LibraryFamily
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: family.icon)
                    .imageScale(.small)
                Text(family.title)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isSelected ? AnyShapeStyle(family.color) : AnyShapeStyle(family.color.opacity(0.15)),
                in: Capsule(),
            )
            .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(family.color))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
