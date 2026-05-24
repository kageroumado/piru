import Testing
import Foundation
import SwiftUI
@testable import Piru

@MainActor
@Suite("AppNavigator")
struct AppNavigatorTests {

    // MARK: - Helpers

    /// Builds a navigator backed by an isolated `UserDefaults` so tests don't
    /// leak the persisted `selectedTab` into one another.
    private func makeNavigator(selectedTab: AppTab? = nil) -> AppNavigator {
        let suite = "AppNavigatorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppNavigator(selectedTab: selectedTab, storage: defaults)
    }

    // MARK: - Tabs

    @Test("Default tab is journal")
    func defaultsToJournal() {
        let nav = makeNavigator()
        #expect(nav.selectedTab == .journal)
    }

    @Test("Selecting a tab persists across navigator instances when sharing storage")
    func selectionPersists() {
        let suite = "AppNavigatorTests-persist-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let nav = AppNavigator(storage: defaults)
        nav.select(.library)

        let nav2 = AppNavigator(storage: defaults)
        #expect(nav2.selectedTab == .library)
    }

    @Test("Explicit selectedTab init wins over persisted value")
    func explicitInitOverridesPersisted() {
        let suite = "AppNavigatorTests-override-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(AppTab.tools.rawValue, forKey: "AppNavigator.selectedTab")
        let nav = AppNavigator(selectedTab: .insights, storage: defaults)
        #expect(nav.selectedTab == .insights)
    }

    // MARK: - Push paths

    @Test("Push appends to the current tab's path")
    func pushAppends() {
        let nav = makeNavigator(selectedTab: .journal)
        nav.push(.day(date: .now))
        nav.push(.entry(timestamp: .now))
        #expect(nav.path(for: .journal).count == 2)
    }

    @Test("Push into another tab does not affect the current tab")
    func pushIsTabScoped() {
        let nav = makeNavigator(selectedTab: .journal)
        nav.push(.substance(name: "LSD"), in: .library)
        #expect(nav.path(for: .journal).isEmpty)
        #expect(nav.path(for: .library) == [.substance(name: "LSD")])
    }

    @Test("Pop removes the last element of the current tab's path")
    func popRemovesLast() {
        let nav = makeNavigator(selectedTab: .journal)
        nav.push(.day(date: .now))
        nav.push(.entry(timestamp: .now))
        nav.pop()
        #expect(nav.path(for: .journal).count == 1)
    }

    @Test("Pop on empty path is a no-op")
    func popEmptyIsNoOp() {
        let nav = makeNavigator()
        nav.pop()
        #expect(nav.path(for: nav.selectedTab).isEmpty)
    }

    @Test("popToRoot clears the current tab")
    func popToRootClears() {
        let nav = makeNavigator(selectedTab: .journal)
        nav.push(.day(date: .now))
        nav.push(.entry(timestamp: .now))
        nav.popToRoot()
        #expect(nav.path(for: .journal).isEmpty)
    }

    @Test("popToRoot in one tab leaves others alone")
    func popToRootScoped() {
        let nav = makeNavigator(selectedTab: .journal)
        nav.push(.day(date: .now), in: .journal)
        nav.push(.substance(name: "MDMA"), in: .library)
        nav.popToRoot(in: .journal)
        #expect(nav.path(for: .journal).isEmpty)
        #expect(nav.path(for: .library).count == 1)
    }

    @Test("pathBinding read and write round-trip through the navigator")
    func pathBindingRoundTrip() {
        let nav = makeNavigator(selectedTab: .insights)
        let binding = nav.pathBinding(for: .insights)
        binding.wrappedValue = [.day(date: Date(timeIntervalSince1970: 1_000))]
        #expect(nav.path(for: .insights).count == 1)
        nav.push(.day(date: Date(timeIntervalSince1970: 2_000)))
        #expect(binding.wrappedValue.count == 2)
    }

    // MARK: - Sheet stack

    @Test("present appends to the sheet stack")
    func presentAppends() {
        let nav = makeNavigator()
        nav.present(.quickLog)
        nav.present(.colorPicker(substance: "MDMA"))
        #expect(nav.sheetStack.count == 2)
        #expect(nav.sheetStack.last == .colorPicker(substance: "MDMA", remaining: []))
    }

    @Test("dismiss removes the top sheet")
    func dismissRemovesTop() {
        let nav = makeNavigator()
        nav.present(.quickLog)
        nav.present(.help)
        nav.dismiss()
        #expect(nav.sheetStack == [.quickLog])
    }

    @Test("dismiss on empty stack is a no-op")
    func dismissEmptyIsNoOp() {
        let nav = makeNavigator()
        nav.dismiss()
        #expect(nav.sheetStack.isEmpty)
    }

    @Test("dismissAll empties the stack")
    func dismissAllEmpties() {
        let nav = makeNavigator()
        nav.present(.settings)
        nav.present(.help)
        nav.present(.quickLog)
        nav.dismissAll()
        #expect(nav.sheetStack.isEmpty)
    }

    @Test("dismiss(_:) removes a specific sheet")
    func dismissSpecific() {
        let nav = makeNavigator()
        nav.present(.settings)
        nav.present(.help)
        nav.present(.quickLog)
        nav.dismiss(.help)
        #expect(nav.sheetStack == [.settings, .quickLog])
    }

    @Test("present with replacingTop swaps the top instead of nesting")
    func replacingTopSwaps() {
        let nav = makeNavigator()
        nav.present(.entryForm(prefill: nil))
        nav.present(.colorPicker(substance: "Caffeine"), replacingTop: true)
        #expect(nav.sheetStack.count == 1)
        #expect(nav.sheetStack.first == .colorPicker(substance: "Caffeine", remaining: []))
    }

    @Test("present with replacingTop on empty stack appends")
    func replacingTopOnEmptyAppends() {
        let nav = makeNavigator()
        nav.present(.quickLog, replacingTop: true)
        #expect(nav.sheetStack == [.quickLog])
    }

    @Test("truncateSheetStack to a depth trims deeper sheets")
    func truncateTrims() {
        let nav = makeNavigator()
        nav.present(.settings)
        nav.present(.help)
        nav.present(.quickLog)
        nav.truncateSheetStack(to: 1)
        #expect(nav.sheetStack == [.settings])
    }

    @Test("truncateSheetStack to a depth >= current size is a no-op")
    func truncateAboveSizeNoOp() {
        let nav = makeNavigator()
        nav.present(.quickLog)
        nav.truncateSheetStack(to: 5)
        #expect(nav.sheetStack == [.quickLog])
    }

    @Test("present beyond maxSheetDepth is dropped silently")
    func presentBeyondMaxDepthDropped() {
        let nav = makeNavigator()
        nav.present(.settings)
        nav.present(.help)
        nav.present(.quickLog)
        // We're at the cap (3). A fourth append must be dropped.
        nav.present(.sessionDetail)
        #expect(nav.sheetStack.count == AppNavigator.maxSheetDepth)
        #expect(nav.sheetStack.last == .quickLog)
    }

    @Test("replacingTop still succeeds at maxSheetDepth")
    func replacingTopAtMaxDepthSucceeds() {
        let nav = makeNavigator()
        nav.present(.settings)
        nav.present(.help)
        nav.present(.quickLog)
        nav.present(.sessionDetail, replacingTop: true)
        #expect(nav.sheetStack.count == AppNavigator.maxSheetDepth)
        #expect(nav.sheetStack.last == .sessionDetail)
    }

    @Test("Setting snapshot clamps sheetStack to maxSheetDepth")
    func snapshotClampsSheetStackDepth() {
        let nav = makeNavigator()
        var snap = NavigatorSnapshot()
        snap.sheetStack = [.settings, .help, .quickLog, .sessionDetail, .entryForm(prefill: nil)]
        nav.snapshot = snap
        #expect(nav.sheetStack.count == AppNavigator.maxSheetDepth)
        // First N from the snapshot survive — deeper items are dropped.
        #expect(nav.sheetStack == [.settings, .help, .quickLog])
    }

    // MARK: - Color picker queue (the Phase 3 bug fix)

    @Test("Color picker queue advances via replacingTop, then dismisses when empty")
    func colorPickerQueueAdvancesAndDismisses() {
        let nav = makeNavigator()
        // Form presents itself, then on Save replaces with the first picker.
        nav.present(.entryForm(prefill: nil))
        nav.present(.colorPicker(substance: "A", remaining: ["B", "C"]), replacingTop: true)

        // Simulate the picker advancing the queue.
        guard case .colorPicker(_, let r1, _) = nav.sheetStack.last else {
            Issue.record("Expected color picker on top")
            return
        }
        nav.present(.colorPicker(substance: r1.first!, remaining: Array(r1.dropFirst())), replacingTop: true)
        nav.present(.colorPicker(substance: "C", remaining: []), replacingTop: true)

        #expect(nav.sheetStack.count == 1)
        #expect(nav.sheetStack.last == .colorPicker(substance: "C", remaining: []))

        nav.dismiss()
        #expect(nav.sheetStack.isEmpty)
    }

    @Test("dismissAll clears the whole chain (logging-flow completion)")
    func dismissAllChain() {
        let nav = makeNavigator()
        // Simulate QuickLog → From Library → EntryForm.
        nav.present(.quickLog)
        nav.present(.entryForm(prefill: EntryPrefillPayload(substance: "Caffeine", route: .oral, unit: "mg")))
        #expect(nav.sheetStack.count == 2)
        // The save handler for a new entry should land us back at root.
        nav.dismissAll()
        #expect(nav.sheetStack.isEmpty)
    }

    @Test("colorPicker route propagates dismissAllOnComplete through Codable")
    func colorPickerCarriesDismissAllFlag() throws {
        let route = SheetRoute.colorPicker(substance: "A", remaining: ["B"], dismissAllOnComplete: true)
        let data = try JSONEncoder().encode(route)
        let decoded = try JSONDecoder().decode(SheetRoute.self, from: data)
        #expect(decoded == route)
        if case .colorPicker(_, _, let flag) = decoded {
            #expect(flag == true)
        } else {
            Issue.record("Expected color picker case")
        }
    }

    // MARK: - Snapshot

    @Test("Snapshot reflects current navigator state")
    func snapshotReflectsState() {
        let nav = makeNavigator(selectedTab: .insights)
        nav.push(.substance(name: "Caffeine"), in: .library)
        nav.present(.quickLog)

        let snap = nav.snapshot
        #expect(snap.selectedTab == .insights)
        #expect(snap.paths[.library] == [.substance(name: "Caffeine")])
        #expect(snap.sheetStack == [.quickLog])
    }

    @Test("Setting snapshot replaces navigator state")
    func snapshotApplies() {
        let nav = makeNavigator()
        var snap = NavigatorSnapshot()
        snap.selectedTab = .tools
        snap.paths[.journal] = [.day(date: Date(timeIntervalSince1970: 0))]
        snap.sheetStack = [.help, .settings]
        nav.snapshot = snap
        #expect(nav.selectedTab == .tools)
        #expect(nav.path(for: .journal).count == 1)
        #expect(nav.sheetStack == [.help, .settings])
    }
}

// MARK: - Route Codable

@Suite("Routes Codable")
struct RoutesCodableTests {

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @Test("Every AppTab encodes and decodes")
    func appTabRoundTrip() throws {
        for tab in AppTab.allCases {
            let decoded = try roundTrip(tab)
            #expect(decoded == tab)
        }
    }

    @Test("Each PushRoute case round-trips", arguments: [
        PushRoute.day(date: Date(timeIntervalSince1970: 1_700_000_000)),
        PushRoute.entry(timestamp: Date(timeIntervalSince1970: 1_700_000_500)),
        PushRoute.substance(name: "LSD"),
        .libraryCategory(.stimulant),
        .libraryCategory(.psychedelic),
        .libraryFavorites,
    ])
    func pushRouteRoundTrip(route: PushRoute) throws {
        #expect(try roundTrip(route) == route)
    }

    @Test("Each SheetRoute case round-trips", arguments: [
        SheetRoute.quickLog,
        .settings,
        .help,
        .onboarding,
        .sessionDetail,
        .entryDetail(timestamp: Date(timeIntervalSince1970: 100)),
        .entryForm(prefill: nil),
        .entryForm(prefill: EntryPrefillPayload(substance: "MDMA", route: .oral, unit: "mg")),
        .entryEdit(timestamp: Date(timeIntervalSince1970: 200)),
        .dailyDoseLog(category: "Antidepressants"),
        .dailyDoseSettings,
        .dailyDoseItemForm(itemID: nil),
        .dailyDoseItemForm(itemID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
        .customSubstancesList,
        .customSubstanceForm(id: nil),
        .customSubstanceForm(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
        .colorPicker(substance: "Caffeine", remaining: []),
        .colorPicker(substance: "A", remaining: ["B", "C"]),
        .journalFilters,
        .journalCalendar,
        .timeAdjust(entryTimestamp: Date(timeIntervalSince1970: 300)),
        .dayShare(date: Date(timeIntervalSince1970: 400)),
    ])
    func sheetRouteRoundTrip(route: SheetRoute) throws {
        #expect(try roundTrip(route) == route)
    }

    @Test("A full NavigatorSnapshot round-trips")
    func snapshotRoundTrip() throws {
        let snap = NavigatorSnapshot(
            selectedTab: .library,
            paths: [
                .journal: [.day(date: Date(timeIntervalSince1970: 1)), .entry(timestamp: Date(timeIntervalSince1970: 2))],
                .library: [.substance(name: "DMT")],
            ],
            sheetStack: [
                .entryForm(prefill: EntryPrefillPayload(substance: "MDMA", route: .insufflation, unit: "mg")),
                .colorPicker(substance: "MDMA", remaining: ["Caffeine"]),
            ]
        )
        let decoded = try JSONDecoder().decode(NavigatorSnapshot.self, from: JSONEncoder().encode(snap))
        #expect(decoded == snap)
    }
}
