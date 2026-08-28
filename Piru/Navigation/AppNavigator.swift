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

    var selectedTab: AppTab {
        didSet {
            guard selectedTab != oldValue else { return }
            storage.set(selectedTab.rawValue, forKey: Self.selectedTabKey)
        }
    }

    private(set) var paths: [AppTab: [PushRoute]]

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

    // MARK: - Init

    init(
        selectedTab: AppTab? = nil,
        paths: [AppTab: [PushRoute]] = [:],
        sheetStack: [SheetRoute] = [],
        storage: UserDefaults = .standard,
    ) {
        self.storage = storage
        if let selectedTab {
            self.selectedTab = selectedTab
        } else if let raw = storage.string(forKey: Self.selectedTabKey),
                  let tab = AppTab(rawValue: raw) {
            self.selectedTab = tab
        } else {
            self.selectedTab = .journal
        }
        self.paths = paths
        self.sheetStack = sheetStack
    }

    // MARK: - Tabs

    func select(_ tab: AppTab) {
        selectedTab = tab
    }

    // MARK: - Push

    /// Push onto the current navigation context. With an explicit `tab` the
    /// route always lands on that tab's stack; otherwise, when a push-capable
    /// sheet is on top (`SheetRoute.supportsPushNavigation`), the route goes
    /// to *that sheet's* path — the visible stack — not the tab behind it.
    func push(_ route: PushRoute, in tab: AppTab? = nil) {
        if tab == nil, let top = sheetStack.last, top.supportsPushNavigation {
            sheetPaths[sheetStack.count - 1, default: []].append(route)
            return
        }
        let target = tab ?? selectedTab
        paths[target, default: []].append(route)
    }

    func pop(in tab: AppTab? = nil) {
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

    func popToRoot(in tab: AppTab? = nil) {
        let target = tab ?? selectedTab
        paths[target] = []
    }

    func setPath(_ path: [PushRoute], in tab: AppTab? = nil) {
        let target = tab ?? selectedTab
        paths[target] = path
    }

    func path(for tab: AppTab) -> [PushRoute] {
        paths[tab, default: []]
    }

    /// Binding into the per-tab path so a `NavigationStack(path:)` can mutate it
    /// directly when the system pops via back button or swipe.
    func pathBinding(for tab: AppTab) -> Binding<[PushRoute]> {
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
        let candidates = [selectedTab] + AppTab.allCases.filter { $0 != selectedTab }
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
        if let tab = outcome.tab {
            selectedTab = tab
        }
        // A push path replaces the target tab's stack — a deep link to a tool
        // or session is a "land me here" intent, not an append onto wherever
        // the user already was. Targets the outcome's tab (falling back to the
        // now-selected tab) so `piru://tool/tolerance` lands on Tools.
        if let path = outcome.path {
            setPath(path, in: outcome.tab)
        }
        if let sheet = outcome.sheet {
            if sheet == .sessionDetail, sheetStack.isEmpty,
               let sessionID = currentSessionID, revealOpenSession(id: sessionID) {
                // Revealed the existing screen (overriding the outcome's
                // default `.journal` tab with wherever it actually lives).
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
}

extension EnvironmentValues {
    @Entry var appNavigator: AppNavigator = .shared
}
