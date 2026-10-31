import SwiftData
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// The staged doses as a grouped-style card (matching the system inset-grouped
/// list): one row per dose, expanding inline into its editor — never a second
/// sheet. Every row — collapsed or expanded — swipes left to delete.
struct TrayStagedListCard: View {
    @Bindable var model: DoseTrayModel
    /// Rows withheld from rendering while the dock sheet grows to fit them —
    /// see `QuickLogDock.unrevealedItemIDs` for the sequencing rationale.
    var hiddenItemIDs: Set<UUID> = []

    /// Ties each collapsed row to its expanded editor so the name, amount,
    /// route, and chevron morph in place instead of cross-fading.
    @Namespace private var morphNamespace

    var body: some View {
        let products = productLayout()
        let lastVisibleID = model.staged.last(where: { !hiddenItemIDs.contains($0.id) && !products.folded.contains($0.id) })?.id
        VStack(spacing: 0) {
            ForEach($model.staged) { $item in
                if !hiddenItemIDs.contains(item.id), !products.folded.contains(item.id) {
                    TraySwipeRow(onDelete: {
                        withAnimation(.snappy) {
                            if let product = products.leads[item.id] {
                                model.removeCombination(product.name)
                            } else {
                                model.remove(item)
                            }
                        }
                    }) {
                        // The horizontal inset is applied OUTSIDE the swap, not
                        // inside each branch. Padding that changes across a
                        // matched-geometry morph moves the container's edges on
                        // a different curve from the frame-interpolated pairs
                        // inside it, which is what made the expansion read as a
                        // lurch. The editor's extra vertical breathing room is
                        // its own business and stays on its branch — that one
                        // doesn't fight the morph because no pair spans it.
                        Group {
                            if let product = products.leads[item.id] {
                                TrayProductCell(product: product, leadID: item.id, model: model, namespace: morphNamespace)
                            } else if model.expandedItemIDs.contains(item.id) {
                                StagedDoseEditor(
                                    item: $item,
                                    namespace: morphNamespace,
                                    onCollapse: {
                                        withAnimation(.snappy) { _ = model.expandedItemIDs.remove(item.id) }
                                    },
                                )
                                .padding(.vertical, Spacing.md)
                            } else {
                                // Long-press only on the collapsed row: the open
                                // editor holds a text field whose own long-press
                                // (cursor, paste) a context menu would take over.
                                TrayRow(dose: item, model: model, namespace: morphNamespace)
                                    .contextMenuPreviewShape(Rectangle())
                                    .contextMenu {
                                        TrayRowContextMenu(model: model, item: item)
                                    }
                            }
                        }
                        .padding(.horizontal, Spacing.xxl)
                    }
                    if item.id != lastVisibleID {
                        Divider().padding(.leading, Spacing.xxl)
                    }
                }
            }
        }
        .background(
            Color.platformSecondarySystemGroupedBackground,
            in: RoundedRectangle(cornerRadius: DoseTrayMetrics.cardCornerRadius, style: .continuous),
        )
    }

    /// The combination products in the tray: each one's lead row (the first
    /// staged from it), which draws the whole product, and the rest of its
    /// rows, which the card folds under it. A row whose product is no longer
    /// defined stays a row of its own.
    private func productLayout() -> (leads: [UUID: CustomSubstanceEntry], folded: Set<UUID>) {
        var leads: [UUID: CustomSubstanceEntry] = [:]
        var folded: Set<UUID> = []
        var seen: Set<String> = []
        for row in model.staged {
            guard let name = row.combinationName,
                  let product = CustomSubstanceStore.shared.combination(named: name) else { continue }
            if seen.insert(name).inserted {
                leads[row.id] = product
            } else {
                folded.insert(row.id)
            }
        }
        return (leads, folded)
    }
}

// MARK: - Commit Bar

/// The tray's shared bottom bar — the warnings, the When/Tags/Location chips
/// and the Log button. Hosted in the dock's bottom `safeAreaBar`, so scroll
/// content can pass beneath it with the soft edge effect.
///
/// At accessibility text sizes the warnings and the chips leave the bar: the
/// pinned bar alone outgrew the compact detent and covered the staged doses,
/// then clipped the Log button — the flow's primary action. The dock renders
/// ``TrayWarningBanner`` and ``TrayMetaChips`` inside the scroll content
/// instead, and only the button stays pinned.
struct TrayCommitBar: View {
    @Bindable var model: DoseTrayModel
    /// Source of the chips' derived caches (tag suggestions, recent
    /// locations). A stable reference on purpose: handing the arrays down as
    /// values re-minted this view's inputs on every dock body pass, which
    /// defeated SwiftUI's view-value diff and re-ran the whole bar + chips
    /// each time (`_printChanges`: `@self changed` on nearly every pass).
    let content: QuickLogContentModel
    let onCommit: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize {
                TrayWarningBanner(model: model, content: content)
                TrayMetaChips(model: model, content: content)
                commitButton
                    .padding(.top, 14)
            } else {
                commitButton
            }
        }
    }

    // MARK: Commit

    private var commitButton: some View {
        Button(action: onCommit) {
            Text(commitLabel)
                .cardTitle()
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(minHeight: DoseTrayMetrics.controlHeight)
                .skinProminentFill(in: skinChipShape())
        }
        .buttonStyle(.plain)
        .disabled(!model.isCommittable)
        .opacity(model.isCommittable ? 1 : 0.5)
    }

    /// The CTA echoes a backdate ("Log 2 · 1h ago") so a stale time can't be
    /// committed blind.
    private var commitLabel: String {
        let base = model.staged.count == 1
            ? String(localized: "Record an entry")
            : String(localized: "Record \(model.staged.count) Entries")
        return model.time.isNow ? base : "\(base) · \(model.time.chipLabel)"
    }
}

// MARK: - Warnings

/// Interactions, the meal's onset delay and the late-dose sleep clause share one
/// element: all are consequences of what the Log button is about to record,
/// stated before it is pressed rather than discovered after.
struct TrayWarningBanner: View {
    let model: DoseTrayModel
    /// Holds the recent dose log the interaction check reads, so a staged dose
    /// is checked against what is already in the body.
    let content: QuickLogContentModel

    @State private var interactions: [InteractionResult] = []
    @State private var sleepWarnings: [SleepWarning] = []

    /// A staged dose whose class holds sleep off and whose modeled effects run
    /// past the hours most people sleep, at the time it is about to be logged.
    struct SleepWarning: Identifiable, Equatable {
        let name: String
        let end: Date

        var id: String {
            name
        }
    }

    var body: some View {
        banner
            .onChange(of: model.staged.map(\.substanceName)) {
                recheckInteractions()
                recheckSleep()
            }
            .onChange(of: model.time) {
                recheckInteractions()
                recheckSleep()
            }
            .onChange(of: content.recentEntriesGeneration) { recheckInteractions() }
            .task {
                recheckInteractions()
                recheckSleep()
            }
    }

    /// The zero-height anchor keeps the view real while there is nothing to
    /// say: `.task` on a view that renders nothing never runs, and the first
    /// check would never fire.
    private var banner: some View {
        let shown = interactions
        let mealLines = TrayMealConsequence.lines(staged: model.staged, meal: model.meal)
        return VStack(spacing: 0) {
            Color.clear.frame(height: 0)
            if !shown.isEmpty || !sleepWarnings.isEmpty || !mealLines.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(Array(shown.prefix(3).enumerated()), id: \.offset) { _, warning in
                        warningRow(
                            symbol: warning.severity == .dangerous
                                ? warning.mechanism.filledIconName : warning.mechanism.iconName,
                            color: warning.severity.labelColor,
                            detail: warning.counterpart?.trayLine,
                        ) {
                            Text(warning.leadClause)
                        }
                    }
                    ForEach(Array(mealLines.enumerated()), id: \.offset) { _, line in
                        TrayMealLineRow(line: line)
                    }
                    // One line however many run late, naming them all against the
                    // latest end, so a morning stack doesn't stack sleep notes.
                    if let latest = sleepWarnings.map(\.end).max() {
                        let names = sleepWarnings.map(\.name).formatted(.list(type: .and))
                        warningRow(symbol: DosePhaseGlyph.sleep, color: Color.Semantic.Caution.text) {
                            Text("\(names) modeled active until ~\(Self.clock(latest))")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, Spacing.lg)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// `detail` is a second, quieter line under the warning — the logged dose
    /// an interaction is with, which the tray has no other way to show.
    private func warningRow(
        symbol: String,
        color: Color,
        detail: String? = nil,
        @ViewBuilder text: () -> Text,
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.caption)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                text()
                    .font(.caption.weight(.medium))
                    .foregroundStyle(color)
                if let detail {
                    Text(verbatim: detail)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// Staged doses against each other and against what is already in the
    /// body at the When chip's time. Recomputed on staging, on the chip, and on
    /// a change to the dose log.
    private func recheckInteractions() {
        interactions = TrayInteractionCheck.warnings(
            staged: model.staged.map(\.substanceName),
            history: content.recentEntries,
            at: model.time.resolved,
        )
    }

    /// The staged doses whose effects the model runs into the night. Recomputed
    /// on staging and on the When chip, because the answer is a function of the
    /// clock the dose is being filed at, not of when the dock was opened.
    private func recheckSleep() {
        let time = model.time.resolved
        sleepWarnings = model.staged.compactMap { dose in
            guard let end = MedTimeConsequence.nightEnd(
                substance: dose.librarySubstance,
                route: dose.route,
                at: time,
            ) else { return nil }
            return SleepWarning(name: dose.productName ?? dose.substanceName, end: end)
        }
    }
}

// MARK: - Tags Popover

/// The tags chip's anchored popover: the suggestion + selected tag chips as
/// toggles. Reads/writes the model directly; dismisses on outside taps like
/// any popover.
struct TrayTagsPopover: View {
    @Bindable var model: DoseTrayModel
    let tagSuggestions: [String]

    private var allTagChoices: [String] {
        tagSuggestions + model.tags.filter { !tagSuggestions.contains($0) }.sorted()
    }

    var body: some View {
        FlowLayout(spacing: Spacing.sm) {
            ForEach(allTagChoices, id: \.self) { tag in
                let on = model.tags.contains(tag)
                Button {
                    withAnimation(.snappy) {
                        if on { model.tags.remove(tag) } else { model.tags.insert(tag) }
                    }
                } label: {
                    Text(verbatim: "#\(tag)")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 11)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.platformSecondarySystemFill),
                            in: Capsule(),
                        )
                        .foregroundStyle(on ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 280)
        .padding(14)
    }
}

// MARK: - Swipe Row

/// Swipe-to-delete container for one staged row — collapsed or expanded, the
/// same leftward swipe reveals the delete capsule (full swipe removes). The
/// content stays fully interactive at rest; while the delete strip is
/// revealed, the first tap anywhere on the row closes it again.
/// The long-press actions on a collapsed staged dose: open it, or remove it —
/// the same Remove the swipe reveals.
struct TrayRowContextMenu: View {
    let model: DoseTrayModel
    let item: StagedDose

    var body: some View {
        Button {
            withAnimation(.snappy) { _ = model.expandedItemIDs.insert(item.id) }
        } label: {
            Label("Edit", systemImage: "slider.horizontal.3")
        }
        Button(role: .destructive) {
            withAnimation(.snappy) { model.remove(item) }
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }
}

struct TraySwipeRow<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0

    private static var revealWidth: CGFloat {
        64
    }
    private static var fullSwipeThreshold: CGFloat {
        180
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteBackdrop
            content
                // The row's own surface slides with it, and it turns visible
                // (a gray rounded surface, like the row capsule Reminders
                // shows mid-swipe) so the *background* reads as moving — on
                // the white card a white surface sliding is invisible.
                .background {
                    RoundedRectangle(cornerRadius: DoseTrayMetrics.cardCornerRadius, style: .continuous)
                        .fill(Color.platformSecondarySystemFill)
                        .opacity(offset < -1 ? 1 : 0)
                }
                .offset(x: offset)
                .overlay {
                    if offset != 0 {
                        // Tap-catcher while revealed — swallows the tap that
                        // would otherwise expand/edit and closes the strip.
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.snappy) { offset = 0 }
                            }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel(Text("Dismiss"))
                    }
                }
                // The swipe gesture is invisible to assistive tech — expose
                // deletion as a rotor action on the row itself.
                .accessibilityAction(named: Text("Remove")) {
                    onDelete()
                }
        }
        .clipped()
        #if os(iOS)
            // A UIKit pan that begins only on a sideways drag: a SwiftUI
            // DragGesture claimed vertical drags too, so a tall staged stack
            // couldn't be scrolled from its rows.
            .gesture(HorizontalSwipePan(onChanged: swipeChanged, onEnded: swipeEnded))
        #else
            .gesture(swipeGesture)
        #endif
    }

    /// The revealed action: a compact red capsule pill, vertically centered —
    /// the iOS 26 swipe-action button (see Reminders), not a full-height fill.
    private var deleteBackdrop: some View {
        Button {
            onDelete()
        } label: {
            Capsule()
                .fill(.red)
                .overlay {
                    Image(systemName: "trash.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
                .frame(width: Self.revealWidth - 8, height: 44)
        }
        .buttonStyle(.plain)
        .frame(maxHeight: .infinity, alignment: .center)
        .padding(.trailing, Spacing.md)
        .accessibilityLabel("Remove")
        .opacity(offset < -1 ? 1 : 0)
        // Hidden until the swipe reveals it — otherwise VoiceOver stops on an
        // invisible button behind every row.
        .accessibilityHidden(offset >= -1)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                swipeChanged(value.translation.width)
            }
            .onEnded { value in
                swipeSettled(projected: value.predictedEndTranslation.width)
            }
    }

    private func swipeChanged(_ translation: CGFloat) {
        offset = min(0, translation)
    }

    /// `velocity` in points per second; a quarter second of it approximates
    /// SwiftUI's predicted end translation.
    private func swipeEnded(_ translation: CGFloat, _ velocity: CGFloat) {
        swipeSettled(projected: translation + velocity * 0.25)
    }

    private func swipeSettled(projected: CGFloat) {
        if offset < -Self.fullSwipeThreshold || projected < -Self.fullSwipeThreshold * 1.5 {
            onDelete()
        } else if offset < -Self.revealWidth / 2 {
            withAnimation(.snappy) { offset = -Self.revealWidth }
        } else {
            withAnimation(.snappy) { offset = 0 }
        }
    }
}

// MARK: - Tray Row

/// A staged dose as a compact row: a downward disclosure chevron (it expands
/// in place — never navigates) — tap expands the inline editor; the enclosing
/// ``TraySwipeRow`` owns swipe-to-delete.
struct TrayRow: View {
    let dose: StagedDose
    /// Stable reference, not parent closures: the row toggles its own
    /// expansion / removal through the model. With no closures and an
    /// `Equatable` `dose`, SwiftUI can compare `TrayRow` and skip the body of
    /// a collapsed row whose dose didn't change — so editing one staged
    /// amount no longer re-evaluates every other row.
    let model: DoseTrayModel
    let namespace: Namespace.ID

    private func expand() {
        withAnimation(.snappy) { model.openForEditing(dose.id) }
    }

    var body: some View {
        // Session-row grammar (Specs/meds-ux-review.md §6): identity leading,
        // the *numbers* on the trailing edge — ROA as a pill, the amount bold
        // and large — with the disclosure chevron at the far trailing edge
        // where every system disclosure puts it.
        HStack(spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: 3) {
                Text(dose.displayTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .trayMorph(id: "title-\(dose.id)", in: namespace)
                // Secondary context under the title: dose level (read via
                // color), component breakdown, note.
                HStack(spacing: 5) {
                    // No level for a zero amount — "0 g · sub-threshold" reads
                    // like a valid dose; the trailing warning marks it instead.
                    if dose.totalAmount > 0, let level = dose.doseLevel {
                        Text(level.displayName)
                            .textCase(.lowercase)
                            .foregroundStyle(level.labelColor)
                    }
                    if let breakdown = dose.breakdownLabel {
                        if dose.totalAmount > 0, dose.doseLevel != nil {
                            Middot().foregroundStyle(.tertiary)
                        }
                        Text(verbatim: breakdown)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    if !dose.note.isEmpty {
                        if (dose.totalAmount > 0 && dose.doseLevel != nil) || dose.breakdownLabel != nil {
                            Middot().foregroundStyle(.tertiary)
                        }
                        Text(dose.note)
                            .foregroundStyle(Theme.secondaryLabel)
                            .lineLimit(1)
                    }
                }
                .font(.subheadline)
            }
            Spacer(minLength: 8)
            // A zero-amount dose blocks the Log button — flag it on the row,
            // otherwise the disabled button gives no clue which dose is why.
            if dose.totalAmount <= 0, !dose.isUnknownAmount {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.cautionAccent)
                    .accessibilityLabel("Needs an amount")
            }
            ROAPill(route: dose.route)
                // Same squeeze as the amount text below: mid-morph the matched
                // siblings carry inflated frames that clip "sublingual" into
                // "subling…". Pin it to its intrinsic width for the animation.
                .fixedSize()
                .trayMorph(id: "route-\(dose.id)", in: namespace)
            Text(verbatim: dose.isUnknownAmount
                ? "? \(dose.unit)"
                : "\(dose.totalAmount.doseFormatted) \(dose.unit.unitDisplay(for: dose.totalAmount))")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityLabel(dose.isUnknownAmount ? Text("unknown amount") : Text(verbatim: "\(dose.totalAmount.doseFormatted) \(dose.unit.unitDisplay(for: dose.totalAmount))"))
                // During the collapse morph the matched siblings carry
                // inflated mid-flight frames, squeezing this text into a
                // momentary "37.…" ellipsis. Fixed-size keeps it at its
                // intrinsic width for the whole animation.
                .fixedSize()
                .trayMorph(id: "amount-\(dose.id)", in: namespace)
            // Points right collapsed, down expanded (the editor renders the
            // same glyph rotated 90°; the matched-geometry swap reads as a
            // rotation in place).
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.tertiaryLabel)
                .frame(width: 16)
                .trayMorph(id: "chevron-\(dose.id)", in: namespace)
        }
        .padding(.vertical, Spacing.xl)
        .contentShape(Rectangle())
        .onTapGesture(perform: expand)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Expands the editor")
    }
}
