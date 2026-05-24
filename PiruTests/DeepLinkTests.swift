import Testing
import Foundation
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

    @Test("Tab-only URLs select the right tab with no sheet", arguments: [
        ("piru://journal", AppTab.journal),
        ("piru://library", .library),
        ("piru://tools", .tools),
        ("piru://insights", .insights),
        ("piru://search", .search),
    ])
    func tabSelection(url: String, expected: AppTab) {
        let outcome = decode(url)
        #expect(outcome?.tab == expected)
        #expect(outcome?.sheet == nil)
    }

    // MARK: - App-level sheets (preserve current tab)

    @Test("piru://quicklog presents QuickLog without switching tab")
    func quickLog() {
        let outcome = decode("piru://quicklog")
        #expect(outcome?.tab == nil) // preserves current
        #expect(outcome?.sheet == .quickLog)
    }

    @Test("piru://settings preserves current tab")
    func settings() {
        let outcome = decode("piru://settings")
        #expect(outcome?.tab == nil)
        #expect(outcome?.sheet == .settings)
    }

    @Test("piru://help preserves current tab")
    func help() {
        let outcome = decode("piru://help")
        #expect(outcome?.tab == nil)
        #expect(outcome?.sheet == .help)
    }

    @Test("?tab=library on an app-level sheet overrides preserve behaviour")
    func appLevelSheetWithTabOverride() {
        let outcome = decode("piru://quicklog?tab=library")
        #expect(outcome?.tab == .library)
        #expect(outcome?.sheet == .quickLog)
    }

    // MARK: - Journal-flow sheets (default to journal tab)

    @Test("piru://day lands on journal with session detail")
    func day() {
        let outcome = decode("piru://day")
        #expect(outcome?.tab == .journal)
        #expect(outcome?.sheet == .sessionDetail)
    }

    @Test("piru://entry/<timestamp> lands on journal with entry detail")
    func entryDetail() {
        let outcome = decode("piru://entry/1700000000")
        #expect(outcome?.tab == .journal)
        #expect(outcome?.sheet == .entryDetail(timestamp: Date(timeIntervalSince1970: 1_700_000_000)))
    }

    @Test("piru://entry without a timestamp returns nil")
    func entryMissingTimestamp() {
        #expect(decode("piru://entry") == nil)
    }

    @Test("piru://entry with garbage returns nil")
    func entryGarbageTimestamp() {
        #expect(decode("piru://entry/not-a-number") == nil)
    }

    @Test("piru://entryform without query presents a blank form")
    func entryFormBlank() {
        let outcome = decode("piru://entryform")
        #expect(outcome?.sheet == .entryForm(prefill: nil))
    }

    @Test("piru://entryform with all query params presents a prefilled form")
    func entryFormPrefilled() {
        let outcome = decode("piru://entryform?substance=MDMA&route=oral&unit=mg")
        let expectedPayload = EntryPrefillPayload(substance: "MDMA", route: .oral, unit: "mg")
        #expect(outcome?.sheet == .entryForm(prefill: expectedPayload))
    }

    @Test("entryform with a partial prefill query (missing route) ignores the prefill")
    func entryFormPartialPrefill() {
        let outcome = decode("piru://entryform?substance=MDMA&unit=mg")
        #expect(outcome?.sheet == .entryForm(prefill: nil))
    }

    // MARK: - Medications

    @Test("piru://meds/<category> presents the medication log")
    func medsCategory() {
        let outcome = decode("piru://meds/Antidepressants")
        #expect(outcome?.tab == .journal)
        #expect(outcome?.sheet == .dailyDoseLog(category: "Antidepressants"))
    }

    @Test("piru://meds with no category returns nil")
    func medsMissingCategory() {
        #expect(decode("piru://meds") == nil)
    }

    // MARK: - Unsupported URLs

    @Test("Unknown scheme returns nil")
    func unknownScheme() {
        #expect(decode("https://example.com/foo") == nil)
    }

    @Test("Unknown host returns nil")
    func unknownHost() {
        #expect(decode("piru://nonsense") == nil)
    }

    @Test("URL with no host returns nil")
    func noHost() {
        #expect(decode("piru://") == nil)
    }

    // MARK: - Applying outcomes preserves unrelated state

    @MainActor
    @Test("Applying a sheet-only outcome does not change the selected tab")
    func applyPreservesTab() {
        let nav = AppNavigator(selectedTab: .library, storage: makeIsolatedDefaults())
        nav.apply(DeepLinkOutcome(tab: nil, sheet: .quickLog))
        #expect(nav.selectedTab == .library)
        #expect(nav.sheetStack == [.quickLog])
    }

    @MainActor
    @Test("Applying a tab-only outcome does not present a sheet")
    func applyTabOnly() {
        let nav = AppNavigator(selectedTab: .journal, storage: makeIsolatedDefaults())
        nav.apply(DeepLinkOutcome(tab: .insights, sheet: nil))
        #expect(nav.selectedTab == .insights)
        #expect(nav.sheetStack.isEmpty)
    }

    @MainActor
    @Test("Applying a tab+sheet outcome sets both")
    func applyBoth() {
        let nav = AppNavigator(selectedTab: .library, storage: makeIsolatedDefaults())
        nav.apply(DeepLinkOutcome(tab: .journal, sheet: .sessionDetail))
        #expect(nav.selectedTab == .journal)
        #expect(nav.sheetStack == [.sessionDetail])
    }

    // MARK: - Encoding (snapshot → URL)

    @Test("Encoding a tab-only snapshot produces piru://<tab>")
    func encodeTab() {
        let snap = NavigatorSnapshot(selectedTab: .library)
        let url = DeepLink.encode(snap)
        #expect(url?.absoluteString == "piru://library")
    }

    @Test("Encoding a quicklog sheet snapshot")
    func encodeQuickLog() {
        let snap = NavigatorSnapshot(selectedTab: .journal, sheetStack: [.quickLog])
        #expect(DeepLink.encode(snap)?.absoluteString == "piru://quicklog")
    }

    @Test("Encoding an entry detail snapshot")
    func encodeEntryDetail() {
        let ts = Date(timeIntervalSince1970: 1_700_000_500)
        let snap = NavigatorSnapshot(selectedTab: .journal, sheetStack: [.entryDetail(timestamp: ts)])
        let url = DeepLink.encode(snap)
        #expect(url?.absoluteString == "piru://entry/1700000500.0")
    }

    @Test("Encoding a non-default tab adds a tab query param")
    func encodeNonDefaultTab() {
        let snap = NavigatorSnapshot(selectedTab: .library, sheetStack: [.quickLog])
        let url = DeepLink.encode(snap)
        #expect(url?.absoluteString.contains("tab=library") == true)
    }

    @Test("Encoding an unrepresentable sheet returns nil")
    func encodeUnrepresentable() {
        let snap = NavigatorSnapshot(
            selectedTab: .journal,
            sheetStack: [.colorPicker(substance: "MDMA")]
        )
        #expect(DeepLink.encode(snap) == nil)
    }

    // MARK: - Round-trip (encode → decode produces matching outcome)

    @Test("Encode → decode produces an outcome that reflects the snapshot")
    func roundTripTabOnly() {
        let snap = NavigatorSnapshot(selectedTab: .insights)
        guard let url = DeepLink.encode(snap), let outcome = DeepLink.decode(url) else {
            Issue.record("Expected encode+decode to succeed")
            return
        }
        #expect(outcome.tab == .insights)
        #expect(outcome.sheet == nil)
    }

    @Test("Round trip through a journal-flow sheet preserves the sheet and tab")
    func roundTripJournalSheet() {
        let snap = NavigatorSnapshot(selectedTab: .journal, sheetStack: [.sessionDetail])
        guard let url = DeepLink.encode(snap), let outcome = DeepLink.decode(url) else {
            Issue.record("Expected encode+decode to succeed")
            return
        }
        #expect(outcome.tab == .journal)
        #expect(outcome.sheet == .sessionDetail)
    }

    @Test("Round trip through an app-level sheet preserves the sheet (and honors tab override)")
    func roundTripAppSheet() {
        let snap = NavigatorSnapshot(selectedTab: .library, sheetStack: [.quickLog])
        guard let url = DeepLink.encode(snap), let outcome = DeepLink.decode(url) else {
            Issue.record("Expected encode+decode to succeed")
            return
        }
        #expect(outcome.tab == .library)
        #expect(outcome.sheet == .quickLog)
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
