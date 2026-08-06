import Foundation
import SQLite3
import Testing
@testable import Piru

/// Phase 0 — curated `popularAliases` + cited `misconceptions` (MythBust) decode
/// and their surfacing on the resolved detail `Substance`.
@Suite("Substance misconceptions & popular aliases")
struct SubstanceMisconceptionsTests {
    // MARK: - MythBust JSON-blob decode (the pipeline → SubstanceStore contract)

    /// The exact shape `pipeline/build/sqlite.py::build_misconceptions_json`
    /// writes into `substances.misconceptions`.
    private static let blob = #"""
    [
      {
        "claim": "It burns holes in your brain",
        "correction": "No. Human imaging shows a **reversible** downregulation, not lesions.",
        "citations": [
          {"citation": {"pmid": 26855234}, "role": "refutes", "note": "SERT meta-analysis"},
          {"citation": {"pmid": 12970544}, "role": "retractedSource", "note": "retracted 2003"},
          {"citation": {"url": "Some free-text label"}, "role": "refutes"}
        ],
        "pullQuote": {"text": "An outrageous scandal.", "attribution": "A pharmacologist"}
      },
      {
        "claim": "A myth with no quote",
        "correction": "Corrected.",
        "citations": [{"citation": {"doi": "10.1000/x"}, "role": "dataset"}]
      }
    ]
    """#

    @Test
    func `MythBust blob decodes into structured value types`() throws {
        let data = try #require(Self.blob.data(using: .utf8))
        let myths = try JSONDecoder().decode([MythBust].self, from: data)

        #expect(myths.count == 2)
        let first = myths[0]
        #expect(first.claim == "It burns holes in your brain")
        #expect(first.correction.contains("**reversible**"))
        #expect(first.citations.count == 3)
        #expect(first.pullQuote?.attribution == "A pharmacologist")

        // Roles decode from their raw values.
        #expect(first.citations[0].role == .refutes)
        #expect(first.citations[1].role == .retractedSource)
        #expect(first.citations[2].note == nil)
        #expect(myths[1].citations[0].role == .dataset)
        #expect(myths[1].pullQuote == nil)
    }

    @Test
    func `Myth citations resolve tappable links only for real identifiers`() throws {
        let data = try #require(Self.blob.data(using: .utf8))
        let myths = try JSONDecoder().decode([MythBust].self, from: data)

        // A PMID citation is tappable...
        #expect(myths[0].citations[0].citation.resolvedURL != nil)
        // ...the retraction-notice PMID is tappable (we link the retraction, not the paper)...
        #expect(myths[0].citations[1].citation.resolvedURL != nil)
        // ...but a free-text label (stored in `url` without a scheme) is NOT a link.
        #expect(myths[0].citations[2].citation.resolvedURL == nil)
        #expect(myths[0].citations[2].citation.label == "Some free-text label")
    }

    @Test
    func `Missing optional keys decode to defaults`() throws {
        // note + pullQuote absent; role present. Mirrors the minimal pipeline row.
        let minimal = #"[{"claim":"C","correction":"K","citations":[{"citation":{"pmid":1},"role":"refutes"}]}]"#
        let myths = try JSONDecoder().decode([MythBust].self, from: #require(minimal.data(using: .utf8)))
        #expect(myths.count == 1)
        #expect(myths[0].pullQuote == nil)
        #expect(myths[0].citations[0].note == nil)
    }

    // MARK: - Surfacing on the resolved detail Substance (bundled DB)

    @Test
    @MainActor
    func `MDMA resolves its curated popular aliases and misconceptions`() throws {
        let mdma = try #require(
            SubstanceStore.shared.lookup("MDMA"),
            "MDMA missing from bundled DB",
        )

        #expect(mdma.popularAliases == ["Ecstasy", "Molly", "E"])

        #expect(mdma.misconceptions.count == 3)
        let claims = mdma.misconceptions.map(\.claim)
        #expect(claims.contains("It burns holes in your brain"))

        // Every curated myth carries at least one citation (the authoring contract).
        for myth in mdma.misconceptions {
            #expect(!myth.citations.isEmpty, "Uncited myth would be a bare counter-assertion")
        }

        // The retraction story: exactly one retractedSource, and it points at the
        // retraction notice (a resolvable PubMed link), never a dead reference.
        let retracted = mdma.misconceptions
            .flatMap(\.citations)
            .filter { $0.role == .retractedSource }
        #expect(retracted.count == 1)
        #expect(retracted.first?.citation.resolvedURL != nil)

        // The flagship pull-quote survives the round-trip.
        #expect(mdma.misconceptions.contains { $0.pullQuote != nil })
    }

    @Test
    @MainActor
    func `A substance without curated content has empty editorial arrays`() throws {
        // Caffeine is popular but carries no curated misconceptions/popularAliases
        // — the sections are correctly absent (empty), not a decode failure.
        let caffeine = try #require(
            SubstanceStore.shared.lookup("Caffeine"),
            "Caffeine missing from bundled DB",
        )
        #expect(caffeine.misconceptions.isEmpty)
        #expect(caffeine.popularAliases.isEmpty)
    }

    // MARK: - B1 regression: an older DB predating the editorial columns

    @Test
    @MainActor
    func `A substance DB missing the editorial columns still resolves`() throws {
        // A schema-6 DB applied via opt-in OTA *before* popular_aliases /
        // misconceptions existed lacks those columns. A reader that named them
        // unconditionally would throw `no such column` on every row and blank
        // the whole detail surface after an app update. The resolve probes for
        // the columns and degrades the fields to empty when absent.
        let fm = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("piru-b1-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let bundled = try #require(
            Bundle(for: SubstanceStore.self).url(forResource: "piru-substances", withExtension: "sqlite"),
            "Bundled piru-substances.sqlite missing from the test host bundle",
        )
        let legacyDB = tempDir.appendingPathComponent("legacy.sqlite")
        try fm.copyItem(at: bundled, to: legacyDB)

        // Drop an editorial column to reproduce the pre-column schema. Each
        // editorial column is probed independently, so dropping one leaves the
        // others still loadable — the dropped column degrades to its empty
        // default while existing columns resolve normally.
        var handle: OpaquePointer?
        #expect(sqlite3_open(legacyDB.path, &handle) == SQLITE_OK)
        var errmsg: UnsafeMutablePointer<CChar>?
        let dropped = sqlite3_exec(handle, "ALTER TABLE substances DROP COLUMN popular_aliases", nil, nil, &errmsg)
        let detail = errmsg.map { String(cString: $0) } ?? "ok"
        sqlite3_free(errmsg)
        #expect(dropped == SQLITE_OK, "Failed to drop popular_aliases: \(detail)")
        sqlite3_close(handle)

        let store = SubstanceStore(
            substancesDBURL: legacyDB,
            userPrefsDBURL: tempDir.appendingPathComponent("prefs.sqlite"),
            prewarmsAllCache: false,
        )

        // The detail surface still resolves — MDMA comes back (not nil). The
        // *dropped* column degrades to empty; the remaining columns load fine.
        let mdma = try #require(
            store.lookup("MDMA"),
            "A column-less DB must still resolve substances",
        )
        #expect(mdma.popularAliases.isEmpty)
        // And an ordinary field still resolves, proving the row loaded fully.
        #expect(!mdma.aliases.isEmpty)
    }
}
