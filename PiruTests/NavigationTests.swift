import Foundation
import SwiftUI
import Testing
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

    @Test
    func `Default tab is journal`() {
        let nav = makeNavigator()
        #expect(nav.selectedTab == .journal)
    }

    @Test
    func `Selecting a tab persists across navigator instances when sharing storage`() throws {
        let suite = "AppNavigatorTests-persist-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let nav = AppNavigator(storage: defaults)
        nav.select(.library)

        let nav2 = AppNavigator(storage: defaults)
        #expect(nav2.selectedTab == .library)
    }

    @Test
    func `Explicit selectedTab init wins over persisted value`() throws {
        let suite = "AppNavigatorTests-override-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(AppTab.tools.rawValue, forKey: "AppNavigator.selectedTab")
        let nav = AppNavigator(selectedTab: .insights, storage: defaults)
        #expect(nav.selectedTab == .insights)
    }

    // MARK: - Push paths

    @Test
    func `Push appends to the current tab's path`() {
        let nav = makeNavigator(selectedTab: .journal)
        nav.push(.session(id: UUID()))
        nav.push(.entry(timestamp: .now, id: UUID()))
        #expect(nav.path(for: .journal).count == 2)
    }

    @Test
    func `Push into another tab does not affect the current tab`() {
        let nav = makeNavigator(selectedTab: .journal)
        nav.push(.substance(name: "LSD"), in: .library)
        #expect(nav.path(for: .journal).isEmpty)
        #expect(nav.path(for: .library) == [.substance(name: "LSD")])
    }

    @Test
    func `Pop removes the last element of the current tab's path`() {
        let nav = makeNavigator(selectedTab: .journal)
        nav.push(.session(id: UUID()))
        nav.push(.entry(timestamp: .now, id: UUID()))
        nav.pop()
        #expect(nav.path(for: .journal).count == 1)
    }

    @Test
    func `Pop on empty path is a no-op`() {
        let nav = makeNavigator()
        nav.pop()
        #expect(nav.path(for: nav.selectedTab).isEmpty)
    }

    @Test
    func `popToRoot clears the current tab`() {
        let nav = makeNavigator(selectedTab: .journal)
        nav.push(.session(id: UUID()))
        nav.push(.entry(timestamp: .now, id: UUID()))
        nav.popToRoot()
        #expect(nav.path(for: .journal).isEmpty)
    }

    @Test
    func `popToRoot in one tab leaves others alone`() {
        let nav = makeNavigator(selectedTab: .journal)
        nav.push(.session(id: UUID()), in: .journal)
        nav.push(.substance(name: "MDMA"), in: .library)
        nav.popToRoot(in: .journal)
        #expect(nav.path(for: .journal).isEmpty)
        #expect(nav.path(for: .library).count == 1)
    }

    @Test
    func `pathBinding read and write round-trip through the navigator`() throws {
        let nav = makeNavigator(selectedTab: .insights)
        let binding = nav.pathBinding(for: .insights)
        binding.wrappedValue = try [.session(id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000010")))]
        #expect(nav.path(for: .insights).count == 1)
        try nav.push(.session(id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000020"))))
        #expect(binding.wrappedValue.count == 2)
    }

    // MARK: - Sheet stack

    @Test
    func `present appends to the sheet stack`() {
        let nav = makeNavigator()
        nav.present(.quickLog(routine: nil))
        nav.present(.colorPicker(substance: "MDMA"))
        #expect(nav.sheetStack.count == 2)
        #expect(nav.sheetStack.last == .colorPicker(substance: "MDMA", remaining: []))
    }

    @Test
    func `dismiss removes the top sheet`() {
        let nav = makeNavigator()
        nav.present(.quickLog(routine: nil))
        nav.present(.help)
        nav.dismiss()
        #expect(nav.sheetStack == [.quickLog(routine: nil)])
    }

    @Test
    func `dismiss on empty stack is a no-op`() {
        let nav = makeNavigator()
        nav.dismiss()
        #expect(nav.sheetStack.isEmpty)
    }

    @Test
    func `dismissAll empties the stack`() {
        let nav = makeNavigator()
        nav.present(.settings)
        nav.present(.help)
        nav.present(.quickLog(routine: nil))
        nav.dismissAll()
        #expect(nav.sheetStack.isEmpty)
    }

    @Test
    func `dismiss(_:) removes a specific sheet`() {
        let nav = makeNavigator()
        nav.present(.settings)
        nav.present(.help)
        nav.present(.quickLog(routine: nil))
        nav.dismiss(.help)
        #expect(nav.sheetStack == [.settings, .quickLog(routine: nil)])
    }

    @Test
    func `present with replacingTop swaps the top instead of nesting`() {
        let nav = makeNavigator()
        nav.present(.entryForm(prefill: nil))
        nav.present(.colorPicker(substance: "Caffeine"), replacingTop: true)
        #expect(nav.sheetStack.count == 1)
        #expect(nav.sheetStack.first == .colorPicker(substance: "Caffeine", remaining: []))
    }

    @Test
    func `present with replacingTop on empty stack appends`() {
        let nav = makeNavigator()
        nav.present(.quickLog(routine: nil), replacingTop: true)
        #expect(nav.sheetStack == [.quickLog(routine: nil)])
    }

    @Test
    func `truncateSheetStack to a depth trims deeper sheets`() {
        let nav = makeNavigator()
        nav.present(.settings)
        nav.present(.help)
        nav.present(.quickLog(routine: nil))
        nav.truncateSheetStack(to: 1)
        #expect(nav.sheetStack == [.settings])
    }

    @Test
    func `truncateSheetStack to a depth >= current size is a no-op`() {
        let nav = makeNavigator()
        nav.present(.quickLog(routine: nil))
        nav.truncateSheetStack(to: 5)
        #expect(nav.sheetStack == [.quickLog(routine: nil)])
    }

    @Test
    func `present beyond maxSheetDepth is dropped silently`() {
        let nav = makeNavigator()
        nav.present(.settings)
        nav.present(.help)
        nav.present(.quickLog(routine: nil))
        // We're at the cap (3). A fourth append must be dropped.
        nav.present(.sessionDetail)
        #expect(nav.sheetStack.count == AppNavigator.maxSheetDepth)
        #expect(nav.sheetStack.last == .quickLog(routine: nil))
    }

    @Test
    func `replacingTop still succeeds at maxSheetDepth`() {
        let nav = makeNavigator()
        nav.present(.settings)
        nav.present(.help)
        nav.present(.quickLog(routine: nil))
        nav.present(.sessionDetail, replacingTop: true)
        #expect(nav.sheetStack.count == AppNavigator.maxSheetDepth)
        #expect(nav.sheetStack.last == .sessionDetail)
    }

    @Test
    func `Setting snapshot clamps sheetStack to maxSheetDepth`() {
        let nav = makeNavigator()
        var snap = NavigatorSnapshot()
        snap.sheetStack = [.settings, .help, .quickLog(routine: nil), .sessionDetail, .entryForm(prefill: nil)]
        nav.snapshot = snap
        #expect(nav.sheetStack.count == AppNavigator.maxSheetDepth)
        // First N from the snapshot survive — deeper items are dropped.
        #expect(nav.sheetStack == [.settings, .help, .quickLog(routine: nil)])
    }

    // MARK: - Color picker queue (the Phase 3 bug fix)

    @Test
    func `Color picker queue advances via replacingTop, then dismisses when empty`() throws {
        let nav = makeNavigator()
        // Form presents itself, then on Save replaces with the first picker.
        nav.present(.entryForm(prefill: nil))
        nav.present(.colorPicker(substance: "A", remaining: ["B", "C"]), replacingTop: true)

        // Simulate the picker advancing the queue.
        guard case let .colorPicker(_, r1, _) = nav.sheetStack.last else {
            Issue.record("Expected color picker on top")
            return
        }
        try nav.present(.colorPicker(substance: #require(r1.first), remaining: Array(r1.dropFirst())), replacingTop: true)
        nav.present(.colorPicker(substance: "C", remaining: []), replacingTop: true)

        #expect(nav.sheetStack.count == 1)
        #expect(nav.sheetStack.last == .colorPicker(substance: "C", remaining: []))

        nav.dismiss()
        #expect(nav.sheetStack.isEmpty)
    }

    @Test
    func `dismissAll clears the whole chain (logging-flow completion)`() {
        let nav = makeNavigator()
        // Simulate QuickLog → From Library → EntryForm.
        nav.present(.quickLog(routine: nil))
        nav.present(.entryForm(prefill: EntryPrefillPayload(substance: "Caffeine", route: .oral, unit: "mg")))
        #expect(nav.sheetStack.count == 2)
        // The save handler for a new entry should land us back at root.
        nav.dismissAll()
        #expect(nav.sheetStack.isEmpty)
    }

    @Test
    func `colorPicker route propagates dismissAllOnComplete through Codable`() throws {
        let route = SheetRoute.colorPicker(substance: "A", remaining: ["B"], dismissAllOnComplete: true)
        let data = try JSONEncoder().encode(route)
        let decoded = try JSONDecoder().decode(SheetRoute.self, from: data)
        #expect(decoded == route)
        if case let .colorPicker(_, _, flag) = decoded {
            #expect(flag == true)
        } else {
            Issue.record("Expected color picker case")
        }
    }

    // MARK: - Snapshot

    @Test
    func `Snapshot reflects current navigator state`() {
        let nav = makeNavigator(selectedTab: .insights)
        nav.push(.substance(name: "Caffeine"), in: .library)
        nav.present(.quickLog(routine: nil))

        let snap = nav.snapshot
        #expect(snap.selectedTab == .insights)
        #expect(snap.paths[.library] == [.substance(name: "Caffeine")])
        #expect(snap.sheetStack == [.quickLog(routine: nil)])
    }

    @Test
    func `Setting snapshot replaces navigator state`() throws {
        let nav = makeNavigator()
        var snap = NavigatorSnapshot()
        snap.selectedTab = .tools
        snap.paths[.journal] = try [.session(id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000030")))]
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

    @Test
    func `Every AppTab encodes and decodes`() throws {
        for tab in AppTab.allCases {
            let decoded = try roundTrip(tab)
            #expect(decoded == tab)
        }
    }

    @Test(arguments: [
        PushRoute.session(id: UUID(uuidString: "00000000-0000-0000-0000-000000000040")!),
        PushRoute.entry(timestamp: Date(timeIntervalSince1970: 1_700_000_500), id: nil),
        PushRoute.entry(
            timestamp: Date(timeIntervalSince1970: 1_700_000_500),
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000060"),
        ),
        PushRoute.rampDown(timestamp: Date(timeIntervalSince1970: 1_700_000_600), id: nil),
        PushRoute.rampDown(
            timestamp: Date(timeIntervalSince1970: 1_700_000_600),
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000061"),
        ),
        PushRoute.substance(name: "LSD"),
        .libraryCategory(.stimulant),
        .libraryCategory(.psychedelic),
        .libraryTag("common"),
        .libraryFavorites,
    ])
    func `Each PushRoute case round-trips`(route: PushRoute) throws {
        #expect(try roundTrip(route) == route)
    }

    /// Pre-V4 payloads carry no `id` key — the synthesized Codable must decode
    /// them with `id == nil` (the timestamp-fallback contract for persisted
    /// snapshots and old deep links). Fixture dates are
    /// `timeIntervalSinceReferenceDate` seconds, JSONEncoder's default coding.
    @Test
    func `Pre-V4 entry payloads without an id still decode`() throws {
        let decoder = JSONDecoder()

        let oldEntry = Data(#"{"entry":{"timestamp":700000000}}"#.utf8)
        #expect(
            try decoder.decode(PushRoute.self, from: oldEntry)
                == .entry(timestamp: Date(timeIntervalSinceReferenceDate: 700_000_000), id: nil),
        )

        let oldRampDown = Data(#"{"rampDown":{"timestamp":700000000}}"#.utf8)
        #expect(
            try decoder.decode(PushRoute.self, from: oldRampDown)
                == .rampDown(timestamp: Date(timeIntervalSinceReferenceDate: 700_000_000), id: nil),
        )

        let oldEntryDetail = Data(#"{"entryDetail":{"timestamp":700000000}}"#.utf8)
        #expect(
            try decoder.decode(SheetRoute.self, from: oldEntryDetail)
                == .entryDetail(timestamp: Date(timeIntervalSinceReferenceDate: 700_000_000), id: nil),
        )
    }

    @Test(arguments: [
        SheetRoute.quickLog(routine: nil),
        .settings,
        .help,
        .onboarding,
        .sessionDetail,
        .entryDetail(timestamp: Date(timeIntervalSince1970: 100), id: nil),
        .entryDetail(
            timestamp: Date(timeIntervalSince1970: 100),
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000062"),
        ),
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
    func `Each SheetRoute case round-trips`(route: SheetRoute) throws {
        #expect(try roundTrip(route) == route)
    }

    @Test
    func `A full NavigatorSnapshot round-trips`() throws {
        let snap = try NavigatorSnapshot(
            selectedTab: .library,
            paths: [
                .journal: [
                    .session(id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000050"))),
                    .entry(
                        timestamp: Date(timeIntervalSince1970: 2),
                        id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000051")),
                    ),
                ],
                .library: [.substance(name: "DMT")],
            ],
            sheetStack: [
                .entryForm(prefill: EntryPrefillPayload(substance: "MDMA", route: .insufflation, unit: "mg")),
                .colorPicker(substance: "MDMA", remaining: ["Caffeine"]),
            ],
        )
        let decoded = try JSONDecoder().decode(NavigatorSnapshot.self, from: JSONEncoder().encode(snap))
        #expect(decoded == snap)
    }
}
