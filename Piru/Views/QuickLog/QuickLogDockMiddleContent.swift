import SwiftUI

// MARK: - Scrolling middle content

/// The dock's scrolling middle: search results, browse suggestions, the staged
/// basket, and meta chips (at accessibility sizes). The section spacing
/// (`VStack(spacing: 14)`) lives here — it wraps the multiple
/// children this view produces, which ``QuickLogDock`` would otherwise collapse
/// by hosting this as a single subview.
///
/// Search content swaps deliberately carry NO transitions: fades clip the
/// moment a detent change lays the content out at the final size, and a
/// fade-then-move sequence read worse (a beat of empty sheet). Instant swaps +
/// the animated platter are the model everywhere else in the dock.
struct DockMiddleContent: View {
    let isBare: Bool
    let searchActive: Bool
    let searchText: String
    var tray: DoseTrayModel
    var content: QuickLogContentModel
    let families: [LibraryFamily]
    @Binding var selectedFamilyID: String?
    @Binding var browseResults: [Substance]
    let unrevealedItemIDs: Set<UUID>
    let awaitingBareCollapse: Bool
    /// Present the custom-substance editor. ``QuickLogDock`` releases search
    /// focus before running this — restoring focus mid-transition on dismiss
    /// caused the SheetBridge exclusivity crash (builds 13/14).
    let onCreateCustom: () -> Void
    /// A row (search hit or suggestion) staged a dose. ``QuickLogDock`` uses it
    /// to end an active search — dismiss the keyboard, leave the search state,
    /// and settle onto medium with the new row's editor open — so the results
    /// list no longer covers the row the user just added.
    let onDidStage: () -> Void

    @State private var customSubstanceStore = CustomSubstanceStore.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !isBare {
                if searchActive {
                    if CrisisKeywords.matches(searchText) {
                        QuickLogHelpBanner()
                    } else if searchText.isEmpty {
                        suggestions
                    } else {
                        DockGroupedCard {
                            QuickLogSearchResults(
                                results: results,
                                onAdd: stagePayload,
                                onAddDraft: stageDraftPayload,
                                onCreateCustom: onCreateCustom,
                            )
                        }
                    }
                } else if tray.isEmpty, !awaitingBareCollapse {
                    // Dragged tall with nothing staged: browse suggestions, not
                    // a page of nothing. Suppressed while the dock is shrinking
                    // to bare — that transient is the same shape, but showing
                    // the pills mid-collapse reads as a flash of the search
                    // state.
                    suggestions
                }

                if !tray.isEmpty {
                    // The staged basket never disappears — search results render
                    // above it, so staging more is not a context switch.
                    TrayStagedListCard(model: tray, hiddenItemIDs: unrevealedItemIDs)

                    // At accessibility sizes the When/Tags/Location chips live in
                    // the scroll content: stacked, they made the pinned bar taller
                    // than the compact detent's cap and clipped the Log button
                    // (see ``TrayCommitBar``).
                    if dynamicTypeSize.isAccessibilitySize {
                        TrayMetaChips(model: tray, content: content)
                    }
                }
            }
        }
    }

    private var suggestions: some View {
        DockSuggestions(
            families: families,
            selectedFamilyID: $selectedFamilyID,
            browseResults: $browseResults,
            recents: recentSubstances,
            onStage: stagePayload,
            onStageDraft: stageDraftPayload,
        )
    }

    /// How many recents the empty search state lists before it stops being a
    /// shortcut and starts being a second library.
    private static let recentSuggestionLimit = 8

    /// The recents the dock covers when it goes full-height, resolved back to
    /// library substances so they stage exactly like a search hit — search
    /// results resolve from the same batch projection, so `lookup` is a true
    /// dictionary hit per row.
    private var recentSubstances: [Substance] {
        var seen: Set<String> = []
        var out: [Substance] = []
        for card in content.cachedCards {
            guard out.count < Self.recentSuggestionLimit else { break }
            guard let substance = SubstanceLibrary.lookup(card.substanceName) else { continue }
            guard seen.insert(substance.name.lowercased()).inserted else { continue }
            out.append(substance)
        }
        return out
    }

    // MARK: Staging from rows

    /// Inline Add: a complete dose joins the tray's collapsed rows. Picking a
    /// hit then ends the search (see ``onDidStage``) so the added row surfaces
    /// instead of sitting hidden beneath the results.
    private func stagePayload(_ payload: QuickLogStagePayload) {
        withAnimation(.snappy) {
            tray.stage(
                substance: payload.substance,
                route: payload.route,
                amount: payload.amount,
                unit: payload.unit,
                colorHex: payload.colorHex ?? content.cachedColorLookup[payload.substance.lowercased()],
                librarySubstance: payload.librarySubstance,
                productName: payload.productName,
                volumeML: payload.volumeML,
                abv: payload.abv,
                drinkName: payload.drinkName,
                emoji: payload.emoji,
            )
        }
        onDidStage()
    }

    /// "Add & edit" (by-volume drinks): a draft opens its full editor in the
    /// staged card; picking it likewise ends the search.
    private func stageDraftPayload(_ payload: QuickLogStagePayload) {
        withAnimation(.snappy) {
            tray.stageDraft(
                substance: payload.substance,
                route: payload.route,
                unit: payload.unit,
                colorHex: payload.colorHex ?? content.cachedColorLookup[payload.substance.lowercased()],
                librarySubstance: payload.librarySubstance,
                productName: payload.productName,
            )
        }
        onDidStage()
    }

    // MARK: Search results

    /// The ranked hits shown beneath the field (recent → library → custom).
    private var results: [QuickLogSearchResult] {
        let query = searchText.lowercased()
        guard !query.isEmpty else { return [] }
        let recentCards = content.cachedCards
            // Match the card's names, not its id — the id is now an opaque
            // substance-identity key (a PSID uid), so filtering on it would miss
            // a resolved card by its own name. Matching the product/form title
            // too makes a Concerta recents chip findable by "concerta" (D.1.6).
            .filter { card in
                card.substanceName.lowercased().contains(query)
                    || card.title?.lowercased().contains(query) == true
                    || card.productName?.lowercased().contains(query) == true
            }
            .prefix(2)

        // The same catalog substance can be both a recent and a library hit —
        // list it once. A library match is a duplicate when it shares a recent's
        // PSID uid or, failing that, its canonical name; a genuinely custom
        // substance (no uid, distinct name) collides with neither.
        let recentUIDs = Set(recentCards.compactMap(\.substanceUID).filter { !$0.isEmpty })
        let recentNames = Set(recentCards.map { $0.substanceName.lowercased() })

        var results: [QuickLogSearchResult] = recentCards.map { .recent($0) }
        results += content.cachedLibraryResults
            .filter { match in
                let uidDuplicate = match.substance.substanceUID.map { !$0.isEmpty && recentUIDs.contains($0) } ?? false
                return !(uidDuplicate || recentNames.contains(match.substance.name.lowercased()))
            }
            .prefix(3)
            .map { .library($0) }
        results += filteredCustomSubstances.prefix(1).map { .custom($0) }
        return Array(results.prefix(4))
    }

    private var filteredCustomSubstances: [Substance] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        let libraryNames = Set(content.cachedLibraryResults.map { $0.substance.name.lowercased() })
        return customSubstanceStore.all
            .filter { custom in
                let nameLower = custom.name.lowercased()
                let displayLower = custom.displayName?.lowercased() ?? ""
                // Match the canonical name OR the personal display name, so a
                // relabelled substance is findable by the name the user gave it.
                let matches = nameLower.contains(query) || (!displayLower.isEmpty && displayLower.contains(query))
                return matches
                    && !content.cachedHistoryNames.contains(nameLower)
                    && !libraryNames.contains(nameLower)
            }
            // Resolve through the library so an override of a shipped substance
            // carries its full dose/duration data (labeled with the personal
            // name); a net-new custom falls back to its own asSubstance.
            .compactMap { SubstanceLibrary.lookup($0.name) ?? $0.asSubstance }
    }
}
