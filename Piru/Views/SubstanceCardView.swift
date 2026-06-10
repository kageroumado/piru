import SwiftUI

// MARK: - Substance Card

/// One recent/favorite substance card: header (colour dot, name, glanceable PK
/// badge, favorite star) plus a chip row per route. Extracted from
/// `QuickLogView` so each card is a structural identity in the `LazyVStack`
/// and — crucially — owns its **ephemeral expansion state** locally. Tapping a
/// card's PK badge or "+N" chip-fold used to mutate a parent `@State` set and
/// re-run the *entire* `QuickLogView.body` (dock, toolbar, every other card,
/// re-measuring every `ViewThatFits`); now it re-renders just this card.
struct SubstanceCardView: View {
    let card: SubstanceCard
    let isFavorite: Bool
    let lastEntry: DoseEntry?
    let tray: DoseTrayModel
    let onToggleFavorite: () -> Void
    let onMoveChip: (SubstanceGroup, DoseChip, Bool) -> Void
    let onRemoveChip: (SubstanceGroup, DoseChip) -> Void

    @State private var customSubstanceStore = CustomSubstanceStore.shared
    /// Substances whose PK badge has been expanded into the full advice card.
    @State private var expandedPK = false
    /// (substance|route) groups showing their full chip set instead of the
    /// single folded row.
    @State private var expandedGroups: Set<String> = []

    private var color: Color {
        card.colorHex.map { Color(hex: $0) } ?? .gray
    }

    var body: some View {
        let pkStatus = lastEntry.flatMap {
            DosePK.status(substanceName: card.substanceName, route: $0.route, lastDoseTimestamp: $0.timestamp)
        }
        let showsBadge = (pkStatus?.remainingPercent ?? 0) > 5

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                Text(customSubstanceStore.displayName(for: card.substanceName))
                    .font(.headline)
                // PK status as a glanceable badge instead of a two-line card —
                // tap to expand the full advice when it actually matters. The
                // badge hides while the card is open so the same fact never
                // shows twice; tapping the card collapses it back.
                if showsBadge, let pkStatus, let lastEntry, !expandedPK {
                    Button {
                        withAnimation(.snappy) { expandedPK = true }
                    } label: {
                        DosePKBadge(
                            remainingPercent: pkStatus.remainingPercent,
                            lastDoseAmount: lastEntry.amount,
                            unit: lastEntry.unit,
                            waitMinutes: pkStatus.waitMinutes,
                            lastDoseTimestamp: lastEntry.timestamp,
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Active dose details")
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
            }

            if showsBadge, expandedPK, let lastEntry {
                Button {
                    withAnimation(.snappy) { expandedPK = false }
                } label: {
                    DoseSuggestionCard(
                        substanceName: card.substanceName,
                        lastDoseAmount: lastEntry.amount,
                        lastDoseTimestamp: lastEntry.timestamp,
                        unit: lastEntry.unit,
                        route: lastEntry.route,
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Collapse")
            }

            ForEach(card.routes) { group in
                routeSection(group)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.cardBackground))
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
            .accessibilityLabel("Custom dose")
        }
    }

    /// A single dose chip. Tapping stages it into the tray; re-tap increments
    /// the count ("took two pills" — one bigger entry, never two). A filled
    /// background + count badge mirror the staged state.
    private func doseChip(_ chip: DoseChip, group: SubstanceGroup) -> some View {
        let stagedCount = tray.quantity(substance: group.substanceName, route: group.route, amount: chip.amount, unit: chip.unit)
        return Text("\(chip.formattedAmount) \(chip.unit)")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(stagedCount > 0 ? color : color.opacity(0.15))
            .foregroundStyle(stagedCount > 0 ? .white : color)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .overlay(alignment: .topTrailing) {
                if stagedCount > 1 {
                    chipCountBadge(stagedCount)
                }
            }
            .onTapGesture {
                withAnimation(.snappy) {
                    tray.stage(
                        substance: group.substanceName,
                        route: group.route,
                        amount: chip.amount,
                        unit: chip.unit,
                        colorHex: group.colorHex,
                        librarySubstance: group.librarySubstance,
                    )
                }
            }
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
