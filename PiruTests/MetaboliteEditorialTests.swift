import Foundation
import Testing
@testable import Piru

/// ``MetaboliteEditorial`` is app-voice localized copy keyed by a (parent, metabolite) pair that only
/// the bundled DB defines, so its keys can go stale silently: a curator renaming a `metabolite_name`,
/// or a substance losing its metabolism row, would leave a sentence that never renders and nothing
/// would say so.
///
/// These are the drift gate. The copy stays in Swift — `metabolism.notes` beside it holds the
/// enrichment layer's quoted paper text with citations, a different register, and 15 of these 21 pairs
/// already carry one that moving app copy in would overwrite — so what the DB owes it is that every
/// key still resolves to a real row.
@Suite("MetaboliteEditorial")
@MainActor
struct MetaboliteEditorialTests {
    let store: SubstanceStore

    init() {
        store = SubstanceStore.shared
    }

    @Test
    func `Every curated note resolves to a metabolism row in the bundled DB`() {
        for entry in MetaboliteEditorial.notes {
            let rows = store.metabolism(forSubstanceName: entry.parent)
            #expect(!rows.isEmpty, "\(entry.parent) carries no metabolism rows at all")
            let matched = rows.contains { row in
                guard let name = row.metaboliteName else { return false }
                return MetaboliteEditorial.divergentNote(parent: entry.parent, metabolite: name) != nil
            }
            #expect(matched, "no \(entry.parent) row names \(entry.metabolite)")
        }
    }

    @Test
    func `Each key resolves to its own note, not a neighbor's`() {
        // The matcher is a loose substring compare, so a metabolite whose name
        // contains another's would silently render the wrong sentence.
        for entry in MetaboliteEditorial.notes {
            let resolved = MetaboliteEditorial.divergentNote(parent: entry.parent, metabolite: entry.metabolite)
            #expect(
                resolved.map { String(localized: $0) } == String(localized: entry.note),
                "\(entry.parent) → \(entry.metabolite) resolved to another entry's note",
            )
        }
    }

    @Test
    func `No two entries claim the same parent and metabolite`() {
        let keys = MetaboliteEditorial.notes.map { "\($0.parent.lowercased())|\($0.metabolite.lowercased())" }
        #expect(Set(keys).count == keys.count)
    }

    @Test
    func `A metabolite with no curated note resolves to nothing`() {
        #expect(MetaboliteEditorial.divergentNote(parent: "Tramadol", metabolite: "N-desmethyltramadol") == nil)
        #expect(MetaboliteEditorial.divergentNote(parent: "Caffeine", metabolite: "paraxanthine") == nil)
    }

    @Test
    func `Both polymorphic enzymes still occur in real metabolism cells`() {
        // The genetics line is gated on a two-name list rather than on a
        // substance's own `pharmacogenetics` rows, deliberately — see the
        // prohibition on `Threshold.polymorphicEnzymes`. What that costs is a
        // name that could go stale against a renamed enzyme cell, so gate it:
        // each name must still be reachable, or the callout silently stops.
        let cells = { (parent: String) in
            self.store.metabolism(forSubstanceName: parent).map(\.enzyme).joined().uppercased()
        }
        #expect(cells("Tramadol").contains("CYP2D6"))
        #expect(cells("Amitriptyline").contains("CYP2C19"))
        #expect(ActiveMetabolite.Threshold.polymorphicEnzymes == ["CYP2D6", "CYP2C19"])
    }

    @Test
    func `The curator's parenthetical synonyms still match`() {
        // The DB stores "O-desmethyltramadol (M1)" and "MDA (3,4-methylenedioxy...)";
        // the note is keyed on the bare name and must survive both forms.
        #expect(MetaboliteEditorial.divergentNote(parent: "Tramadol", metabolite: "O-desmethyltramadol (M1)") != nil)
        #expect(MetaboliteEditorial.divergentNote(parent: "MDMA", metabolite: "MDA (3,4-methylenedioxyamphetamine)") != nil)
    }
}
