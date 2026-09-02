import SwiftData
import SwiftUI
import TipKit

/// The Journal's `•••` toolbar button: a Mail-style options popover carrying the
/// grouping thumbnail picker plus Jump to Date and the app-level Settings/Help
/// (folded in from the removed ``AppOverflowMenu`` so the toolbar stays at two
/// controls). A popover rather than a `Menu` because a menu can't host the
/// custom thumbnail views — same pattern as the Tolerance screen's options menu.
struct JournalOptionsButton: View {
    @Environment(\.appNavigator) private var navigator
    @Binding var grouping: JournalGrouping
    @Binding var groupKey: JournalGroupKey
    let onJumpToDate: () -> Void

    @State private var showsOptions = false
    @State private var pendingAction: JournalMenuAction?

    var body: some View {
        Button {
            showsOptions = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
        }
        .accessibilityLabel(Text("More"))
        .popover(isPresented: $showsOptions) {
            JournalOptionsMenu(grouping: $grouping, groupKey: $groupKey) { action in
                pendingAction = action
                showsOptions = false
            }
            .presentationCompactAdaptation(.popover)
        }
        // The "your data lives here" tip points at Settings — it anchored to the
        // Journal's overflow menu before the toolbar consolidation, so it lives
        // on this button now (Journal is the landing tab; other tabs never
        // surfaced it).
        .popoverTip(SettingsDataTip(), arrowEdge: .top)
        .onChange(of: showsOptions) {
            guard !showsOptions, let action = pendingAction else { return }
            pendingAction = nil
            // Let the popover's dismissal settle before presenting a sheet — an
            // immediate present races the teardown (the root is still
            // "presenting" the popover) and gets dropped by UIKit.
            Task {
                try? await Task.sleep(for: UITiming.presentationTeardown)
                switch action {
                case .jumpToDate: onJumpToDate()
                case .myMeds: navigator.push(.myMeds)
                case .settings: present(.settings)
                case .help: present(.help)
                }
            }
        }
    }

    private func present(_ route: SheetRoute) {
        guard navigator.sheetStack.isEmpty else { return }
        navigator.present(route)
    }
}

/// The options popover content, modeled on Mail's view-options menu: the
/// grouping thumbnail picker across the top (three line-art phones with a radio
/// each, plus the Grouped key as a segmented control beneath while Grouped is
/// selected), then Jump to Date, then the app-level Settings/Help. Picking a
/// grouping keeps the popover open (Mail's behavior — the list re-buckets
/// behind it); the action rows dismiss.
struct JournalOptionsMenu: View {
    @Binding var grouping: JournalGrouping
    @Binding var groupKey: JournalGroupKey
    let onAction: (JournalMenuAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(JournalGrouping.allCases, id: \.self) { option in
                    groupingColumn(option)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 12)

            if grouping == .grouped {
                Picker("Group by", selection: $groupKey) {
                    ForEach(JournalGroupKey.allCases, id: \.self) { key in
                        Text(key.displayName).tag(key)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }

            Divider()

            VStack(spacing: 0) {
                actionRow(.jumpToDate, title: Text("Jump to Date"), systemImage: "calendar")
                // The Journal's standing door to My Meds: the MyMedsCard only
                // exists once meds do, so before the first med this row is the
                // only way in from the Journal.
                actionRow(.myMeds, title: Text("My Meds"), systemImage: "pills")
            }

            Divider()

            VStack(spacing: 0) {
                actionRow(.settings, title: Text("Settings"), systemImage: "gearshape")
                actionRow(.help, title: Text("Help"), systemImage: "lifepreserver")
            }
            .padding(.bottom, 8)
        }
        .frame(width: 320)
    }

    private func groupingColumn(_ option: JournalGrouping) -> some View {
        let selected = grouping == option
        return Button {
            grouping = option
        } label: {
            VStack(spacing: 7) {
                MenuPhoneThumbnail(selected: selected, sketch: JournalGroupingArt.sketch(for: option))
                    .frame(width: 52, height: 107) // aspect 0.486 — the iPhone 17 bezel
                Text(option.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.primary)
                radio(selected: selected)
                    .frame(width: 18, height: 18)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(option.displayName))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func radio(selected: Bool) -> some View {
        ZStack {
            if selected {
                Circle().fill(Theme.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            } else {
                Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.5)
            }
        }
    }

    private func actionRow(_ action: JournalMenuAction, title: Text, systemImage: String) -> some View {
        Button {
            onAction(action)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                title
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.leading, 28)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The Journal's third toolbar control, present only while the Timeline
/// grouping is selected: the strip's display options (``TimelineOptionsMenu``)
/// behind a sliders glyph, so they stay reachable however far the canvas has
/// scrolled. The bindings are the Journal's app-group defaults, shared with
/// the pushed timeline screen's copy of the same menu.
struct JournalTimelineOptionsButton: View {
    @Binding var zoom: Double
    @Binding var compressGaps: Bool
    @Binding var pkCurves: Bool
    @Binding var strengthScaling: Bool
    @Binding var showsAxis: Bool
    @Binding var bubbleStyle: TimelineBubbleStyle

    var body: some View {
        TimelineOptionsMenu(
            zoom: $zoom,
            compressGaps: $compressGaps,
            pkCurves: $pkCurves,
            strengthScaling: $strengthScaling,
            showsAxis: $showsAxis,
            bubbleStyle: $bubbleStyle,
        ) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 17, weight: .semibold))
        }
    }
}

/// The Journal's filter toolbar menu — the single home for narrowing the list.
/// Reads the model's available facet values (only what's actually present in
/// the journal) and toggles the parent's filter sets through the bindings (the
/// parent's `onChange(of:)` drives the regroup + Day-window reset). Tags and
/// categories are multi-select checkmark sections; routes live one level down
/// so the top level stays short.
struct JournalFilterMenu: View {
    let model: JournalModel
    @Binding var filterTags: Set<String>
    @Binding var filterCategories: Set<SubstanceCategory>
    @Binding var filterRoutes: Set<RouteOfAdministration>

    private var hasActiveFilters: Bool {
        !filterTags.isEmpty || !filterCategories.isEmpty || !filterRoutes.isEmpty
    }

    /// Spoken filter state — the active/inactive cue is otherwise tint-only.
    private var filterValue: Text {
        guard hasActiveFilters else { return Text("Off") }
        let parts = filterTags.sorted().map { "#\($0)" }
            + filterCategories.map { String(localized: $0.displayName) }.sorted()
            + filterRoutes.map { String(localized: $0.localizedName) }.sorted()
        return Text(verbatim: parts.joined(separator: ", "))
    }

    var body: some View {
        // Active state: an accent-filled circle nested inside the item's platter,
        // Phone-app style. A prominent `Menu` can't replace the platter the way a
        // prominent `Button` does (it renders via the generic bordered path), and
        // the platter's own tint API isn't public — so the filled circle is sized
        // *down* (regular control size + a small label frame) to sit within the
        // platter ring instead of fighting it.
        if hasActiveFilters {
            Menu {
                menuContent
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
            }
            .menuStyle(.button)
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .controlSize(.regular)
            .tint(Theme.accent)
            .accessibilityLabel(Text("Filter"))
            .accessibilityValue(filterValue)
        } else {
            Menu {
                menuContent
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 17, weight: .semibold))
            }
            .accessibilityLabel(Text("Filter"))
            .accessibilityValue(filterValue)
        }
    }

    /// Shared menu body for both filter button states. Each facet is its own
    /// drill-in submenu (substance type, tags, route of administration) whose
    /// rows are checkmark toggles — the top level stays a short list of facets,
    /// and the label carries a `(count)` badge so an applied filter is visible
    /// without opening the submenu. No time window — the list already shows
    /// every day in order, and the calendar *scrolls* to a day instead.
    @ViewBuilder
    private var menuContent: some View {
        Section {
            if !model.categories.isEmpty {
                Menu {
                    ForEach(model.categories, id: \.self) { category in
                        toggleRow(
                            isOn: filterCategories.contains(category),
                            title: Text(category.displayName),
                            icon: category.icon,
                        ) { toggle(category, in: $filterCategories) }
                    }
                } label: {
                    facetLabel("Category", systemImage: "square.grid.2x2", count: filterCategories.count)
                }
            }

            if !model.tags.isEmpty {
                Menu {
                    ForEach(model.tags, id: \.self) { tag in
                        toggleRow(
                            isOn: filterTags.contains(tag),
                            title: Text(verbatim: "#\(tag)"),
                        ) { toggle(tag, in: $filterTags) }
                    }
                } label: {
                    facetLabel("Tags", systemImage: "number", count: filterTags.count)
                }
            }

            if model.routes.count > 1 {
                Menu {
                    ForEach(model.routes, id: \.self) { route in
                        toggleRow(
                            isOn: filterRoutes.contains(route),
                            title: Text(route.localizedName),
                        ) { toggle(route, in: $filterRoutes) }
                    }
                } label: {
                    facetLabel("Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath", count: filterRoutes.count)
                }
            }
        }

        if hasActiveFilters {
            Section {
                Button("Clear Filters", role: .destructive) {
                    filterTags = []
                    filterCategories = []
                    filterRoutes = []
                }
            }
        }
    }

    /// A submenu's title with a `(count)` suffix once that facet has selections,
    /// so the collapsed top level advertises what's applied. The facet name stays
    /// localized; the numeric suffix is universal.
    private func facetLabel(_ title: LocalizedStringResource, systemImage: String, count: Int) -> some View {
        Label {
            if count > 0 {
                Text(verbatim: "\(String(localized: title)) (\(count))")
            } else {
                Text(title)
            }
        } icon: {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
        }
    }

    /// A checkmark toggle row inside a facet submenu. When `icon` is supplied it
    /// shows in place of the checkmark while unselected (matching the category
    /// rows' glyphs); otherwise the row is glyph-less until checked.
    private func toggleRow(isOn: Bool, title: Text, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                title
            } icon: {
                if isOn {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                } else if let icon {
                    Image(systemName: icon)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func toggle<Value: Hashable>(_ value: Value, in set: Binding<Set<Value>>) {
        if set.wrappedValue.contains(value) {
            set.wrappedValue.remove(value)
        } else {
            set.wrappedValue.insert(value)
        }
    }
}

// MARK: - Substance Entry Row (for substance/category grouping)
