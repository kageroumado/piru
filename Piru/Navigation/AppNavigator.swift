import Observation
import SwiftUI

/// Single source of truth for the app's navigation state — tab selection,
/// per-tab push paths, and the modal stack.
///
/// Views read state through `@Bindable` and call mutating methods (`push`,
/// `present`, `dismiss`, etc.) rather than holding their own `@State`
/// navigation flags. Dismissal is a synchronous state mutation, not a
/// `@Environment(\.dismiss)` round-trip through the view tree — that
/// difference is what kills the "Done needs two taps" bug.
///
/// Use ``AppNavigator/shared`` from anywhere; views typically receive it via
/// `@Environment(\.appNavigator)`.
@MainActor
@Observable
final class AppNavigator {
    static let shared = AppNavigator()

    // MARK: - State

    var selectedTab: TabID {
        didSet {
            guard selectedTab != oldValue else { return }
            storage.set(selectedTab.storageKey, forKey: Self.selectedTabKey)
        }
    }

    private(set) var paths: [TabID: [PushRoute]]

    /// How many times each tab has reopened the record already beside its list. The
    /// path does not change then, so a split tab watches this to show the record again.
    private(set) var recordReopenings: [TabID: Int] = [:]

    /// Records with an edit in progress, by the tab they were opened in. Opening
    /// another record in that tab, or closing it, would throw the edit away.
    private(set) var recordsBeingEdited: [UUID: TabID] = [:]

    /// A change to a tab's open record waiting for the person to discard an edit.
    private(set) var pendingRecordChange: PendingRecordChange?

    /// Modal stack — top of the stack is what's currently presented. Multiple
    /// entries mean nested modals (e.g. form → color picker), though SwiftUI
    /// only gracefully renders ~3 deep on iOS 26.
    private(set) var sheetStack: [SheetRoute]

    /// Push paths for sheets that host their own `NavigationStack`
    /// (`SheetRoute.supportsPushNavigation`), keyed by depth in `sheetStack`.
    /// While such a sheet is on top, `push`/`pop` target its path — the tab
    /// stacks are behind the sheet, so pushing there would navigate a screen
    /// the user can't see while the sheet itself stays put.
    private(set) var sheetPaths: [Int: [PushRoute]] = [:]

    // MARK: - Persistence

    @ObservationIgnored
    private let storage: UserDefaults

    @ObservationIgnored
    private static let selectedTabKey = "AppNavigator.selectedTab"

    /// The user's tab bar — what a "land me here" request resolves against.
    @ObservationIgnored
    private let layout: TabLayoutStore

    // MARK: - Init

    init(
        selectedTab: TabID? = nil,
        paths: [TabID: [PushRoute]] = [:],
        sheetStack: [SheetRoute] = [],
        storage: UserDefaults = .standard,
        layout: TabLayoutStore = .shared,
    ) {
        self.storage = storage
        self.layout = layout
        let visible = layout.layout.visible
        if let selectedTab {
            self.selectedTab = selectedTab
        } else if let key = storage.string(forKey: Self.selectedTabKey),
                  let tab = TabID(storageKey: key),
                  visible.contains(tab) {
            self.selectedTab = tab
        } else {
            // Nothing persisted, or a tab the user has since taken out of the bar.
            self.selectedTab = visible.first ?? .journal
        }
        self.paths = paths
        self.sheetStack = sheetStack
    }

    // MARK: - Tabs

    func select(_ tab: TabID) {
        selectedTab = tab
    }

    /// Follow a tab-bar edit: a selection that left the bar moves to the first
    /// tab, and stacks of removed tabs are dropped so re-adding one starts at
    /// its root.
    func reconcile(visible: [TabID]) {
        if !visible.contains(selectedTab), let first = visible.first {
            selectedTab = first
        }
        paths = paths.filter { visible.contains($0.key) }
    }

    /// Pop every tab to its root.
    func resetAllPaths() {
        paths.removeAll()
    }

    /// Land on `route` — the dock's shortcuts and other "take me there"
    /// actions. `home` is the tab the route belongs to; where it actually
    /// lands depends on the user's bar (`TabRouting`).
    func open(_ route: PushRoute, home: AppTab) {
        switch TabRouting.target(for: route, home: home, visible: layout.layout.visible) {
        case let .pinned(tab):
            selectedTab = tab
            setPath([], in: tab)
        case let .home(tab):
            selectedTab = tab
            push(route, in: tab)
        case .current:
            push(route, in: selectedTab)
        }
    }

    // MARK: - Push

    /// Push onto the current navigation context. With an explicit `tab` the
    /// route always lands on that tab's stack; otherwise, when a push-capable
    /// sheet is on top (`SheetRoute.supportsPushNavigation`), the route goes
    /// to *that sheet's* path — the visible stack — not the tab behind it.
    func push(_ route: PushRoute, in tab: TabID? = nil) {
        if tab == nil, let top = sheetStack.last, top.supportsPushNavigation {
            sheetPaths[sheetStack.count - 1, default: []].append(route)
            return
        }
        let target = tab ?? selectedTab
        paths[target, default: []].append(route)
    }

    func pop(in tab: TabID? = nil) {
        if tab == nil, let top = sheetStack.last, top.supportsPushNavigation {
            let depth = sheetStack.count - 1
            guard var sheetPath = sheetPaths[depth], !sheetPath.isEmpty else { return }
            sheetPath.removeLast()
            sheetPaths[depth] = sheetPath
            return
        }
        let target = tab ?? selectedTab
        guard var stack = paths[target], !stack.isEmpty else { return }
        stack.removeLast()
        paths[target] = stack
    }

    /// Opens a route from a tab's root list: beside the list in a split tab, pushed otherwise.
    /// When the record beside the list is being edited, it waits for ``resolvePendingRecordChange(discard:)``.
    func openRecord(_ route: PushRoute, besideList: Bool) {
        guard besideList else { return push(route) }
        guard !isEditingRecord(in: selectedTab) else {
            pendingRecordChange = PendingRecordChange(tab: selectedTab, opening: route)
            return
        }
        apply(PendingRecordChange(tab: selectedTab, opening: route))
    }

    /// Sets the levels of a split tab's list column. A record pushed there (a link the
    /// collapsed split hosts outside the list's environment) opens beside the list.
    func setList(_ newList: [PushRoute], in tab: TabID) {
        let split = SplitPath(path(for: tab))
        if let opened = newList.first(where: \.opensBesideList), opened == split.record {
            recordReopenings[tab, default: 0] += 1
        }
        setPath(split.listChanged(to: newList), in: tab)
    }

    /// Closes the record beside a tab's list, waiting the same way while it is being edited.
    func closeRecord(in tab: TabID) {
        let change = PendingRecordChange(tab: tab, opening: nil)
        guard !isEditingRecord(in: tab) else {
            pendingRecordChange = change
            return
        }
        apply(change)
    }

    /// Discards the waiting change's edit and makes the change, or keeps editing.
    func resolvePendingRecordChange(discard: Bool) {
        guard let change = pendingRecordChange else { return }
        pendingRecordChange = nil
        guard discard else { return }
        recordsBeingEdited = recordsBeingEdited.filter { $0.value != change.tab }
        apply(change)
    }

    /// Marks a record as being edited in the selected tab, or no longer.
    func setEditing(_ editing: Bool, record id: UUID) {
        if editing {
            recordsBeingEdited[id] = selectedTab
        } else {
            recordsBeingEdited[id] = nil
        }
    }

    /// Takes the routes `matching` out of the selected tab's path, for a record that
    /// was just deleted: a nested one pops, a record beside the list closes. Returns
    /// whether any were there; a record shown in a sheet is the sheet's to dismiss.
    @discardableResult
    func removeDeletedRecord(matching: (PushRoute) -> Bool) -> Bool {
        guard sheetStack.isEmpty else { return false }
        let stack = path(for: selectedTab)
        guard let first = stack.firstIndex(where: matching) else { return false }
        setPath(Array(stack[..<first]), in: selectedTab)
        return true
    }

    /// Whether the record open beside a tab's list has an edit in progress.
    func isEditingRecord(in tab: TabID) -> Bool {
        recordsBeingEdited.values.contains(tab)
    }

    private func apply(_ change: PendingRecordChange) {
        let split = SplitPath(path(for: change.tab))
        guard let route = change.opening else { return setPath(split.list, in: change.tab) }
        if split.record == route { recordReopenings[change.tab, default: 0] += 1 }
        setPath(split.opening(route), in: change.tab)
    }

    func popToRoot(in tab: TabID? = nil) {
        let target = tab ?? selectedTab
        paths[target] = []
    }

    func setPath(_ path: [PushRoute], in tab: TabID? = nil) {
        let target = tab ?? selectedTab
        paths[target] = path
    }

    func path(for tab: TabID) -> [PushRoute] {
        paths[tab, default: []]
    }

    /// Binding into the per-tab path so a `NavigationStack(path:)` can mutate it
    /// directly when the system pops via back button or swipe.
    func pathBinding(for tab: TabID) -> Binding<[PushRoute]> {
        Binding(
            get: { [weak self] in self?.paths[tab, default: []] ?? [] },
            set: { [weak self] in self?.paths[tab] = $0 },
        )
    }

    func sheetPath(atDepth depth: Int) -> [PushRoute] {
        sheetPaths[depth, default: []]
    }

    /// Binding into a presented sheet's own push path (see `sheetPaths`), so
    /// the sheet's `NavigationStack` can mutate it directly on system pops.
    func sheetPathBinding(atDepth depth: Int) -> Binding<[PushRoute]> {
        Binding(
            get: { [weak self] in self?.sheetPaths[depth, default: []] ?? [] },
            set: { [weak self] in self?.sheetPaths[depth] = $0 },
        )
    }

    // MARK: - Modals

    /// Maximum sheet stack depth that the presenter can render gracefully on
    /// iOS 26. Pushing past this limit is silently dropped — sheets in state
    /// but not on screen would otherwise create a "ghost stack" where
    /// `dismiss()` removes invisible items before reaching what the user
    /// can actually see.
    static let maxSheetDepth = 3

    /// Present `sheet` on top of the current stack.
    ///
    /// When `replacingTop` is true and a sheet is already showing, the top of
    /// the stack is replaced rather than a new sheet being nested. This is the
    /// pattern used by Save handlers: dismiss the current form *and* present
    /// the color picker in one atomic transition, so the user perceives a
    /// single tap of Done.
    ///
    /// Pushes beyond `maxSheetDepth` are dropped; replacements always succeed.
    ///
    func present(_ sheet: SheetRoute, replacingTop: Bool = false) {
        if replacingTop, !sheetStack.isEmpty {
            sheetStack[sheetStack.count - 1] = sheet
            sheetPaths[sheetStack.count - 1] = nil
        } else if sheetStack.count < Self.maxSheetDepth {
            sheetStack.append(sheet)
            sheetPaths[sheetStack.count - 1] = nil
        }
    }

    /// Dismiss the top sheet. No-op when the stack is empty.
    func dismiss() {
        guard !sheetStack.isEmpty else { return }
        sheetStack.removeLast()
        sheetPaths[sheetStack.count] = nil
    }

    /// Dismiss every sheet at once.
    func dismissAll() {
        sheetStack.removeAll()
        sheetPaths.removeAll()
    }

    /// Dismiss the last occurrence of a specific sheet from the stack (rare;
    /// usually used to dismiss a known sheet from a sibling context).
    func dismiss(_ sheet: SheetRoute) {
        guard let idx = sheetStack.lastIndex(of: sheet) else { return }
        sheetStack.remove(at: idx)
        // Sheets above `idx` shift down one — their paths must follow.
        sheetPaths = Dictionary(uniqueKeysWithValues: sheetPaths.compactMap { depth, path in
            if depth == idx { return nil }
            return (depth > idx ? depth - 1 : depth, path)
        })
    }

    /// Trim the sheet stack to the given depth. Called by the sheet stack
    /// presenter when the system dismisses a sheet (swipe down, tap outside)
    /// — that closes everything deeper as well.
    func truncateSheetStack(to depth: Int) {
        guard sheetStack.count > depth else { return }
        sheetStack = Array(sheetStack.prefix(depth))
        sheetPaths = sheetPaths.filter { $0.key < depth }
    }

    // MARK: - Snapshot

    /// The full navigator state as a Codable value. Used by the deep link
    /// codec and for tests.
    var snapshot: NavigatorSnapshot {
        get { NavigatorSnapshot(selectedTab: selectedTab, paths: paths, sheetStack: sheetStack) }
        set {
            selectedTab = newValue.selectedTab
            paths = newValue.paths
            // Same `maxSheetDepth` clamp as `present(_:)`. A snapshot loaded
            // from disk or assembled programmatically must not bypass the
            // limit and create invisible sheets that `dismiss()` would have
            // to drain before reaching what the user can see.
            sheetStack = Array(newValue.sheetStack.prefix(Self.maxSheetDepth))
            // Snapshots don't carry sheet paths; whatever was tracked belongs
            // to the replaced stack.
            sheetPaths.removeAll()
        }
    }

    // MARK: - Session Detail

    /// Open the current session (accessory pill tap): if that session's detail
    /// is already somewhere on a tab's push stack, reveal it there instead of
    /// presenting a duplicate `.sessionDetail` sheet over it; otherwise present
    /// the sheet as before. Reveal only applies with no sheets up — under an
    /// open sheet the revealed tab wouldn't be visible.
    func revealOrPresentSessionDetail(currentSessionID: UUID?) {
        if sheetStack.isEmpty, let id = currentSessionID, revealOpenSession(id: id) { return }
        present(.sessionDetail)
    }

    /// If `.session(id:)` is on some tab's push stack, switch to that tab and
    /// trim the stack so the session screen is on top — the intent is "show me
    /// this screen", not "show me whatever was stacked above it". The selected
    /// tab is preferred when several tabs have it. Returns whether a reveal
    /// happened.
    private func revealOpenSession(id: UUID) -> Bool {
        let target = PushRoute.session(id: id)
        let candidates = [selectedTab] + layout.layout.visible.filter { $0 != selectedTab }
        guard let tab = candidates.first(where: { paths[$0, default: []].contains(target) }),
              let index = paths[tab]?.lastIndex(of: target)
        else { return false }
        paths[tab] = Array(paths[tab]![...index])
        selectedTab = tab
        return true
    }

    /// Apply a deep-link outcome. Unlike setting `snapshot`, this only mutates
    /// the slices the URL spoke about — a sheet-only URL doesn't clobber the
    /// current tab.
    ///
    /// `currentSessionID` is the session the `.sessionDetail` sheet would show
    /// (resolved by the caller, which has store access); it lets a `piru://day`
    /// link reveal an already-open session screen instead of presenting a
    /// duplicate sheet whose pushes would land on the stack behind it.
    func apply(_ outcome: DeepLinkOutcome, currentSessionID: UUID? = nil) {
        if let path = outcome.path {
            land(on: path, home: outcome.tab)
        } else if let tab = outcome.tab, layout.layout.visible.contains(.stock(tab)) {
            // A tab-only link to a tab the user took out of the bar changes nothing.
            selectedTab = .stock(tab)
        }
        if let sheet = outcome.sheet {
            if sheet == .sessionDetail, sheetStack.isEmpty,
               let sessionID = currentSessionID, revealOpenSession(id: sessionID) {
                // Revealed the existing screen wherever it actually lives.
                return
            }
            // A link targeting the kind of sheet that's already on top is a
            // no-op: `piru://quicklog?routine=…` while quick-log is open must
            // not stack a duplicate — or worse, rebuild the tray and discard
            // whatever the user has staged mid-composition.
            let topIsSameKind = switch (sheetStack.last, sheet) {
            case (.quickLog?, .quickLog): true
            default: sheetStack.last == sheet
            }
            if !topIsSameKind {
                present(sheet)
            }
        }
    }

    /// A push path is a "land me here" intent, not an append onto wherever
    /// the user already was: it replaces the stack of the tab it lands on —
    /// the pinned tab showing its first route (which becomes the root), else
    /// the home tab. With neither in the bar it goes onto the current tab,
    /// and there it appends, since that stack is the user's own.
    private func land(on path: [PushRoute], home: AppTab?) {
        switch TabRouting.target(for: path.first, home: home, visible: layout.layout.visible) {
        case let .pinned(tab):
            selectedTab = tab
            setPath(Array(path.dropFirst()), in: tab)
        case let .home(tab):
            selectedTab = tab
            setPath(path, in: tab)
        case .current:
            let current = self.path(for: selectedTab)
            if !current.ends(with: path) {
                setPath(current + path)
            }
        }
    }
}

private extension Array where Element: Equatable {
    func ends(with suffix: [Element]) -> Bool {
        count >= suffix.count && Array(self[(count - suffix.count)...]) == suffix
    }
}

extension EnvironmentValues {
    @Entry var appNavigator: AppNavigator = .shared
}

/// A change to the record open beside a tab's list: another record, or none.
struct PendingRecordChange: Equatable {
    let tab: TabID
    let opening: PushRoute?
}
