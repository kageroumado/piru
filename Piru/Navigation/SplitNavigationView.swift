import SwiftUI

/// A tab's navigation: an opened record sits beside the list it came from when the
/// window has room for both, and the split collapses to one stack when it does not.
/// One container at every width, so resizing never rebuilds the screens inside it.
/// On a platform with no split view this is the tab's plain stack.
struct SplitNavigationView<Root: View>: View {
    @Environment(\.appNavigator) private var navigator
    let tab: TabID
    @ViewBuilder let root: Root

    var body: some View {
        #if os(iOS) || os(macOS)
            AdaptiveSplitNavigation(tab: tab, root: root)
        #else
            NavigationStack(path: navigator.pathBinding(for: tab)) {
                root
                    .withAppDestinations()
            }
        #endif
    }
}

extension EnvironmentValues {
    /// True in the list column of a split tab, where opening a record shows it beside the list.
    @Entry var opensRecordsBesideList = false
    /// The record open beside the list, for the list to mark.
    @Entry var selectedRecord: PushRoute?
}

extension PushRoute {
    /// Whether this route is a record that opens beside the list, or one more level of the list itself.
    nonisolated var opensBesideList: Bool {
        switch self {
        case .libraryCategory, .libraryTag, .libraryFavorites, .libraryCustom, .drugClassGroup, .insightGroup:
            false
        case .session, .entry, .comedownGuide, .timeline, .substance, .libraryUnits, .libraryColors, .tool,
             .dataStorage, .drugClass, .insight, .myMeds, .medDetail, .inventoryItem, .substanceData:
            true
        }
    }
}

/// A tab's path cut at its first record: the list column shows the levels before
/// it, the detail column the record and whatever was pushed from it.
nonisolated struct SplitPath: Equatable {
    let list: [PushRoute]
    let detail: [PushRoute]

    init(_ path: [PushRoute]) {
        let cut = path.firstIndex(where: \.opensBesideList) ?? path.endIndex
        list = Array(path[..<cut])
        detail = Array(path[cut...])
    }

    var record: PushRoute? {
        detail.first
    }

    /// The path once the list column's own stack reads `newList`. A record pushed
    /// there replaces the open one; a list level pushed or popped keeps it.
    func listChanged(to newList: [PushRoute]) -> [PushRoute] {
        if let cut = newList.firstIndex(where: \.opensBesideList) { return Array(newList[...cut]) }
        return newList + detail
    }

    /// The path once the detail column's stack, above its record, reads `pushed`.
    func detailChanged(to pushed: [PushRoute]) -> [PushRoute] {
        guard let record else { return list }
        return list + [record] + pushed
    }

    /// The path after opening `route` from the list column.
    func opening(_ route: PushRoute) -> [PushRoute] {
        route.opensBesideList ? list + [route] : list + [route] + detail
    }
}

/// A link to a route. In a split tab's list column a record opens beside the list
/// through a button: a `NavigationLink` there pushes inside the list column first,
/// so the record flashes in the sidebar before it moves beside it.
struct RouteLink<Label: View>: View {
    @Environment(\.appNavigator) private var navigator
    @Environment(\.opensRecordsBesideList) private var opensRecordsBesideList
    let route: PushRoute
    /// Draws the disclosure chevron a `NavigationLink` row gets from `List` on its own.
    var disclosure = false
    let label: Label

    init(_ route: PushRoute, disclosure: Bool = false, @ViewBuilder label: () -> Label) {
        self.route = route
        self.disclosure = disclosure
        self.label = label()
    }

    var body: some View {
        if opensRecordsBesideList, route.opensBesideList {
            Button {
                navigator.openRecord(route, besideList: true)
            } label: {
                if disclosure {
                    HStack {
                        label
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(.primary)
                    .contentShape(.rect)
                } else {
                    label
                }
            }
        } else {
            NavigationLink(value: route) { label }
        }
    }
}

/// Wide enough, the list is a sidebar at its minimum width and the record takes the
/// rest; folded, the fold is the boundary. Widths are content minima.
nonisolated struct SplitPaneGeometry: Equatable {
    static let minimumPaneWidth: CGFloat = 360
    static let minimumSplitWidth: CGFloat = 840

    let listWidth: CGFloat
    let showsBoth: Bool

    init(size: CGSize, hasSelection: Bool, division: CGRect? = nil, minimumPaneWidth: CGFloat = Self.minimumPaneWidth) {
        let boundary = division?.minX ?? minimumPaneWidth
        let gap = division?.width ?? 1
        let trailing = size.width - boundary - gap
        showsBoth = hasSelection && size.width >= Self.minimumSplitWidth
            && boundary >= minimumPaneWidth && trailing >= minimumPaneWidth
        listWidth = showsBoth ? boundary : size.width
    }
}

#if os(iOS) || os(macOS)
    /// The geometry the pane split depends on, so layout passes that change nothing else skip the body.
    private nonisolated struct SplitPaneSpace: Equatable {
        var size: CGSize = .zero
        var fold: CGRect?

        #if os(iOS)
            /// The active vertical fold of a partly open device, which the list boundary follows.
            static func fold(in proxy: GeometryProxy) -> CGRect? {
                // Reserved regions exist only in the iOS 27.1 SDK; CI's older Xcode
                // compiles this without them, and its split simply has no fold.
                #if compiler(>=6.4)
                    guard #available(iOS 27.1, *) else { return nil }
                    return proxy.reservedRegions(kind: .division)
                        .first { $0.isActive && $0.frame.height > $0.frame.width }?.frame
                #else
                    return nil
                #endif
            }
        #endif
    }

    private struct AdaptiveSplitNavigation<Root: View>: View {
        @Environment(\.appNavigator) private var navigator
        let tab: TabID
        let root: Root
        /// Which pane a single-pane width shows; `nil` until the person browses or opens something.
        @State private var readingList: Bool?
        @State private var columns: NavigationSplitViewVisibility = .all
        @State private var space = SplitPaneSpace()
        @ScaledMetric(relativeTo: .body) private var minimumPaneWidth = SplitPaneGeometry.minimumPaneWidth

        private var split: SplitPath {
            SplitPath(navigator.path(for: tab))
        }

        var body: some View {
            let split = split
            #if os(iOS)
                let geometry = SplitPaneGeometry(
                    size: space.size,
                    hasSelection: split.record != nil,
                    division: space.fold,
                    minimumPaneWidth: minimumPaneWidth,
                )
                let showsBoth = geometry.showsBoth
                let marksSelection = showsBoth
                let collapsed = !showsBoth
                let listWidth = max(geometry.listWidth, minimumPaneWidth)
                let width = (min: minimumPaneWidth, ideal: listWidth, max: listWidth)
            #else
                // A Mac window always shows both columns; the list is a resizable sidebar,
                // and selecting something else replaces the record, as in Mail or Notes.
                let showsBoth = false
                let marksSelection = true
                let collapsed = false
                let width = (min: 340.0, ideal: minimumPaneWidth, max: 480.0)
            #endif

            NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: Binding(
                get: { (readingList ?? (split.record == nil)) ? .sidebar : .detail },
                set: { readingList = $0 == .sidebar },
            )) {
                list(split, marksSelection: marksSelection)
                    .navigationSplitViewColumnWidth(min: width.min, ideal: width.ideal, max: width.max)
            } detail: {
                detail(split, showsBoth: showsBoth)
            }
            .navigationSplitViewStyle(.balanced)
            #if os(iOS)
                .environment(\.horizontalSizeClass, showsBoth ? .regular : .compact)
                .onGeometryChange(for: SplitPaneSpace.self) { proxy in
                    SplitPaneSpace(size: proxy.size, fold: SplitPaneSpace.fold(in: proxy))
                } action: { space = $0 }
            #endif
                .onChange(of: navigator.recordReopenings[tab]) {
                    guard collapsed else { return readingList = false }
                    // A collapsed split shows its detail only when the record changes, so
                    // the record already open is taken out for a moment and put back.
                    let path = navigator.path(for: tab)
                    navigator.setPath(SplitPath(path).list, in: tab)
                    Task { navigator.setPath(path, in: tab) }
                }
                .confirmationDialog(
                    "Discard your changes?",
                    isPresented: Binding(
                        get: { navigator.pendingRecordChange?.tab == tab },
                        set: { if !$0 { navigator.resolvePendingRecordChange(discard: false) } },
                    ),
                    titleVisibility: .visible,
                ) {
                    Button("Discard Changes", role: .destructive) {
                        navigator.resolvePendingRecordChange(discard: true)
                    }
                    Button("Keep Editing", role: .cancel) {
                        navigator.resolvePendingRecordChange(discard: false)
                    }
                } message: {
                    Text("The entry you are editing has changes that are not saved.")
                }
                .onChange(of: split) { old, new in
                    if new.record == nil {
                        readingList = true
                        columns = .all
                    } else {
                        readingList = new.detail == old.detail
                    }
                }
        }

        private func list(_ split: SplitPath, marksSelection: Bool) -> some View {
            NavigationStack(path: Binding(
                get: { split.list },
                set: { navigator.setList($0, in: tab) },
            )) {
                root
                    .withAppDestinations()
            }
            .environment(\.opensRecordsBesideList, true)
            // Marked only beside the record: alone on screen, the list shows no selection.
            .environment(\.selectedRecord, marksSelection ? split.record : nil)
            .onScrollPhaseChange { _, phase in
                if phase == .interacting || phase == .animating { readingList = true }
            }
        }

        private func detail(_ split: SplitPath, showsBoth: Bool) -> some View {
            NavigationStack(path: Binding(
                get: { Array(split.detail.dropFirst()) },
                set: { navigator.setPath(self.split.detailChanged(to: $0), in: tab) },
            )) {
                Group {
                    if let record = split.record {
                        PushRouteView(route: record)
                            .id(record)
                    } else {
                        #if os(macOS)
                            ContentUnavailableView("Nothing Open", systemImage: "sidebar.left", description: Text("Choose something from the list to see it here."))
                        #endif
                    }
                }
                .withAppDestinations()
                .toolbar {
                    // One pane already has Back to the list; Close is for the record beside it. While
                    // it is being edited, the editor's Cancel is the way out.
                    if showsBoth, !navigator.isEditingRecord(in: tab) {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close record", systemImage: "xmark") {
                                navigator.closeRecord(in: tab)
                            }
                        }
                    }
                }
            }
            // Scrolling marks the record as the pane in use. Never a tap gesture here:
            // above a List it swallows row selection, so every row link in a record is dead.
            .onScrollPhaseChange { _, phase in
                if phase == .interacting || phase == .animating { readingList = false }
            }
        }
    }
#endif
