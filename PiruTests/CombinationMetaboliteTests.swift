import Foundation
import Testing
@testable import Piru

/// The pair-generated active species (`combination_metabolites` + its precursor slots), and the
/// `metabolism.conditional_combination_id` flag that keeps them off a parent's own page.
///
/// The definitions are database rows, so these gate the rows: that every combination decodes and has
/// copy, that a combination is genuinely a *pair* (two non-empty slots), that its precursors name
/// substances the app carries, and that a conditional metabolism row exists only for a declared
/// combination.
@Suite("CombinationMetabolite")
@MainActor
struct CombinationMetaboliteTests {
    let store: SubstanceStore
    let catalog: [CombinationMetabolite.Definition]

    init() {
        store = SubstanceStore.shared
        catalog = SubstanceStore.shared.combinationMetabolites()
    }

    // MARK: - The curated table itself

    @Test
    func `Every curated combination decodes and every combination has copy`() {
        // Both directions: a row with no `CombinationID` case is dropped at load and
        // vanishes silently; a case with no row is copy for something that no longer
        // ships. The readout is two sentences, so neither half can go missing.
        #expect(Set(catalog.map(\.id)) == Set(CombinationMetabolite.CombinationID.allCases))
    }

    @Test
    func `A combination is a pair — at least two non-empty precursor slots`() {
        // With one slot the species would be claimed to form whenever that single
        // drug is onboard, which is exactly the unconditional metabolite this table
        // exists to distinguish itself from.
        for definition in catalog {
            #expect(definition.precursors.count >= 2, "\(definition.id.rawValue)")
            for (slot, matchers) in definition.precursors.enumerated() {
                #expect(!matchers.isEmpty, "\(definition.id.rawValue) slot \(slot) is empty")
                #expect(matchers.allSatisfy { $0 == $0.lowercased() }, "\(definition.id.rawValue) slot \(slot)")
            }
        }
    }

    @Test
    func `Every precursor slot names at least one substance the app carries`() {
        // A slot whose names resolve to nothing can never be satisfied by a logged
        // dose, so the combination would be permanently unreachable.
        for definition in catalog {
            for (slot, matchers) in definition.precursors.enumerated() {
                let resolves = matchers.contains { SubstanceLibrary.lookup($0) != nil }
                #expect(resolves, "\(definition.id.rawValue) slot \(slot) resolves no substance")
            }
        }
    }

    // MARK: - Formation

    @Test
    func `Cocaine + ethanol forms cocaethylene`() {
        let formed = CombinationMetabolite.formed(among: ["Cocaine", "Ethanol"], catalog: catalog)
        #expect(formed.count == 1)
        #expect(formed.first?.id == .cocaethylene)
    }

    @Test
    func `Common alcohol aliases also trigger formation`() {
        #expect(!CombinationMetabolite.formed(among: ["Cocaine", "Alcohol"], catalog: catalog).isEmpty)
        #expect(!CombinationMetabolite.formed(among: ["crack", "alcohol"], catalog: catalog).isEmpty)
    }

    @Test
    func `Matching is case- and whitespace-insensitive`() {
        #expect(!CombinationMetabolite.formed(among: ["  COCAINE ", "ETHANOL"], catalog: catalog).isEmpty)
    }

    @Test
    func `A single precursor alone forms nothing`() {
        #expect(CombinationMetabolite.formed(among: ["Cocaine"], catalog: catalog).isEmpty)
        #expect(CombinationMetabolite.formed(among: ["Ethanol"], catalog: catalog).isEmpty)
    }

    @Test
    func `Unrelated co-present substances do not trigger a false positive`() {
        #expect(CombinationMetabolite.formed(among: ["Caffeine", "Alcohol"], catalog: catalog).isEmpty)
        #expect(CombinationMetabolite.formed(among: ["Cocaine", "Caffeine", "Cannabis"], catalog: catalog).isEmpty)
    }

    @Test
    func `Empty input forms nothing`() {
        #expect(CombinationMetabolite.formed(among: [], catalog: catalog).isEmpty)
    }

    // MARK: - The conditional gate (these must never read as unconditional)

    @Test
    func `A conditional metabolism row only exists for a declared combination`() {
        // The flag is derived from this table by the build, so a row can only be
        // marked by a combination that exists — this gates that the derivation
        // stayed keyed to a declared id rather than drifting to a free-text name.
        let declared = Set(catalog.map(\.id))
        var flagged: [CombinationMetabolite.CombinationID: [String]] = [:]
        for definition in catalog {
            for slot in definition.precursors {
                for name in slot {
                    for row in store.metabolism(forSubstanceName: name) {
                        guard let id = row.conditionalCombinationID else { continue }
                        #expect(declared.contains(id), "\(name) is flagged for undeclared \(id.rawValue)")
                        flagged[id, default: []].append(row.metaboliteName ?? "")
                    }
                }
            }
        }
        // Cocaine's cocaethylene row is the case the guard exists for; if it stops
        // being flagged the species reappears as an unconditional "Also Active".
        #expect(flagged[.cocaethylene]?.isEmpty == false)
    }

    @Test
    func `The flagged species is the one its combination names`() {
        for definition in catalog {
            for slot in definition.precursors {
                for name in slot {
                    let rows = store.metabolism(forSubstanceName: name)
                        .filter { $0.conditionalCombinationID == definition.id }
                    for row in rows {
                        let metabolite = (row.metaboliteName ?? "").lowercased()
                        #expect(
                            metabolite.hasPrefix(definition.metaboliteName.lowercased()),
                            "\(name): \(metabolite) flagged as \(definition.id.rawValue)",
                        )
                    }
                }
            }
        }
    }

    @Test
    func `A combination species never reaches the parent's Also Active fold`() {
        // The product invariant behind the flag: cocaethylene forms while ethanol is
        // present, not whenever cocaine is, so cocaine's own page must not list it.
        let folded = SubstanceDetailModel.foldActiveMetabolites(
            from: store.metabolism(forSubstanceName: "Cocaine"),
        )
        #expect(!folded.contains { $0.name.lowercased().contains("cocaethylene") })
        // …and the filter reaches only flagged rows: an unconditional active
        // metabolite still folds normally.
        let tramadol = SubstanceDetailModel.foldActiveMetabolites(
            from: store.metabolism(forSubstanceName: "Tramadol"),
        )
        #expect(tramadol.contains { $0.name.lowercased().contains("desmethyltramadol") })
    }

    // MARK: - Temporal gate

    private static func onboard(_ name: String, at start: Double, hours: Double) -> CombinationMetabolite.Onboard {
        CombinationMetabolite.Onboard(
            name: name,
            interval: DateInterval(start: Date(timeIntervalSince1970: start * 3_600), duration: hours * 3_600),
        )
    }

    @Test
    func `Overlapping windows form the pair metabolite`() {
        let cocaine = Self.onboard("Cocaine", at: 0, hours: 2)
        let alcohol = Self.onboard("Alcohol", at: 1, hours: 4)
        let formed = CombinationMetabolite.formed(overlapping: cocaine, with: [alcohol], catalog: catalog)
        #expect(formed.map(\.id) == [.cocaethylene])
    }

    @Test
    func `A peer that has already cleared forms nothing`() {
        let alcohol = Self.onboard("Alcohol", at: 0, hours: 3)
        let cocaine = Self.onboard("Cocaine", at: 9, hours: 2)
        #expect(CombinationMetabolite.formed(overlapping: cocaine, with: [alcohol], catalog: catalog).isEmpty)
    }

    @Test
    func `Methylphenidate brands overlapping alcohol form ethylphenidate`() {
        let concerta = Self.onboard("Concerta", at: 0, hours: 12)
        let beer = Self.onboard("Ethanol", at: 6, hours: 3)
        let formed = CombinationMetabolite.formed(overlapping: concerta, with: [beer], catalog: catalog)
        #expect(formed.map(\.id) == [.ethylphenidate])
    }

    @Test
    func `A bystander dose in the same session claims nothing`() {
        // Cocaine and alcohol overlap, but this screen is an ibuprofen dose —
        // the note belongs on the precursors' own entries, not on everything
        // logged nearby.
        let ibuprofen = Self.onboard("Ibuprofen", at: 0, hours: 6)
        let peers = [Self.onboard("Cocaine", at: 1, hours: 2), Self.onboard("Alcohol", at: 1, hours: 4)]
        #expect(CombinationMetabolite.formed(overlapping: ibuprofen, with: peers, catalog: catalog).isEmpty)
    }

    @Test
    func `A lone dose with no peers forms nothing`() {
        let cocaine = Self.onboard("Cocaine", at: 0, hours: 2)
        #expect(CombinationMetabolite.formed(overlapping: cocaine, with: [], catalog: catalog).isEmpty)
    }

    @Test
    func `Touching windows count as co-present`() {
        // A dose taken exactly as the previous one clears still meets it; the
        // transesterification gate is presence, not a gap threshold.
        let alcohol = Self.onboard("Alcohol", at: 0, hours: 3)
        let cocaine = Self.onboard("Cocaine", at: 3, hours: 2)
        #expect(!CombinationMetabolite.formed(overlapping: cocaine, with: [alcohol], catalog: catalog).isEmpty)
    }
}
