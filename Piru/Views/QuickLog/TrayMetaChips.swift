import SwiftUI

// MARK: - Meta Chips

/// The tray-wide chips, ordered by how often they're used: When, Food (only while an
/// oral dose is staged — the stomach is where an oral dose waits), Location, and
/// Tags as a trailing icon. Rendered inside ``TrayCommitBar`` normally; at
/// accessibility sizes the dock hosts them in the scroll content, stacked.
///
/// An unset chip names its category ("Food", "Location"); a set one shows its
/// value, tinted. When the row can't hold every label, labels drop one step at a
/// time (``TrayChipFit``) rather than the row squeezing or wrapping.
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
    @State private var showTagsPopover = false
    @State private var showDatePopover = false
    @State private var showLocationDeniedAlert = false
    /// Owns current-location requests for the location menu; the chip shows a
    /// spinner while a request is in flight.
    @State private var locationModel = LocationSearchModel()
    @State private var fit = TrayChipFit()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var showsMeal: Bool {
        model.staged.contains { $0.route == .oral }
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    whenChip
                    if showsMeal { TrayMealChip(model: model, showsLabel: true) }
                    locationChip(showsLabel: true)
                    tagsChip
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                row
            }
        }
        .sensoryFeedback(.selection, trigger: model.time)
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView(recents: content.cachedRecentLocations) { picked in
                model.location = picked
            }
        }
        .alert("Location access is off", isPresented: $showLocationDeniedAlert) {
            Button("Open Settings") {
                openPlatformSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Turn on location access in Settings to use your current location.")
        }
    }

    private var row: some View {
        let tier = fit.tier(showsMeal: showsMeal, mealSet: model.meal != nil, locationSet: model.location != nil)
        return HStack(spacing: Spacing.md) {
            whenChip
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { fit.when = $0 }
            if showsMeal {
                TrayMealChip(model: model, showsLabel: TrayChipFit.mealShowsLabel(tier: tier, isSet: model.meal != nil))
            }
            locationChip(showsLabel: TrayChipFit.locationShowsLabel(tier: tier, isSet: model.location != nil))
            Spacer(minLength: 0)
            tagsChip
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { fit.tags = $0 }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { fit.available = $0 }
        .background { measuringFaces }
    }

    /// Each collapsible chip in both of its forms, laid out and never shown, so
    /// the tier is chosen from real widths in the current language and text size.
    private var measuringFaces: some View {
        ZStack {
            TrayChipFace(systemImage: model.meal?.systemImage ?? "fork.knife", title: model.meal?.chipLabel ?? String(localized: "Food"), isSet: model.meal != nil)
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { fit.mealLabeled = $0 }
            TrayChipFace(systemImage: "fork.knife", title: nil, isSet: false)
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { fit.mealIcon = $0 }
            TrayChipFace(systemImage: "mappin.and.ellipse", title: model.location?.name ?? String(localized: "Location"), isSet: model.location != nil)
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { fit.locationLabeled = $0 }
            TrayChipFace(systemImage: "mappin.and.ellipse", title: nil, isSet: false)
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { fit.locationIcon = $0 }
        }
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: When

    /// The visible chip is plain SwiftUI with the Menu overlaid as an invisible
    /// tap target. Never make the chip a `Menu` label: the UIKit-backed menu
    /// button applies its width outside the SwiftUI transaction, so the color
    /// crossfades at the old width and then the frame snaps. Decoupled, the
    /// whole chip animates in one `.snappy` pass.
    private var whenChip: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock")
                .imageScale(.small)
            Text(model.time.chipLabel)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
        }
        .sectionLabel()
        // Pin the label to its ideal width so the new string isn't clipped to
        // the interpolating frame (which flashed truncated text mid-animation).
        .fixedSize()
        .padding(.horizontal, 14)
        .padding(.vertical, Spacing.lg)
        .background(
            model.time.isNow
                ? AnyShapeStyle(Color.platformSecondarySystemFill)
                : AnyShapeStyle(Color.cautionAccent.opacity(Theme.Opacity.tintActive)),
            in: Capsule(),
        )
        .foregroundStyle(model.time.isNow ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.cautionText))
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
            .menuOrder(.fixed)
            .accessibilityLabel(Text("Dose time: \(model.time.chipLabel)"))
            .accessibilityInputLabels([Text("Dose time"), Text("Time")])
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
            )
            .datePickerStyle(.graphical)
            .frame(width: 320)
            .padding(Spacing.xl)
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

    // MARK: Tags

    /// The least-used chip, so an icon at the trailing edge, badged with the count
    /// once tags are set. Toggles live in an anchored popover.
    private var tagsChip: some View {
        Button {
            showTagsPopover = true
        } label: {
            TrayChipFace(systemImage: "tag", title: nil, isSet: !model.tags.isEmpty)
                .overlay(alignment: .topTrailing) {
                    if !model.tags.isEmpty {
                        Text(verbatim: "\(model.tags.count)")
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(Theme.accent, in: Capsule())
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tags")
        .accessibilityValue(model.tags.isEmpty ? Text("None") : Text("^[\(model.tags.count) tag](inflect: true)"))
        .popover(isPresented: $showTagsPopover, arrowEdge: .bottom) {
            TrayTagsPopover(model: model, tagSuggestions: content.cachedTagSuggestions)
                .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: Location

    /// A native Menu — current location, recent places, the full search, and
    /// remove — over the same decoupled chip face as the when chip.
    private func locationChip(showsLabel: Bool) -> some View {
        TrayChipFace(
            systemImage: model.location == nil ? "mappin.and.ellipse" : "mappin.circle.fill",
            title: showsLabel ? (model.location?.name ?? String(localized: "Location")) : nil,
            isSet: model.location != nil,
            isBusy: locationModel.isLocating,
        )
        .animation(.snappy, value: model.location)
        .accessibilityHidden(true)
        .overlay {
            Menu {
                locationMenuItems
            } label: {
                Color.clear.contentShape(Capsule())
            }
            .menuOrder(.fixed)
            .accessibilityLabel(model.location.map { Text("Location: \($0.name)") } ?? Text("Location"))
            .accessibilityInputLabels([Text("Location")])
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

// MARK: - Chip face

/// The capsule every collapsible meta chip draws: an icon, and a title unless the
/// row has collapsed it. Tinted once set. Shared by the visible chips and their
/// hidden measuring copies, so the two can't disagree about width.
struct TrayChipFace: View {
    let systemImage: String
    /// `nil` draws the icon alone.
    let title: String?
    let isSet: Bool
    var isBusy = false

    var body: some View {
        HStack(spacing: 5) {
            if isBusy {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            if let title {
                CappedWidthLayout(maxWidth: TrayChipFit.titleMaxWidth) {
                    Text(title)
                        .lineLimit(1)
                }
            }
        }
        .sectionLabel()
        .padding(.horizontal, 14)
        .padding(.vertical, Spacing.lg)
        .background(
            isSet ? AnyShapeStyle(Theme.accent.opacity(Theme.Opacity.tint)) : AnyShapeStyle(Color.platformSecondarySystemFill),
            in: Capsule(),
        )
        .foregroundStyle(isSet ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))
    }
}

/// Sizes its one child to its ideal width, capped: a long place name truncates at
/// the cap, and a short title takes only what it needs. A `.frame(maxWidth:)` would
/// grow to the cap whenever the row has spare width to offer.
struct CappedWidthLayout: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let width = min(child.sizeThatFits(.unspecified).width, maxWidth, proposal.width ?? .infinity)
        let size = child.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
        return CGSize(width: width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

// MARK: - Fit

/// Which chip titles the row can afford, measured rather than guessed so it holds
/// in every language and text size. Tiers, each dropping one more set of titles:
/// 0 every title; 1 an unset Location's (the longest category word); 2 every unset
/// chip's; 3 every collapsible chip's. When never collapses: the time is the one
/// value the dock is always asked.
struct TrayChipFit: Equatable {
    static let titleMaxWidth: CGFloat = 140

    var available: CGFloat = 0
    var when: CGFloat = 0
    var tags: CGFloat = 0
    var mealLabeled: CGFloat = 0
    var mealIcon: CGFloat = 0
    var locationLabeled: CGFloat = 0
    var locationIcon: CGFloat = 0

    static func mealShowsLabel(tier: Int, isSet: Bool) -> Bool {
        tier <= 1 || (isSet && tier < 3)
    }

    static func locationShowsLabel(tier: Int, isSet: Bool) -> Bool {
        tier == 0 || (isSet && tier < 3)
    }

    /// The first tier whose row fits; tier 0 until the row has been measured.
    func tier(showsMeal: Bool, mealSet: Bool, locationSet: Bool) -> Int {
        guard available > 0 else { return 0 }
        for tier in 0 ... 2 where width(tier: tier, showsMeal: showsMeal, mealSet: mealSet, locationSet: locationSet) <= available {
            return tier
        }
        return 3
    }

    func width(tier: Int, showsMeal: Bool, mealSet: Bool, locationSet: Bool) -> CGFloat {
        var chips = [when, tags]
        if showsMeal {
            chips.append(Self.mealShowsLabel(tier: tier, isSet: mealSet) ? mealLabeled : mealIcon)
        }
        chips.append(Self.locationShowsLabel(tier: tier, isSet: locationSet) ? locationLabeled : locationIcon)
        return chips.reduce(0, +) + Spacing.md * CGFloat(chips.count - 1)
    }
}
