import SwiftData
import SwiftUI
import UIKit

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
        let lastVisibleID = model.staged.last(where: { !hiddenItemIDs.contains($0.id) })?.id
        VStack(spacing: 0) {
            ForEach($model.staged) { $item in
                if !hiddenItemIDs.contains(item.id) {
                    TraySwipeRow(onDelete: { withAnimation(.snappy) { model.remove(item) } }) {
                        // The horizontal inset is applied OUTSIDE the swap, not
                        // inside each branch. Padding that changes across a
                        // matched-geometry morph moves the container's edges on
                        // a different curve from the frame-interpolated pairs
                        // inside it, which is what made the expansion read as a
                        // lurch. The editor's extra vertical breathing room is
                        // its own business and stays on its branch — that one
                        // doesn't fight the morph because no pair spans it.
                        Group {
                            if model.expandedItemIDs.contains(item.id) {
                                StagedDoseEditor(item: $item, namespace: morphNamespace) {
                                    withAnimation(.snappy) { _ = model.expandedItemIDs.remove(item.id) }
                                } onRemove: {
                                    withAnimation(.snappy) { model.remove(item) }
                                }
                                .padding(.vertical, 8)
                            } else {
                                TrayRow(dose: item, model: model, namespace: morphNamespace)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    if item.id != lastVisibleID {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: DoseTrayMetrics.cardCornerRadius, style: .continuous),
        )
    }
}

// MARK: - Commit Bar

/// The tray's shared bottom bar — the When/Tags/Location chips and the Log
/// button. Hosted in the dock's bottom `safeAreaBar`, so scroll content can
/// pass beneath it with the soft edge effect.
///
/// At accessibility text sizes the chips leave the bar: stacked, the pinned
/// bar alone outgrew the compact detent's cap and clipped the Log button —
/// the flow's primary action. The dock renders ``TrayMetaChips`` inside the
/// scroll content instead, and only the button stays pinned.
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
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                // The dock contract: the Log button and the search field
                // share one frame, so the faces morph into one another.
                .frame(height: DoseTrayMetrics.controlHeight)
                .background(Theme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!model.isCommittable)
        .opacity(model.isCommittable ? 1 : 0.5)
    }

    /// The CTA echoes a backdate ("Log 2 · 1h ago") so a stale time can't be
    /// committed blind.
    private var commitLabel: String {
        let base = model.staged.count == 1
            ? String(localized: "Log Dose")
            : String(localized: "Log \(model.staged.count) Doses")
        return model.time.isNow ? base : "\(base) · \(model.time.chipLabel)"
    }
}

// MARK: - Meta Chips

/// The tray-wide When/Tags/Location chips with their anchored presentations.
/// Rendered inside ``TrayCommitBar`` normally; at accessibility sizes the
/// dock hosts them in the scroll content (see ``TrayCommitBar``).
struct TrayMetaChips: View {
    @Bindable var model: DoseTrayModel
    /// Source of the tag suggestions and recent locations. A stable reference
    /// — and this body reads its caches only inside the popover/menu/sheet
    /// closures, which resolve at presentation time — so neither a dock body
    /// pass nor a cache rebuild re-renders the chips at all.
    let content: QuickLogContentModel

    /// The user's configured "When" presets (minutes), edited in Settings › Journal.
    @AppStorage(DoseTimeDefaults.choicesKey, store: UserDefaults(suiteName: DoseTimeDefaults.suite))
    private var doseTimeChoicesRaw = DoseTimeDefaults.defaultRaw

    @State private var showLocationPicker = false
    /// Anchored presentations off the chips — Apple's idiom for quick options
    /// (menus/popovers) instead of the old inline floating panels.
    @State private var showTagsPopover = false
    @State private var showDatePopover = false
    @State private var showLocationDeniedAlert = false
    /// Owns current-location requests for the location menu; the chip shows a
    /// spinner while a request is in flight.
    @State private var locationModel = LocationSearchModel()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Chips side by side normally; stacked at accessibility sizes, where
    /// three capsules can't share the row — squeezed, their labels wrapped
    /// character-per-line into vertical columns.
    private var chipLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    var body: some View {
        chipLayout {
            whenChip
            tagsChip
            locationChip
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sensoryFeedback(.selection, trigger: model.time)
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView(recents: content.cachedRecentLocations) { picked in
                model.location = picked
            }
        }
        .alert("Location access is off", isPresented: $showLocationDeniedAlert) {
            Button("Open Settings") {
                // UIApplication directly, not `@Environment(\.openURL)`: the
                // environment's action wrapper compares as changed on every
                // parent pass, so reading it re-rendered these chips whenever
                // the dock body ran (`_printChanges`: `_openURL changed`).
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Turn on location access in Settings to use your current location.")
        }
    }

    // MARK: Shared controls

    /// The visible chip is plain SwiftUI with the Menu overlaid as an invisible
    /// tap target. As a `Menu` *label* the chip's width was sized by the
    /// UIKit-backed menu button, which applies the new size outside the SwiftUI
    /// transaction — the color crossfaded at the old width, then the frame
    /// snapped. Decoupled, the whole chip animates in one `.snappy` pass.
    private var whenChip: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock")
                .imageScale(.small)
            Text(model.time.chipLabel)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
        }
        .font(.subheadline.weight(.semibold))
        // Pin the label to its ideal width so the new string isn't clipped to
        // the interpolating frame (which flashed truncated text mid-animation).
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            model.time.isNow ? AnyShapeStyle(Color(.secondarySystemFill)) : AnyShapeStyle(Color.orange.opacity(0.18)),
            in: Capsule(),
        )
        .foregroundStyle(model.time.isNow ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.orange))
        .animation(.snappy, value: model.time)
        // The overlay Menu is the accessible element — expose only it, or
        // VoiceOver stops on the decorative chip content too.
        .accessibilityHidden(true)
        .overlay {
            Menu {
                whenMenuItems
            } label: {
                Color.clear.contentShape(Capsule())
            }
            .accessibilityLabel(Text("Dose time: \(model.time.chipLabel)"))
        }
        .popover(isPresented: $showDatePopover, arrowEdge: .bottom) {
            DatePicker(
                "When",
                selection: Binding(
                    get: {
                        if case let .custom(date) = model.time { date } else { model.time.resolved }
                    },
                    set: { model.time = .custom($0) },
                ),
                in: ...Date.now,
            )
            .datePickerStyle(.graphical)
            .frame(width: 320)
            .padding(12)
            .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder
    private var whenMenuItems: some View {
        Button {
            withAnimation(.snappy) { model.time = .now }
        } label: {
            if model.time.isNow {
                Label("Now", systemImage: "checkmark")
            } else {
                Text("Now")
            }
        }
        ForEach(DoseTimeDefaults.parse(doseTimeChoicesRaw), id: \.self) { minutes in
            Button {
                withAnimation(.snappy) { model.time = .offset(minutes: minutes) }
            } label: {
                if model.time == .offset(minutes: minutes) {
                    Label(TrayTime.offsetLabel(minutes: minutes), systemImage: "checkmark")
                } else {
                    Text(TrayTime.offsetLabel(minutes: minutes))
                }
            }
        }
        Button {
            withAnimation(.snappy) { model.time = .custom(model.time.resolved) }
            // Presenting while the menu is still tearing down races UIKit's
            // presentation slot — defer one runloop turn.
            Task { @MainActor in showDatePopover = true }
        } label: {
            Label("Pick date & time…", systemImage: "calendar")
        }
    }

    /// Tag toggles live in an anchored popover (Apple's quick-options idiom),
    /// not an inline panel that reflows the whole bar.
    private var tagsChip: some View {
        Button {
            showTagsPopover = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "tag")
                    .imageScale(.small)
                if model.tags.isEmpty {
                    Text("Tags")
                        .lineLimit(1)
                } else {
                    Text(verbatim: "\(model.tags.count)")
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                model.tags.isEmpty ? AnyShapeStyle(Color(.secondarySystemFill)) : AnyShapeStyle(Theme.accent.opacity(0.15)),
                in: Capsule(),
            )
            .foregroundStyle(model.tags.isEmpty ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.accent))
        }
        .buttonStyle(.plain)
        // Otherwise once tags exist the chip reads as a bare number with no
        // "Tags" word; keep the noun as the label and put the count in a value.
        .accessibilityLabel("Tags")
        .accessibilityValue(model.tags.isEmpty ? Text("None") : Text("^[\(model.tags.count) tag](inflect: true)"))
        .popover(isPresented: $showTagsPopover, arrowEdge: .bottom) {
            TrayTagsPopover(model: model, tagSuggestions: content.cachedTagSuggestions)
                .presentationCompactAdaptation(.popover)
        }
    }

    /// A native Menu — current location, recent places, the full search, and
    /// remove — with the same decoupled chip visual as the when chip (the
    /// label resizes when a place is picked).
    private var locationChip: some View {
        HStack(spacing: 5) {
            if locationModel.isLocating {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: model.location == nil ? "mappin.and.ellipse" : "mappin.circle.fill")
                    .imageScale(.small)
            }
            if let location = model.location {
                Text(location.name)
                    .lineLimit(1)
            } else {
                Text("Location")
                    .lineLimit(1)
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            model.location == nil ? AnyShapeStyle(Color(.secondarySystemFill)) : AnyShapeStyle(Theme.accent.opacity(0.15)),
            in: Capsule(),
        )
        .foregroundStyle(model.location == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.accent))
        .frame(maxWidth: 180, alignment: .leading)
        .animation(.snappy, value: model.location)
        // The overlay Menu is the accessible element — expose only it, or
        // VoiceOver stops on the decorative chip content too.
        .accessibilityHidden(true)
        .overlay(alignment: .leading) {
            Menu {
                locationMenuItems
            } label: {
                Color.clear.contentShape(Capsule())
            }
            .accessibilityLabel(model.location.map { Text("Location: \($0.name)") } ?? Text("Location"))
        }
    }

    @ViewBuilder
    private var locationMenuItems: some View {
        Button {
            Task {
                guard let picked = await locationModel.requestCurrentLocation() else {
                    if locationModel.authDenied { showLocationDeniedAlert = true }
                    return
                }
                withAnimation(.snappy) { model.location = picked }
            }
        } label: {
            Label("Current Location", systemImage: "location.fill")
        }
        ForEach(Array(content.cachedRecentLocations.prefix(3)), id: \.name) { place in
            Button {
                withAnimation(.snappy) { model.location = place }
            } label: {
                if model.location == place {
                    Label(place.name, systemImage: "checkmark")
                } else {
                    Label(place.name, systemImage: "mappin.circle.fill")
                }
            }
        }
        Button {
            showLocationPicker = true
        } label: {
            Label("Find a Place…", systemImage: "magnifyingglass")
        }
        if model.location != nil {
            Divider()
            Button(role: .destructive) {
                withAnimation(.snappy) { model.location = nil }
            } label: {
                Label("Remove location", systemImage: "xmark")
            }
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
        FlowLayout(spacing: 6) {
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
                        .padding(.vertical, 6)
                        .background(
                            on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color(.secondarySystemFill)),
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
                        .fill(Color(.secondarySystemFill))
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
                    }
                }
                // The swipe gesture is invisible to assistive tech — expose
                // deletion as a rotor action on the row itself.
                .accessibilityAction(named: Text("Remove")) {
                    onDelete()
                }
        }
        .clipped()
        .gesture(swipeGesture)
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
        .padding(.trailing, 8)
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
                offset = min(0, value.translation.width)
            }
            .onEnded { value in
                if offset < -Self.fullSwipeThreshold || value.predictedEndTranslation.width < -Self.fullSwipeThreshold * 1.5 {
                    onDelete()
                } else if offset < -Self.revealWidth / 2 {
                    withAnimation(.snappy) { offset = -Self.revealWidth }
                } else {
                    withAnimation(.snappy) { offset = 0 }
                }
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
        withAnimation(.snappy) { _ = model.expandedItemIDs.insert(dose.id) }
    }

    var body: some View {
        // Session-row grammar (Specs/meds-ux-review.md §6): identity leading,
        // the *numbers* on the trailing edge — ROA as a pill, the amount bold
        // and large — with the disclosure chevron at the far trailing edge
        // where every system disclosure puts it.
        HStack(spacing: 12) {
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
            if dose.totalAmount <= 0 {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Needs an amount")
            }
            ROAPill(route: dose.route)
                // Same squeeze as the amount text below: mid-morph the matched
                // siblings carry inflated frames that clip "sublingual" into
                // "subling…". Pin it to its intrinsic width for the animation.
                .fixedSize()
                .trayMorph(id: "route-\(dose.id)", in: namespace)
            Text(verbatim: "\(dose.totalAmount.doseFormatted) \(dose.unit.unitDisplay(for: dose.totalAmount))")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
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
                .foregroundStyle(.tertiary)
                .frame(width: 16)
                .trayMorph(id: "chevron-\(dose.id)", in: namespace)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: expand)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Expands the editor")
    }
}
