import Testing
import Foundation
@testable import Piru

@Suite("DeepLink")
struct DeepLinkTests {

    // MARK: - Helpers

    private func decode(_ string: String) -> NavigatorSnapshot? {
        guard let url = URL(string: string) else {
            Issue.record("Invalid URL: \(string)")
            return nil
        }
        return DeepLink.decode(url)
    }

    // MARK: - Tab selection

    @Test("Tab-only URLs select the right tab", arguments: [
        ("piru://journal", AppTab.journal),
        ("piru://library", .library),
        ("piru://tools", .tools),
        ("piru://insights", .insights),
        ("piru://search", .search),
    ])
    func tabSelection(url: String, expected: AppTab) {
        let snap = decode(url)
        #expect(snap?.selectedTab == expected)
        #expect(snap?.sheetStack.isEmpty == true)
    }

    // MARK: - App-level sheets

    @Test("piru://quicklog presents the QuickLog sheet")
    func quickLog() {
        let snap = decode("piru://quicklog")
        #expect(snap?.sheetStack == [.quickLog])
    }

    @Test("piru://settings presents Settings")
    func settings() {
        #expect(decode("piru://settings")?.sheetStack == [.settings])
    }

    @Test("piru://help presents Help")
    func help() {
        #expect(decode("piru://help")?.sheetStack == [.help])
    }

    // MARK: - Entry-flow sheets

    @Test("piru://day presents the session detail on journal")
    func day() {
        let snap = decode("piru://day")
        #expect(snap?.selectedTab == .journal)
        #expect(snap?.sheetStack == [.sessionDetail])
    }

    @Test("piru://entry/<timestamp> presents the entry detail")
    func entryDetail() {
        let snap = decode("piru://entry/1700000000")
        #expect(snap?.selectedTab == .journal)
        #expect(snap?.sheetStack == [.entryDetail(timestamp: Date(timeIntervalSince1970: 1_700_000_000))])
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
        let snap = decode("piru://entryform")
        #expect(snap?.sheetStack == [.entryForm(prefill: nil)])
    }

    @Test("piru://entryform with all query params presents a prefilled form")
    func entryFormPrefilled() {
        let snap = decode("piru://entryform?substance=MDMA&route=oral&unit=mg")
        let expectedPayload = EntryPrefillPayload(substance: "MDMA", route: .oral, unit: "mg")
        #expect(snap?.sheetStack == [.entryForm(prefill: expectedPayload)])
    }

    @Test("entryform with a partial prefill query (missing route) ignores the prefill")
    func entryFormPartialPrefill() {
        let snap = decode("piru://entryform?substance=MDMA&unit=mg")
        #expect(snap?.sheetStack == [.entryForm(prefill: nil)])
    }

    // MARK: - Medications

    @Test("piru://meds/<category> presents the medication log")
    func medsCategory() {
        let snap = decode("piru://meds/Antidepressants")
        #expect(snap?.sheetStack == [.dailyDoseLog(category: "Antidepressants")])
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

    // MARK: - Encoding

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

    // MARK: - Round-trip

    @Test("Encode → decode preserves snapshot", arguments: [
        NavigatorSnapshot(selectedTab: .journal),
        NavigatorSnapshot(selectedTab: .library),
        NavigatorSnapshot(selectedTab: .tools),
        NavigatorSnapshot(selectedTab: .insights),
        NavigatorSnapshot(selectedTab: .search),
        NavigatorSnapshot(selectedTab: .journal, sheetStack: [.quickLog]),
        NavigatorSnapshot(selectedTab: .journal, sheetStack: [.settings]),
        NavigatorSnapshot(selectedTab: .journal, sheetStack: [.help]),
        NavigatorSnapshot(selectedTab: .journal, sheetStack: [.sessionDetail]),
        NavigatorSnapshot(selectedTab: .journal, sheetStack: [.entryDetail(timestamp: Date(timeIntervalSince1970: 1_700_000_500))]),
        NavigatorSnapshot(selectedTab: .journal, sheetStack: [.entryForm(prefill: nil)]),
        NavigatorSnapshot(selectedTab: .journal, sheetStack: [.entryForm(prefill: EntryPrefillPayload(substance: "LSD", route: .oral, unit: "µg"))]),
        NavigatorSnapshot(selectedTab: .journal, sheetStack: [.dailyDoseLog(category: "Antidepressants")]),
    ])
    func roundTrip(snapshot: NavigatorSnapshot) {
        guard let url = DeepLink.encode(snapshot) else {
            Issue.record("Expected encode to succeed for \(snapshot)")
            return
        }
        let decoded = DeepLink.decode(url)
        #expect(decoded == snapshot)
    }
}
