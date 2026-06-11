import Foundation
import Testing
@testable import Piru

@Suite("DeepLink")
struct DeepLinkTests {
    // MARK: - Helpers

    private func decode(_ string: String) -> DeepLinkOutcome? {
        guard let url = URL(string: string) else {
            Issue.record("Invalid URL: \(string)")
            return nil
        }
        return DeepLink.decode(url)
    }

    // MARK: - Tab selection

    @Test(arguments: [
        ("piru://journal", AppTab.journal),
        ("piru://library", .library),
        ("piru://tools", .tools),
        ("piru://insights", .insights),
        ("piru://search", .search),
    ])
    func `Tab-only URLs select the right tab with no sheet`(url: String, expected: AppTab) {
        let outcome = decode(url)
        #expect(outcome?.tab == expected)
        #expect(outcome?.sheet == nil)
    }

    // MARK: - App-level sheets (preserve current tab)

    @Test
    func `piru://quicklog presents QuickLog without switching tab`() {
        let outcome = decode("piru://quicklog")
        #expect(outcome?.tab == nil) // preserves current
        #expect(outcome?.sheet == .quickLog(routine: nil))
    }

    @Test
    func `piru://quicklog?routine= carries the routine to pre-stage`() {
        let outcome = decode("piru://quicklog?routine=Pre-workout")
        #expect(outcome?.tab == nil)
        #expect(outcome?.sheet == .quickLog(routine: "Pre-workout"))
    }

    @Test
    func `quickLog with a routine round-trips through encode`() {
        let snap = NavigatorSnapshot(selectedTab: .journal, sheetStack: [.quickLog(routine: "Night Meds")])
        let url = DeepLink.encode(snap)
        #expect(url != nil)
        let outcome = url.flatMap(DeepLink.decode)
        #expect(outcome?.sheet == .quickLog(routine: "Night Meds"))
    }

    @Test
    func `piru://settings preserves current tab`() {
        let outcome = decode("piru://settings")
        #expect(outcome?.tab == nil)
        #expect(outcome?.sheet == .settings)
    }

    @Test
    func `piru://help preserves current tab`() {
        let outcome = decode("piru://help")
        #expect(outcome?.tab == nil)
        #expect(outcome?.sheet == .help)
    }

    @Test
    func `?tab=library on an app-level sheet overrides preserve behaviour`() {
        let outcome = decode("piru://quicklog?tab=library")
        #expect(outcome?.tab == .library)
        #expect(outcome?.sheet == .quickLog(routine: nil))
    }

    // MARK: - Journal-flow sheets (default to journal tab)

    @Test
    func `piru://day lands on journal with session detail`() {
        let outcome = decode("piru://day")
        #expect(outcome?.tab == .journal)
        #expect(outcome?.sheet == .sessionDetail)
    }

    @Test
    func `piru://entry/<timestamp> lands on journal with entry detail (id-less fallback)`() {
        // Timestamp-only URLs — pre-V4 links and everything the Live Activity
        // emits — must keep decoding, with a nil id (resolved by the ±2 s
        // window downstream).
        let outcome = decode("piru://entry/1700000000")
        #expect(outcome?.tab == .journal)
        #expect(outcome?.sheet == .entryDetail(timestamp: Date(timeIntervalSince1970: 1_700_000_000), id: nil))
    }

    @Test
    func `piru://entry with an id query carries the stable id`() throws {
        let id = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000003"))
        let outcome = decode("piru://entry/1700000000?id=\(id.uuidString)")
        #expect(outcome?.sheet == .entryDetail(timestamp: Date(timeIntervalSince1970: 1_700_000_000), id: id))
    }

    @Test
    func `piru://entry with a malformed id decodes with nil id`() {
        let outcome = decode("piru://entry/1700000000?id=not-a-uuid")
        #expect(outcome?.sheet == .entryDetail(timestamp: Date(timeIntervalSince1970: 1_700_000_000), id: nil))
    }

    @Test
    func `piru://entry without a timestamp returns nil`() {
        #expect(decode("piru://entry") == nil)
    }

    @Test
    func `piru://entry with garbage returns nil`() {
        #expect(decode("piru://entry/not-a-number") == nil)
    }

    @Test
    func `piru://entryform without query presents a blank form`() {
        let outcome = decode("piru://entryform")
        #expect(outcome?.sheet == .entryForm(prefill: nil))
    }

    @Test
    func `piru://entryform with all query params presents a prefilled form`() {
        let outcome = decode("piru://entryform?substance=MDMA&route=oral&unit=mg")
        let expectedPayload = EntryPrefillPayload(substance: "MDMA", route: .oral, unit: "mg")
        #expect(outcome?.sheet == .entryForm(prefill: expectedPayload))
    }

    @Test
    func `entryform with a partial prefill query (missing route) ignores the prefill`() {
        let outcome = decode("piru://entryform?substance=MDMA&unit=mg")
        #expect(outcome?.sheet == .entryForm(prefill: nil))
    }

    // MARK: - Medications

    @Test
    func `piru://meds/<category> presents the medication log`() {
        let outcome = decode("piru://meds/Antidepressants")
        #expect(outcome?.tab == .journal)
        #expect(outcome?.sheet == .dailyDoseLog(category: "Antidepressants"))
    }

    @Test
    func `piru://meds with no category returns nil`() {
        #expect(decode("piru://meds") == nil)
    }

    // MARK: - Unsupported URLs

    @Test
    func `Unknown scheme returns nil`() {
        #expect(decode("https://example.com/foo") == nil)
    }

    @Test
    func `Unknown host returns nil`() {
        #expect(decode("piru://nonsense") == nil)
    }

    @Test
    func `URL with no host returns nil`() {
        #expect(decode("piru://") == nil)
    }

    // MARK: - Applying outcomes preserves unrelated state

    @MainActor
    @Test
    func `Applying a sheet-only outcome does not change the selected tab`() {
        let nav = AppNavigator(selectedTab: .library, storage: makeIsolatedDefaults())
        nav.apply(DeepLinkOutcome(tab: nil, sheet: .quickLog(routine: nil)))
        #expect(nav.selectedTab == .library)
        #expect(nav.sheetStack == [.quickLog(routine: nil)])
    }

    @MainActor
    @Test
    func `Applying a tab-only outcome does not present a sheet`() {
        let nav = AppNavigator(selectedTab: .journal, storage: makeIsolatedDefaults())
        nav.apply(DeepLinkOutcome(tab: .insights, sheet: nil))
        #expect(nav.selectedTab == .insights)
        #expect(nav.sheetStack.isEmpty)
    }

    @MainActor
    @Test
    func `Applying a tab+sheet outcome sets both`() {
        let nav = AppNavigator(selectedTab: .library, storage: makeIsolatedDefaults())
        nav.apply(DeepLinkOutcome(tab: .journal, sheet: .sessionDetail))
        #expect(nav.selectedTab == .journal)
        #expect(nav.sheetStack == [.sessionDetail])
    }

    // MARK: - Encoding (snapshot → URL)

    @Test
    func `Encoding a tab-only snapshot produces piru://<tab>`() {
        let snap = NavigatorSnapshot(selectedTab: .library)
        let url = DeepLink.encode(snap)
        #expect(url?.absoluteString == "piru://library")
    }

    @Test
    func `Encoding a quicklog sheet snapshot`() {
        let snap = NavigatorSnapshot(selectedTab: .journal, sheetStack: [.quickLog(routine: nil)])
        #expect(DeepLink.encode(snap)?.absoluteString == "piru://quicklog")
    }

    @Test
    func `Encoding an id-less entry detail snapshot`() {
        let ts = Date(timeIntervalSince1970: 1_700_000_500)
        let snap = NavigatorSnapshot(selectedTab: .journal, sheetStack: [.entryDetail(timestamp: ts, id: nil)])
        let url = DeepLink.encode(snap)
        #expect(url?.absoluteString == "piru://entry/1700000500.0")
    }

    @Test
    func `Encoding an entry detail snapshot carries the id and round-trips`() throws {
        let ts = Date(timeIntervalSince1970: 1_700_000_500)
        let id = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000004"))
        let snap = NavigatorSnapshot(selectedTab: .journal, sheetStack: [.entryDetail(timestamp: ts, id: id)])
        let url = try #require(DeepLink.encode(snap))
        #expect(url.absoluteString == "piru://entry/1700000500.0?id=\(id.uuidString)")
        let outcome = DeepLink.decode(url)
        #expect(outcome?.sheet == .entryDetail(timestamp: ts, id: id))
    }

    @Test
    func `Encoding a non-default tab adds a tab query param`() {
        let snap = NavigatorSnapshot(selectedTab: .library, sheetStack: [.quickLog(routine: nil)])
        let url = DeepLink.encode(snap)
        #expect(url?.absoluteString.contains("tab=library") == true)
    }

    @Test
    func `Encoding an unrepresentable sheet returns nil`() {
        let snap = NavigatorSnapshot(
            selectedTab: .journal,
            sheetStack: [.colorPicker(substance: "MDMA")],
        )
        #expect(DeepLink.encode(snap) == nil)
    }

    // MARK: - Round-trip (encode → decode produces matching outcome)

    @Test
    func `Encode → decode produces an outcome that reflects the snapshot`() {
        let snap = NavigatorSnapshot(selectedTab: .insights)
        guard let url = DeepLink.encode(snap), let outcome = DeepLink.decode(url) else {
            Issue.record("Expected encode+decode to succeed")
            return
        }
        #expect(outcome.tab == .insights)
        #expect(outcome.sheet == nil)
    }

    @Test
    func `Round trip through a journal-flow sheet preserves the sheet and tab`() {
        let snap = NavigatorSnapshot(selectedTab: .journal, sheetStack: [.sessionDetail])
        guard let url = DeepLink.encode(snap), let outcome = DeepLink.decode(url) else {
            Issue.record("Expected encode+decode to succeed")
            return
        }
        #expect(outcome.tab == .journal)
        #expect(outcome.sheet == .sessionDetail)
    }

    @Test
    func `Round trip through an app-level sheet preserves the sheet (and honors tab override)`() {
        let snap = NavigatorSnapshot(selectedTab: .library, sheetStack: [.quickLog(routine: nil)])
        guard let url = DeepLink.encode(snap), let outcome = DeepLink.decode(url) else {
            Issue.record("Expected encode+decode to succeed")
            return
        }
        #expect(outcome.tab == .library)
        #expect(outcome.sheet == .quickLog(routine: nil))
    }
}

// MARK: - Helpers

@MainActor
private func makeIsolatedDefaults() -> UserDefaults {
    let suite = "DeepLinkTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}
