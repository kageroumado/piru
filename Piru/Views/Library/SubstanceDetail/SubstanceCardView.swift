import SwiftData
import SwiftUI

// MARK: - Substance Card

/// One recent/favorite substance card: header (color dot, name, glanceable PK
/// badge, favorite star) plus a chip row per route. Extracted from
/// `QuickLogView` so each card is a structural identity in the `LazyVStack`
/// and — crucially — owns its **ephemeral expansion state** locally. Tapping a
/// card's PK badge or "+N" chip-fold used to mutate a parent `@State` set and
/// re-run the *entire* `QuickLogView.body` (dock, toolbar, every other card,
/// re-measuring every `ViewThatFits`); now it re-renders just this card.
struct SubstanceCardView: View, Equatable {
    let card: SubstanceCard
    let isFavorite: Bool
    /// Precomputed PK badge for this card's most recent dose, built in
    /// `QuickLogContentModel` when the history-derived caches rebuild — so the
    /// per-card `DosePK.status` call (two `SubstanceLibrary` lookups + PK math)
    /// and the live-`DoseEntry` reads no longer run inside `body` on every
    /// render.
    let badge: CardPKBadge?
    /// This card's staged chip counts, as a *value* snapshot. The card used to
    /// read `tray.quantity(...)` per chip in `body`, which subscribed it to the
    /// whole `DoseTrayModel` — so any staging change anywhere re-ran every card's
    /// body and re-diffed thousands of chip buttons + context menus. Taking a
    /// comparable slice instead lets `.equatable()` skip every card but the one
    /// whose own staged state changed. The `tray` is kept for *actions* only
    /// (staging on tap), which don't subscribe the body.
    let stagedCounts: StagedChipCounts
    let tray: DoseTrayModel
    let onToggleFavorite: () -> Void
    let onMoveChip: (SubstanceGroup, DoseChip, Bool) -> Void
    let onRemoveChip: (SubstanceGroup, DoseChip) -> Void
    /// Remove the whole substance from the quick-log list.
    let onRemoveCard: () -> Void

    /// Compare only the rendered inputs — not the `tray` reference (a single
    /// shared instance) or the parent-supplied action closures (uncomparable, and
    /// they capture only stable references). Paired with `.equatable()` at the
    /// call site, this lets SwiftUI keep the existing card instance when its
    /// content + staged state are unchanged, instead of rebuilding its chip
    /// buttons and context menus on every sibling's staging change.
    static func == (lhs: SubstanceCardView, rhs: SubstanceCardView) -> Bool {
        lhs.card == rhs.card
            && lhs.isFavorite == rhs.isFavorite
            && lhs.badge == rhs.badge
            && lhs.stagedCounts == rhs.stagedCounts
    }

    @State private var customSubstanceStore = CustomSubstanceStore.shared
    /// Tracked inventory items — drives the passive "X left" hint. A `@Query`
    /// here re-renders only this card when stock changes, never the whole list.
    @Query private var inventoryItems: [InventoryItem]
    /// Substances whose PK badge has been expanded into the full advice card.
    @State private var expandedPK = false
    /// (substance|route) groups showing their full chip set instead of the
    /// single folded row.
    @State private var expandedGroups: Set<String> = []

    private var color: Color {
        card.colorHex.map { Color(hex: $0) } ?? .gray
    }

    var body: some View {
        let showsBadge = badge?.showsBadge ?? false

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                // A product/form card titles by what the user named ("Concerta",
                // "Methylphenidate XR"); a plain card keeps the regionalized,
                // relabel-aware display name.
                Text(card.title ?? customSubstanceStore.displayName(for: card.substanceName))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                // PK status as a glanceable badge instead of a two-line card —
                // tap to expand the full advice when it actually matters. The
                // badge hides while the card is open so the same fact never
                // shows twice; tapping the card collapses it back.
                if showsBadge, let badge, !expandedPK {
                    Button {
                        withAnimation(.snappy) { expandedPK = true }
                    } label: {
                        DosePKBadge(
                            remainingPercent: badge.remainingPercent,
                            lastDoseAmount: badge.lastDoseAmount,
                            unit: badge.lastDoseUnit,
                            waitMinutes: badge.waitMinutes,
                            lastDoseTimestamp: badge.lastDoseTimestamp,
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Active dose")
                    .accessibilityValue(badge.accessibilityValue)
                    .accessibilityHint("Shows dosing advice")
                }
                Spacer()
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.body)
                        .foregroundStyle(isFavorite ? Color.yellow : Theme.secondaryLabel)
                        .contentTransition(.symbolEffect(.replace))
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                // The card's own menu. Removing a substance from the list used
                // to mean long-pressing every chip it had — up to eight per
                // route — because the only delete lived in the chip's context
                // menu and nothing on screen said that menu existed. This is
                // also where the per-chip actions become discoverable: a
                // visible control that admits the card is editable.
                Menu {
                    Button(role: .destructive, action: onRemoveCard) {
                        Label("Remove from Quick Log", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body)
                        .foregroundStyle(Theme.secondaryLabel)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More actions")
            }

            if showsBadge, expandedPK, let badge {
                Button {
                    withAnimation(.snappy) { expandedPK = false }
                } label: {
                    DoseSuggestionCard(
                        substanceName: card.substanceName,
                        lastDoseAmount: badge.lastDoseAmount,
                        lastDoseTimestamp: badge.lastDoseTimestamp,
                        unit: badge.lastDoseUnit,
                        route: badge.lastDoseRoute,
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Collapses the dosing advice")
            }

            inventoryHint

            ForEach(card.routes) { group in
                routeSection(group)
            }
        }
        .padding(14)
        .themeCard(cornerRadius: 20)
        // Group the card's elements into one container so a VoiceOver user can
        // tell which name/badge/chips belong together, instead of 8–10 loose
        // siblings whose card-membership is only inferable from reading order.
        .accessibilityElement(children: .contain)
    }

    /// The matching tracked item for this card's substance (salt-agnostic — the
    /// card isn't salt-specific; prefer the base form).
    private var inventoryItem: InventoryItem? {
        let name = card.substanceName.lowercased()
        let matches = inventoryItems.filter { $0.substance.lowercased() == name }
        return matches.first { $0.saltForm == nil } ?? matches.first
    }

    /// Passive stock hint (1B): a supply bar (only when a baseline is set) with
    /// the "X left" amount on the line below. Nothing for untracked substances —
    /// the quick-log flow stays nudge-free.
    @ViewBuilder
    private var inventoryHint: some View {
        if let item = inventoryItem {
            VStack(alignment: .leading, spacing: 4) {
                if let fraction = item.fillFraction {
                    InventorySupplyBar(fraction: fraction, tint: item.stockStatus.barTint)
                }
                Text(stockHintText(item))
                    .font(.caption)
                    .foregroundStyle(item.stockStatus == .ok ? Theme.secondaryLabel : item.stockStatus.numberColor)
            }
        }
    }

    private func stockHintText(_ item: InventoryItem) -> String {
        if item.stockStatus == .out { return String(localized: "Out of stock") }
        return String(localized: "\(item.currentQuantity.inventoryFormatted) \(item.unit) left")
    }

    private func routeSection(_ group: SubstanceGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.route.localizedName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.top, 4)

            doseChips(for: group)
        }
    }

    private func doseChips(for group: SubstanceGroup) -> some View {
        OneRowChips(
            items: group.doses,
            isExpanded: expandedGroups.contains(group.id),
            onExpand: {
                withAnimation(.snappy) { _ = expandedGroups.insert(group.id) }
            },
        ) { chip in
            doseChip(chip, group: group)
        } trailing: {
            Button {
                withAnimation(.snappy) {
                    tray.stageDraft(
                        substance: group.substanceName,
                        route: group.route,
                        unit: group.doses.first?.unit ?? "mg",
                        colorHex: group.colorHex,
                        librarySubstance: group.librarySubstance,
                        productName: group.stageProductName,
                    )
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.tint.opacity(0.12))
                    .foregroundStyle(.tint)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Custom dose of \(customSubstanceStore.displayName(for: group.substanceName))")
        }
    }

    /// A single dose chip. Tapping stages it into the tray; re-tap increments
    /// the count ("took two pills" — one bigger entry, never two). A filled
    /// background + count badge mirror the staged state.
    private func doseChip(_ chip: DoseChip, group: SubstanceGroup) -> some View {
        let stagedCount = stagedCounts.count(route: group.route, amount: chip.amount, unit: chip.unit)
        return Button {
            withAnimation(.snappy) {
                tray.stage(
                    substance: group.substanceName,
                    route: group.route,
                    amount: chip.amount,
                    unit: chip.unit,
                    colorHex: group.colorHex,
                    librarySubstance: group.librarySubstance,
                    productName: group.stageProductName,
                    volumeML: chip.volumeML,
                    abv: chip.abv,
                    drinkName: chip.drinkName,
                    emoji: chip.emoji,
                )
            }
            // Staging is otherwise conveyed by color alone — the tree is
            // byte-identical after a tap. Speak it so a VoiceOver user gets
            // confirmation the tap did something.
            UIAccessibility.post(
                notification: .announcement,
                argument: String(localized: "Staged \(customSubstanceStore.displayName(for: group.substanceName))"),
            )
        } label: {
            chipLabel(chip)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, chip.hasDrinkDetail ? 8 : 6)
                .background(stagedCount > 0 ? color : color.opacity(0.15))
                .foregroundStyle(stagedCount > 0 ? .white : color)
                .clipShape(chip.hasDrinkDetail ? AnyShape(RoundedRectangle(cornerRadius: 16, style: .continuous)) : AnyShape(Capsule()))
                .contentShape(chip.hasDrinkDetail ? AnyShape(RoundedRectangle(cornerRadius: 16, style: .continuous)) : AnyShape(Capsule()))
                .overlay(alignment: .topTrailing) {
                    if stagedCount > 1 {
                        chipCountBadge(stagedCount)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chipAccessibilityLabel(chip, group: group))
        .accessibilityValue(stagedCount > 0 ? Text("\(stagedCount) staged") : Text(verbatim: ""))
        .accessibilityAddTraits(stagedCount > 0 ? [.isSelected] : [])
        .contextMenu {
            Button {
                onMoveChip(group, chip, true)
            } label: { Label("Move to Front", systemImage: "arrow.up.to.line") }
            Button {
                onMoveChip(group, chip, false)
            } label: { Label("Move to Back", systemImage: "arrow.down.to.line") }
            Divider()
            Button(role: .destructive) {
                onRemoveChip(group, chip)
            } label: { Label("Remove from Quick Log", systemImage: "trash") }
        }
    }

    /// Drink chips (alcohol recents) show emoji · name over a "volume · % · grams"
    /// subtitle; ordinary chips show the bare gram/mg amount.
    @ViewBuilder
    private func chipLabel(_ chip: DoseChip) -> some View {
        if chip.hasDrinkDetail {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    if let emoji = chip.emoji { Text(emoji) }
                    if let name = chip.drinkName, !name.isEmpty {
                        Text(name).fontWeight(.semibold)
                    } else {
                        Text("\(chip.formattedAmount) \(chip.unit.unitDisplay(for: chip.amount))").fontWeight(.semibold)
                    }
                }
                Text(chip.detailLine)
                    .font(.caption2.weight(.semibold))
                    .opacity(0.9)
            }
        } else {
            Text("\(chip.formattedAmount) \(chip.unit.unitDisplay(for: chip.amount))")
        }
    }

    /// Spoken label: "Log IPA, 330 mL · 6% · 16 g" for a drink, else
    /// "Log 20 g of Caffeine" — the substance is named because a VoiceOver
    /// user swiping chip-to-chip mid-list has no visual row context.
    private func chipAccessibilityLabel(_ chip: DoseChip, group: SubstanceGroup) -> Text {
        let substance = customSubstanceStore.displayName(for: group.substanceName)
        guard chip.hasDrinkDetail else {
            return Text("Log \(chip.formattedAmount) \(chip.unit.unitDisplay(for: chip.amount)) of \(substance)")
        }
        if let name = chip.drinkName, !name.isEmpty {
            return Text("Log \(name), \(chip.detailLine)")
        }
        return Text("Log \(chip.detailLine) of \(substance)")
    }

    private func chipCountBadge(_ count: Int) -> some View {
        Text(verbatim: "\(count)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Theme.accent, in: Capsule())
            .offset(x: 6, y: -7)
    }
}
