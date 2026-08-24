import OSLog
import SwiftData
import SwiftUI
import UIKit
import WidgetKit

/// The dock sheet's content root: owns the detent state and applies the
/// presentation configuration.
///
/// Split out of `QuickLogView` so the dock's detent churn stays local: the
/// detent selection and set are rewritten several times per transition (every
/// stage, search enter/exit, drag settle), and while they were `@State` on
/// `QuickLogView` each write re-ran the *whole screen's* body — toolbar,
/// scroll chrome, and this sheet closure — just to re-apply an unchanged
/// presentation. Owned here, a detent write invalidates only this wrapper.
/// Localizing the re-application also narrows the window where a SwiftUI
/// presentation update can rewrite the sheet's detents mid-ramp (the
/// self-heal in `QuickLogDock.animateHeightDetent` exists for exactly that).
///
/// Presentation configuration lives at this view's root so it reliably
/// reaches the presentation (not shadowed by the nested sheet wrappers
/// above it). The background *style* is clear: that swaps the default
/// full-width sheet backing for the system's inset floating glass platter,
/// which is the dock's one surface in every detent (Maps' collapsed-bar
/// look at peek).
struct DockSheetHost: View {
    var tray: DoseTrayModel
    var content: QuickLogContentModel
    var containerHeight: CGFloat
    @Binding var searchText: String
    @Binding var searchActive: Bool
    /// Owned by `QuickLogView` (its body hides the cover content from
    /// assistive tech while either sheet is up); presented from here because
    /// the dock occupies the cover's only presentation slot, so these must
    /// stack on the dock.
    @Binding var showCustomForm: Bool
    @Binding var showEditSheet: Bool
    @Binding var showScanner: Bool
    let onCommit: () -> Void

    @Environment(\.appNavigator) private var navigator

    /// The dock's current detent. ``QuickLogDock`` drives the transitions.
    @State private var detent: PresentationDetent = QuickLogDockMetrics.peekDetent
    /// The live detent set — dynamic because the dock's smallest detent is
    /// fit-to-content once doses are staged. ``QuickLogDock`` owns the swaps.
    @State private var detents: Set<PresentationDetent> = QuickLogDockMetrics.emptyDetents

    @State private var pendingCustomPrefill: EntryPrefillPayload?

    var body: some View {
        QuickLogDock(
            tray: tray,
            content: content,
            containerHeight: containerHeight,
            searchText: $searchText,
            searchActive: $searchActive,
            detent: $detent,
            detents: $detents,
            onCreateCustom: { showCustomForm = true },
            onCommit: onCommit,
        )
        .sheet(isPresented: $showCustomForm, onDismiss: onCustomFormDismiss) {
            CustomSubstanceFormView(initialName: searchText.trimmingCharacters(in: .whitespaces)) { saved in
                pendingCustomPrefill = EntryPrefillPayload(
                    substance: saved.name,
                    route: saved.defaultRoute,
                    unit: saved.unit,
                )
            }
        }
        .sheet(isPresented: $showEditSheet) {
            QuickLogEditSheet()
        }
        // The label scanner stacks on the dock (the cover's slot is taken), like
        // the sheets above — full-screen for the live camera.
        .fullScreenCover(isPresented: $showScanner) {
            LabelScannerView(
                onResolved: stageScanned,
                onSearch: { text in
                    searchText = text
                    searchActive = true
                },
            )
        }
        // Navigator sheets launched from quick log (Manage Routines, Edit
        // Routine…) present here, stacked on the dock — the dock occupies
        // the cover's only presentation slot, so they can't present there.
        .hostsNestedNavigatorSheets(navigator)
        .presentationDetents(detents, selection: $detent)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationContentInteraction(.resizes)
        .presentationBackground { Color.clear }
        .interactiveDismissDisabled()
    }

    /// Stage a scanned label as a complete dose — the strength read off the box
    /// pre-fills the amount, so it lands like a tapped chip. The scanned brand
    /// rides along as `productName` (canonical name stays the substance's own),
    /// exactly as a search hit does.
    private func stageScanned(_ resolved: ResolvedDrug) {
        withAnimation(.snappy) {
            tray.stage(
                substance: resolved.canonicalName,
                route: resolved.stagingRoute,
                amount: resolved.stagingAmount,
                unit: resolved.stagingUnit,
                colorHex: content.cachedColorLookup[resolved.canonicalName.lowercased()],
                librarySubstance: resolved.substance,
                productName: resolved.brandName,
            )
            searchActive = false
            searchText = ""
        }
    }

    private func onCustomFormDismiss() {
        guard let prefill = pendingCustomPrefill else { return }
        pendingCustomPrefill = nil
        withAnimation(.snappy) {
            tray.stageDraft(
                substance: prefill.substance,
                route: prefill.route,
                unit: prefill.unit,
                colorHex: content.cachedColorLookup[prefill.substance.lowercased()],
                librarySubstance: SubstanceLibrary.lookup(prefill.substance.lowercased()),
            )
            searchActive = false
            searchText = ""
        }
    }
}

// MARK: - Staging Haptics

/// A zero-size leaf that fires the staging haptics. It exists so the tick-counter
/// reads (`stageTick` / `incrementTick`) live *here* and not in `QuickLogView.body`
/// — reading the `@Observable` counters in the parent body would re-run the whole
/// quick-log screen on every chip tap. Mounted always-present via `.background`,
/// so it fires regardless of which dock face is showing.
struct StagingHaptics: View {
    let tray: DoseTrayModel

    var body: some View {
        Color.clear
            .sensoryFeedback(.impact(weight: .light), trigger: tray.stageTick)
            .sensoryFeedback(.increase, trigger: tray.incrementTick)
    }
}

// MARK: - Cover Accessibility Unmasker

/// Restores VoiceOver access to the dock sheet at undimmed detents.
///
/// UIKit marks the quick-log cover's `UITransitionView` `accessibilityViewIsModal`
/// (it's a full-screen modal), and VoiceOver ignores every *sibling* of a modal
/// view — which includes the always-presented dock sheet's own transition view
/// whenever the dock is non-modal (peek/compact/medium, i.e. whenever
/// `presentationBackgroundInteraction` leaves it undimmed). Net effect: at rest
/// the search field, staged doses, and Log Dose are invisible to assistive tech;
/// at `.large` the dock's transition view turns modal itself, wins as topmost,
/// and the situation flips (verified via lldb: both transition views, flag by
/// detent). The full-screen presentation already removes the Journal underneath
/// from the hierarchy, so the cover's modal flag protects nothing — clearing it
/// exposes cover content and dock together, while the dock's *own* modal flag
/// still correctly masks the cover at `.large`.
///
/// Public-API superview walk from a hosted leaf, same pattern as the (retired)
/// `SheetPlatterHider`. Re-asserted from `layoutSubviews` because UIKit can
/// re-apply the flag across presentation transitions.
struct CoverAccessibilityUnmasker: UIViewRepresentable {
    func makeUIView(context _: Context) -> UnmaskView {
        UnmaskView()
    }
    func updateUIView(_: UnmaskView, context _: Context) {}

    final class UnmaskView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            unmask()
            // The presentation transition can set the flag after this view
            // lands in the window — re-check once the current turn settles.
            DispatchQueue.main.async { [weak self] in self?.unmask() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            unmask()
        }

        private func unmask() {
            var ancestor = superview
            while let view = ancestor {
                if view.accessibilityViewIsModal {
                    view.accessibilityViewIsModal = false
                    UIAccessibility.post(notification: .layoutChanged, argument: nil)
                    break
                }
                ancestor = view.superview
            }
        }
    }
}

// MARK: - Card List

/// The quick-log scroll content — routines, favorites, and recent cards.
///
/// Extracted from `QuickLogView` as a **closure-free** child: it takes only the
/// two stable references it needs (`content`, `tray`) and owns its own `@Query`s
/// and list-mutating actions, so it passes *no* parent closures. That matters
/// because closures can't be compared — a view holding them is always treated as
/// changed, forcing its body to re-run whenever the parent does. `QuickLogView`'s
/// body re-runs on every search keystroke (it reads `searchText`/`dockResults`),
/// which used to cascade into every `SubstanceCardView`/`OneRowChips` body (a
/// phone SwiftUI trace of the search/dock flow showed ~28k view-body updates
/// dominated by that chain). With only stable references here, SwiftUI's
/// view-value comparison finds this subtree unchanged and skips it when the
/// parent re-renders for state the list doesn't depend on. The cards still update
/// through their own observation (the `content` caches, `tray` staging) — which
/// is exactly the scope we want.
struct QuickLogCardList: View {
    let content: QuickLogContentModel
    let tray: DoseTrayModel

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appNavigator) private var navigator

    @Query private var quickLogDoses: [QuickLogDose]
    @Query(sort: [SortDescriptor(\FavoriteSubstance.sortOrder), SortDescriptor(\FavoriteSubstance.createdAt, order: .reverse)]) private var favorites: [FavoriteSubstance]

    /// Folds the Routines & Prescriptions section down to its header — for
    /// people who don't use the feature. Persisted across launches.
    @AppStorage("quickLogRoutinesCollapsed") private var routinesCollapsed = false

    var body: some View {
        // Snapshot staged counts once per staging change; each card takes only
        // its own slice, so a card whose staged state is unchanged is skipped by
        // its `.equatable()` rather than re-diffing every chip + context menu.
        let staged = tray.stagedCountsBySubstance()
        return LazyVStack(alignment: .leading, spacing: 12) {
            if !content.hasLoaded {
                // Loading: render nothing (the dock stays put) rather than
                // the empty-state placeholder — the caches fill within a
                // frame or two off the warm batch cache, so this avoids the
                // jarring "No Previous Substances" flash on open.
                EmptyView()
            } else {
                scrollContentInner(staged: staged)
            }
        }
    }

    /// One header style for every section: sentence case, no icon, no caps —
    /// matching how the rest of the app titles things. The extra top padding
    /// separates sections; header → content is the stack's own 12pt.
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.secondaryLabel)
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func scrollContentInner(staged: [String: StagedChipCounts]) -> some View {
        // "What should I take NOW?" answers first (Specs/meds-ux-review.md §5)
        // — the strip disappears entirely when nothing is due, no dead chrome.
        if !content.cachedDueNow.isEmpty {
            dueNowSection(staged: staged)
        }

        // Meds are always surfaced (discoverability) — with none defined
        // the section is just the Add a Med pill, and the whole thing is
        // collapsible for people who don't use it.
        dailySection(staged: staged)

        if content.cachedCards.isEmpty, content.cachedDailyGroups.isEmpty {
            ContentUnavailableView(
                "No Previous Substances",
                systemImage: "magnifyingglass",
                description: Text("Search for a substance to log your first entry."),
            )
        }

        // ONE substances section — favorites pinned first (their saved order),
        // recents filling behind. Two headers ("Favorites" / "Recent") made
        // three competing lists on one screen; the split is still visible
        // through the star, without costing a second decision.
        if !content.cachedCards.isEmpty || !content.cachedFavoriteLibrarySubstances.isEmpty {
            sectionHeader("Your Substances")
            ForEach(content.cachedFavoriteCards) { card in
                cardView(card, isFavorite: true, staged: staged)
                    .id("\(card.id)_fav")
            }
            ForEach(content.cachedFavoriteLibrarySubstances) { substance in
                libraryRow(substance)
            }
            ForEach(content.cachedNonFavoriteCards) { card in
                cardView(card, isFavorite: false, staged: staged)
                    .id("\(card.id)_recent")
            }
        }
    }

    // MARK: - Due now

    @ViewBuilder
    private func dueNowSection(staged: [String: StagedChipCounts]) -> some View {
        let slots = content.cachedDueNow
        let loud = slots.filter { !$0.isQuiet }
        let quiet = slots.filter(\.isQuiet)
        // ≥2 quiet slots fold into one Supplements row (the hub/card rule);
        // a lone quiet med just shows as itself.
        let collapseQuiet = quiet.count >= 2

        sectionHeader("Due now")
        VStack(spacing: 0) {
            ForEach(loud) { slot in
                dueNowRow(slot, staged: staged)
            }
            if collapseQuiet {
                DueNowRowView(
                    timeText: quiet.compactMap(\.slotMinutes).min().map(Self.timeText),
                    title: String(localized: "Supplements"),
                    // "med" isn't in the system inflection lexicon; the fold
                    // only exists at ≥2, so the plural is safe to hardcode.
                    subtitle: String(localized: "\(quiet.count) meds"),
                    staged: quiet.allSatisfy { stagedQuantity($0.item, staged: staged) > 0 },
                    onTap: {
                        withAnimation(.snappy) {
                            for slot in quiet where stagedQuantity(slot.item, staged: staged) == 0 {
                                stageDailyItem(slot.item)
                            }
                        }
                    },
                )
            } else {
                ForEach(quiet) { slot in
                    dueNowRow(slot, staged: staged)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .themeCard()
    }

    private func dueNowRow(_ slot: DueNowSlot, staged: [String: StagedChipCounts]) -> some View {
        DueNowRowView(
            timeText: slot.slotMinutes.map(Self.timeText),
            title: slot.item.productName ?? CustomSubstanceStore.shared.displayName(for: slot.item.substance),
            subtitle: "\(slot.item.amount.doseFormatted) \(slot.item.unit)",
            staged: stagedQuantity(slot.item, staged: staged) > 0,
            onTap: { withAnimation(.snappy) { stageDailyItem(slot.item) } },
        )
    }

    private static func timeText(_ minutes: Int) -> String {
        let date = Calendar.current.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now,
        ) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Daily routine

    @ViewBuilder
    private func dailySection(staged: [String: StagedChipCounts]) -> some View {
        // The collapse toggle is the whole header row — chevron included.
        Button {
            withAnimation(.snappy) { routinesCollapsed.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text("My Meds")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(routinesCollapsed ? 0 : 90))
                Spacer()
            }
            .foregroundStyle(Theme.secondaryLabel)
            .padding(.top, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("My Meds")
        .accessibilityValue(routinesCollapsed ? Text("Collapsed") : Text("Expanded"))

        if !routinesCollapsed {
            FlowLayout(spacing: 8) {
                ForEach(content.cachedDailyGroups) { group in
                    routinePill(group, staged: staged)
                }
                manageMedsPill
            }
        }
    }

    /// Trailing pill of the meds row — adding/editing meds lives with the
    /// pills they produce.
    private var manageMedsPill: some View {
        Button {
            navigator.present(.dailyDoseSettings)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .imageScale(.small)
                Text("Add a Med")
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color(.secondarySystemFill), in: Capsule())
            .foregroundStyle(Theme.secondaryLabel)
        }
        .buttonStyle(.plain)
    }

    /// A time-of-day group is one pill — a *shortcut* that stages its whole
    /// set into the tray in one tap (the eight-supplements use case),
    /// idempotent for anything already staged. The checkmark is informational
    /// ("all of these were logged today"); the pill stays tappable for
    /// re-logs. Long-press to manage meds.
    private func routinePill(_ group: DailyCategoryGroup, staged: [String: StagedChipCounts]) -> some View {
        let done = group.remaining.isEmpty
        let allStaged = group.items.allSatisfy { stagedQuantity($0, staged: staged) > 0 }
        return Button {
            withAnimation(.snappy) {
                for item in group.items where stagedQuantity(item, staged: staged) == 0 {
                    stageDailyItem(item)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: done ? "checkmark" : group.icon)
                    .imageScale(.small)
                Text(group.title)
                // A single-med pill (every PRN med) is just its name — "· 1"
                // is noise.
                if group.items.count > 1 {
                    Text(verbatim: "· \(group.items.count)")
                        .opacity(0.75)
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                allStaged
                    ? Theme.accent
                    : done ? Color.green.opacity(0.12) : Theme.accent.opacity(0.12),
                in: Capsule(),
            )
            .foregroundStyle(
                allStaged
                    ? Color.white
                    : done ? Color.green : Theme.accent,
            )
        }
        .buttonStyle(.plain)
        // Otherwise reads "Daily, middle dot, 2"; speak it as a clean
        // label + item count, with the logged-today state as a value.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(group.title)
        .accessibilityValue(
            done
                ? Text("^[\(group.items.count) item](inflect: true), all logged today")
                : Text("^[\(group.items.count) item](inflect: true)"),
        )
        .accessibilityHint("Stages this group’s meds")
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            Button {
                navigator.present(.dailyDoseSettings)
            } label: {
                Label("Manage Meds…", systemImage: "pencil")
            }
        }
    }

    private func stagedQuantity(_ item: DailyDoseItem, staged: [String: StagedChipCounts]) -> Int {
        staged[item.substance.lowercased()]?.count(route: item.route, amount: item.amount, unit: item.unit) ?? 0
    }

    // MARK: - Due-now row

    /// One due slot: time leading, med + dose center, one big check trailing
    /// (the Pillo-row grammar, in Apple's visual language). Its own struct —
    /// value inputs only — so a staging change re-evaluates rows, not the list.
    private struct DueNowRowView: View {
        let timeText: String?
        let title: String
        let subtitle: String
        let staged: Bool
        let onTap: () -> Void

        var body: some View {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Text(timeText.map(\.self) ?? String(localized: "Anytime"))
                        .font(.subheadline.weight(.medium).monospacedDigit())
                        .foregroundStyle(Theme.secondaryLabel)
                        .frame(width: 64, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    Spacer()
                    Image(systemName: staged ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(staged ? Theme.accent : Color(.tertiaryLabel))
                        .contentTransition(.symbolEffect(.replace))
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(title), \(subtitle)"))
            .accessibilityValue(staged ? Text("Staged") : Text("Due"))
            .accessibilityHint("Stages this dose")
            .accessibilityAddTraits(.isButton)
        }
    }

    private func stageDailyItem(_ item: DailyDoseItem) {
        tray.stage(
            substance: item.substance,
            route: item.route,
            amount: item.amount,
            unit: item.unit,
            colorHex: content.cachedColorLookup[item.substance.lowercased()],
            librarySubstance: SubstanceLibrary.lookup(item.substance.lowercased()),
            // Carry the daily item's product so a Concerta med logs as Concerta —
            // the tray derives the release form/isomer from it, same as search.
            productName: item.productName,
            isFromDailySet: true,
            isBackgroundMed: item.isBackgroundMed,
        )
    }

    // MARK: - Substance Card

    /// Builds the extracted ``SubstanceCardView`` for a recent/favorite card,
    /// wiring the list-owned actions (favorite toggle + curated-list edits)
    /// while the card itself owns its layout and ephemeral expansion state.
    private func cardView(_ card: SubstanceCard, isFavorite: Bool, staged: [String: StagedChipCounts]) -> some View {
        SubstanceCardView(
            card: card,
            isFavorite: isFavorite,
            badge: content.cachedMostRecent[card.id],
            stagedCounts: staged[card.id] ?? .empty,
            tray: tray,
            onToggleFavorite: { withAnimation(.snappy) { toggleFavorite(card) } },
            onMoveChip: { group, chip, toFront in moveChip(group: group, chip: chip, toFront: toFront) },
            onRemoveChip: { group, chip in removeChip(group: group, chip: chip) },
            onRemoveCard: { withAnimation(.snappy) { removeCard(card) } },
        )
        // Skip rebuilding this card (its chip buttons + context menus) when its
        // content and staged slice are unchanged — the staging-cascade fix.
        .equatable()
    }

    private func toggleFavorite(_ card: SubstanceCard) {
        let nowFavorite = FavoriteService.toggle(
            substance: card.substanceName,
            substanceUID: card.substanceUID,
            isomer: card.isomer,
            releaseForm: card.releaseForm,
            saltForm: card.saltForm,
            productName: card.productName,
            in: modelContext,
        )
        content.setFavorite(identity: card.id, on: nowFavorite)
    }

    // MARK: - Library Row

    private func libraryRow(_ substance: Substance) -> some View {
        Button {
            openLibrarySubstance(substance)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "pill")
                    .foregroundStyle(Theme.secondaryLabel)
                VStack(alignment: .leading, spacing: 2) {
                    Text(substance.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("\(substance.defaultRoute.displayName) \u{2014} \(substance.defaultUnit)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .padding(14)
            .themeCard(cornerRadius: 20)
        }
        .buttonStyle(.plain)
    }

    /// Staging-only counterpart to `QuickLogView.openLibrarySubstance` — a card
    /// in the list isn't a search surface, so it stages a draft without the
    /// search-state reset the dock version performs.
    private func openLibrarySubstance(_ substance: Substance) {
        withAnimation(.snappy) {
            tray.stageDraft(
                substance: substance.name,
                route: substance.defaultRoute,
                unit: substance.defaultUnit,
                colorHex: content.cachedColorLookup[substance.name.lowercased()],
                librarySubstance: substance,
            )
        }
    }

    // MARK: - Quick-log list curation

    /// The curated row backing a chip, matched by substance + route + measurement.
    private func quickLogDose(for group: SubstanceGroup, chip: DoseChip) -> QuickLogDose? {
        let key = QuickLogDose.makeKey(
            substance: group.substanceName,
            route: group.route,
            amount: chip.amount,
            unit: chip.unit,
            substanceUID: group.substanceUID,
            isomer: group.isomer,
            releaseForm: group.releaseForm,
            saltForm: group.saltForm,
            volumeML: chip.volumeML,
            abv: chip.abv,
            drinkName: chip.drinkName,
        )
        return quickLogDoses.first { $0.key == key }
    }

    /// Remove a whole substance from the quick-log list — every chip on every
    /// route, in one action, and it stays removed across the history re-seed.
    private func removeCard(_ card: SubstanceCard) {
        QuickLogManager.removeFromRecents(identityKey: card.id, context: modelContext)
        content.rebuildCards(quickLogDoses: quickLogDoses, favorites: favorites)
    }

    private func removeChip(group: SubstanceGroup, chip: DoseChip) {
        guard let dose = quickLogDose(for: group, chip: chip) else { return }
        modelContext.delete(dose)
        try? modelContext.save()
        withAnimation(.snappy) { content.rebuildCards(quickLogDoses: quickLogDoses, favorites: favorites) }
    }

    /// Move a chip to the front (or back) of its (substance, route) group by
    /// rewriting its `sortOrder` just past the current min/max.
    private func moveChip(group: SubstanceGroup, chip: DoseChip, toFront: Bool) {
        guard let dose = quickLogDose(for: group, chip: chip) else { return }
        // Reorder within the same (identity, route) group — a Concerta chip floats
        // past its Concerta siblings, not Ritalin's.
        let siblings = quickLogDoses.filter { $0.identityKey == group.cardKey && $0.route == group.route }
        if toFront {
            dose.sortOrder = (siblings.map(\.sortOrder).min() ?? 0) - 1
        } else {
            dose.sortOrder = (siblings.map(\.sortOrder).max() ?? 0) + 1
        }
        try? modelContext.save()
        withAnimation(.snappy) { content.rebuildCards(quickLogDoses: quickLogDoses, favorites: favorites) }
    }
}
