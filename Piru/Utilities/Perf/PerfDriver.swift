#if DEBUG
    import Foundation
    import SwiftData
    #if canImport(UIKit)
        import UIKit
    #endif

    extension PerfTour {
        /// One measured step: what it does, and an optional note for the report
        /// (a skipped precondition, a count it acted on).
        struct Step {
            let name: String
            let run: @MainActor (PerfDriver) async -> String?

            init(_ name: String, run: @escaping @MainActor (PerfDriver) async -> String?) {
                self.name = name
                self.run = run
            }
        }

        struct Flow {
            let name: String
            let steps: [Step]
        }
    }

    /// The moves a flow is made of: navigation through `AppNavigator`, and on
    /// iOS scrolling and typing through the UIKit views SwiftUI hosts, so no
    /// step depends on screen coordinates.
    @MainActor
    final class PerfDriver {
        let context: ModelContext
        let container: ModelContainer
        let directory: URL
        let navigator = AppNavigator.shared
        private let groupDefaults = UserDefaults(suiteName: AppIdentity.appGroup)

        init(context: ModelContext, container: ModelContainer, directory: URL) {
            self.context = context
            self.container = container
            self.directory = directory
        }

        /// The active profile's context: a profile switch replaces the container.
        var activeContext: ModelContext {
            ProfileDirectory.shared.activeContainer.mainContext
        }

        // MARK: - Navigation

        func reset() async {
            let hadSheet = !navigator.sheetStack.isEmpty
            navigator.dismissAll()
            navigator.resetAllPaths()
            await wait(hadSheet ? 0.7 : 0.3)
        }

        func wait(_ seconds: Double) async {
            try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
        }

        func tab(_ tab: TabID) {
            navigator.select(tab)
        }

        func push(_ route: PushRoute, in tab: TabID) {
            navigator.select(tab)
            navigator.setPath([route], in: tab)
        }

        func present(_ sheet: SheetRoute) {
            navigator.present(sheet)
        }

        func dismiss() {
            navigator.dismiss()
        }

        var currentGrouping: String? {
            groupDefaults?.string(forKey: JournalGroupingMigration.groupingKey)
        }

        func grouping(_ grouping: JournalGrouping) {
            groupDefaults?.set(grouping.rawValue, forKey: JournalGroupingMigration.groupingKey)
        }

        func restoreGrouping(_ raw: String?) {
            groupDefaults?.set(raw, forKey: JournalGroupingMigration.groupingKey)
        }

        // MARK: - Data

        func newestEntries(_ limit: Int) -> [DoseEntry] {
            var descriptor = FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
            descriptor.fetchLimit = limit
            return (try? activeContext.fetch(descriptor)) ?? []
        }

        func newestSessions(_ limit: Int) -> [Session] {
            var descriptor = FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
            descriptor.fetchLimit = limit
            return (try? activeContext.fetch(descriptor)) ?? []
        }

        // MARK: - Scrolling

        /// Scrolls the screen's main scroll view to its end and back, a page at
        /// a time, each page an animated move the next one interrupts — a fling.
        /// Returns the pages moved, or a note when there is nothing to scroll.
        func scrollEndToEnd(budget seconds: Double = 12, pause: Double = 0.12) async -> String {
            #if canImport(UIKit)
                guard let view = mainScrollView() else { return "no scroll view" }
                let deadline = Date.now.addingTimeInterval(seconds)
                var pages = 0
                var lastExtent: CGFloat = -1
                while Date.now < deadline {
                    let offset = view.contentOffset.y + view.bounds.height * 0.9
                    let limit = view.contentSize.height + view.adjustedContentInset.bottom - view.bounds.height
                    if offset >= limit {
                        if view.contentSize.height == lastExtent { break }
                        lastExtent = view.contentSize.height
                    }
                    view.setContentOffset(CGPoint(x: view.contentOffset.x, y: min(offset, max(limit, 0))), animated: true)
                    pages += 1
                    await wait(pause)
                }
                let back = Date.now.addingTimeInterval(seconds / 2)
                while view.contentOffset.y > -view.adjustedContentInset.top + 1, Date.now < back {
                    let offset = max(view.contentOffset.y - view.bounds.height * 1.8, -view.adjustedContentInset.top)
                    view.setContentOffset(CGPoint(x: view.contentOffset.x, y: offset), animated: true)
                    pages += 1
                    await wait(pause)
                }
                return "\(pages) pages, extent \(Int(view.contentSize.height)) pt"
            #else
                return "scrolling is iOS only"
            #endif
        }

        /// Flings down three pages and reverses halfway through, `times` over.
        func reversedFlings(_ times: Int) async -> String {
            #if canImport(UIKit)
                guard let view = mainScrollView() else { return "no scroll view" }
                for _ in 0 ..< times {
                    let down = view.contentOffset.y + view.bounds.height * 3
                    view.setContentOffset(CGPoint(x: view.contentOffset.x, y: down), animated: true)
                    await wait(0.12)
                    let up = max(view.contentOffset.y - view.bounds.height * 2, -view.adjustedContentInset.top)
                    view.setContentOffset(CGPoint(x: view.contentOffset.x, y: up), animated: true)
                    await wait(0.12)
                }
                return "\(times) reversals"
            #else
                return "scrolling is iOS only"
            #endif
        }

        // MARK: - Typing

        /// Types `text` one character at a time into the search field on
        /// screen, the way a fast typist does. Returns a note when no field is up.
        func type(_ text: String, interval: Double = 0.09, clearFirst: Bool = true) async -> String? {
            #if canImport(UIKit)
                guard let field = textField() else { return "no text field" }
                field.becomeFirstResponder()
                await wait(0.3)
                if clearFirst {
                    field.text = ""
                    field.sendActions(for: .editingChanged)
                }
                for character in text {
                    field.text = (field.text ?? "") + String(character)
                    field.sendActions(for: .editingChanged)
                    await wait(interval)
                }
                return nil
            #else
                return "typing is iOS only"
            #endif
        }

        func endEditing() {
            #if canImport(UIKit)
                for window in windows() {
                    window.endEditing(true)
                }
            #endif
        }

        #if canImport(UIKit)
            private func windows() -> [UIWindow] {
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).filter { !$0.isHidden }
            }

            /// The view of the frontmost presented controller, so a sheet's views
            /// win over the tab underneath it.
            private func frontView() -> UIView? {
                guard let window = windows().first(where: \.isKeyWindow) ?? windows().first,
                      var controller = window.rootViewController else { return nil }
                while let presented = controller.presentedViewController, !presented.isBeingDismissed {
                    controller = presented
                }
                return controller.view
            }

            /// The largest vertically scrollable view on screen.
            private func mainScrollView() -> UIScrollView? {
                guard let root = frontView() else { return nil }
                var best: (view: UIScrollView, area: CGFloat)?
                func visit(_ view: UIView) {
                    if let scroll = view as? UIScrollView, !(view is UITextView), scroll.window != nil, !scroll.isHidden,
                       scroll.contentSize.height > scroll.bounds.height + 1 {
                        let frame = scroll.convert(scroll.bounds, to: nil).intersection(scroll.window?.bounds ?? .zero)
                        let area = frame.width * frame.height
                        if area > (best?.area ?? 0) { best = (scroll, area) }
                    }
                    view.subviews.forEach(visit)
                }
                visit(root)
                return best?.view
            }

            private func textField() -> UITextField? {
                guard let root = frontView() else { return nil }
                func find(_ view: UIView) -> UITextField? {
                    if let field = view as? UISearchTextField, field.window != nil { return field }
                    for subview in view.subviews {
                        if let field = find(subview) { return field }
                    }
                    return nil
                }
                func anyField(_ view: UIView) -> UITextField? {
                    if let field = view as? UITextField, field.window != nil, field.isEnabled { return field }
                    for subview in view.subviews {
                        if let field = anyField(subview) { return field }
                    }
                    return nil
                }
                return find(root) ?? anyField(root) ?? windows().lazy.compactMap { find($0) }.first
            }
        #endif
    }
#endif
