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

    /// `matchedTransitionSource` id the current depth-0 sheet should zoom out of,
    /// set by `present(_:zoomSource:)`. Drives the Mail-style grow-from-button
    /// effect for the quick-log and current-session sheets. `nil` → default
    /// slide-up (deep links, ordinary presents).
    var sheetZoomSourceID: String?

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

    func push(_ route: PushRoute, in tab: AppTab? = nil) {
        let target = tab ?? selectedTab
        paths[target, default: []].append(route)
    }

    func pop(in tab: AppTab? = nil) {
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
    /// `zoomSource` records the `matchedTransitionSource` id the presented sheet
    /// should grow out of (e.g. the floating add button). It's set on *every*
    /// call — defaulting to `nil` — so an ordinary present never inherits a stale
    /// zoom id from a previous launch; only callers that pass one get a zoom.
    func present(_ sheet: SheetRoute, replacingTop: Bool = false, zoomSource: String? = nil) {
        sheetZoomSourceID = zoomSource
        if replacingTop, !sheetStack.isEmpty {
            sheetStack[sheetStack.count - 1] = sheet
        } else if sheetStack.count < Self.maxSheetDepth {
            sheetStack.append(sheet)
        }
    }

    /// Dismiss the top sheet. No-op when the stack is empty.
    func dismiss() {
        guard !sheetStack.isEmpty else { return }
        sheetStack.removeLast()
    }

    /// Dismiss every sheet at once.
    func dismissAll() {
        sheetStack.removeAll()
    }

    /// Dismiss the last occurrence of a specific sheet from the stack (rare;
    /// usually used to dismiss a known sheet from a sibling context).
    func dismiss(_ sheet: SheetRoute) {
        guard let idx = sheetStack.lastIndex(of: sheet) else { return }
        sheetStack.remove(at: idx)
    }

    /// Trim the sheet stack to the given depth. Called by the sheet stack
    /// presenter when the system dismisses a sheet (swipe down, tap outside)
    /// — that closes everything deeper as well.
    func truncateSheetStack(to depth: Int) {
        guard sheetStack.count > depth else { return }
        sheetStack = Array(sheetStack.prefix(depth))
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
        }
    }

    /// Apply a deep-link outcome. Unlike setting `snapshot`, this only mutates
    /// the slices the URL spoke about — a sheet-only URL doesn't clobber the
    /// current tab.
    func apply(_ outcome: DeepLinkOutcome) {
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
            // A link targeting the kind of sheet that's already on top is a
            // no-op: `piru://quicklog?routine=…` while quick-log is open must
            // not stack a duplicate — or worse, rebuild the tray and discard
            // whatever the user has staged mid-composition.
            let topIsSameKind = switch (sheetStack.last, sheet) {
            case (.quickLog?, .quickLog): true
            default: sheetStack.last == sheet
            }
            if !topIsSameKind {
                // Deep links have no on-screen source button; `present` defaults
                // `zoomSource` to nil, so the sheet slides up normally rather
                // than zooming from a control that isn't there.
                present(sheet)
            }
        }
    }
}

extension EnvironmentValues {
    @Entry var appNavigator: AppNavigator = .shared
}
