import Foundation
import Testing
@testable import Piru

/// D.1 — the product the user named survives capture.
///
/// The bug this pins: a search for "Concerta" resolved to Methylphenidate and
/// then threw the word away, so the committed dose was byte-identical to a
/// Ritalin one and the XR was unrecoverable (the `substanceUID == nil` backfill
/// gate never revisits a dose that already has a uid). See
/// `Specs/psid-identity-consumption.md` D.1.
@Suite("Product name capture")
@MainActor
struct ProductNameCaptureTests {
    private func match(_ query: String) -> SubstanceMatch? {
        SubstanceLibrary.searchMatches(query).first { $0.matchedAlias?.lowercased() == query.lowercased() }
            ?? SubstanceLibrary.searchMatches(query).first
    }

    // MARK: - The alias comes back out of search

    @Test
    func `Brand search returns the brand it matched`() {
        let hit = match("concerta")
        #expect(hit?.substance.name == "Methylphenidate")
        #expect(hit?.matchedAlias == "Concerta", "the typed brand must survive the match")
        #expect(hit?.displayName == "Concerta", "the row titles the user's word, not the catalog's")
    }

    @Test
    func `Canonical search names no product`() {
        let hit = match("methylphenidate")
        #expect(hit?.substance.name == "Methylphenidate")
        #expect(hit?.matchedAlias == nil, "the user named the substance; asserting a product would put words in their mouth")
        #expect(hit?.displayName == "Methylphenidate")
    }

    @Test
    func `Prefix of a brand still names it`() {
        // A user who typed "concert" is reaching for Concerta and hasn't finished.
        let hit = match("concert")
        #expect(hit?.matchedAlias == "Concerta")
    }

    @Test
    func `Shortest alias wins a prefix tie`() {
        // "rital" prefixes Ritalin, Ritalin LA, and Ritalin SR — all one substance.
        // `aliasIndex` is a dictionary, so without a total order this row would be
        // titled differently on different keystrokes.
        let first = match("rital")?.matchedAlias
        #expect(first == "Ritalin")
        for _ in 0 ..< 5 {
            #expect(match("rital")?.matchedAlias == first, "alias choice must not vary with dictionary layout")
        }
    }

    @Test
    func `Display casing survives normalization`() {
        // aliasIndex keys are the pipeline's `alias_normalized`; the row needs the
        // authored casing back.
        #expect(match("vyvanse")?.matchedAlias == "Vyvanse")
        #expect(match("oxycontin")?.matchedAlias == "OxyContin")
    }

    // MARK: - The facets the product names

    @Test
    func `Staged brand recovers its release form`() {
        // The regression this whole stage exists for: `releaseForm` derived from
        // `substanceName`, which is canonicalized at staging, so it always read nil.
        let dose = StagedDose(
            substanceName: "Methylphenidate", amount: 36, unit: "mg", route: .oral,
            productName: "Concerta",
        )
        #expect(dose.releaseForm == "XR")
    }

    @Test
    func `Staged bare brand claims no release form`() {
        // "Ritalin" is the unspecified form — the PSID `0` sentinel. Claiming IR
        // for it would assert a form the name never named.
        let dose = StagedDose(
            substanceName: "Methylphenidate", amount: 10, unit: "mg", route: .oral,
            productName: "Ritalin",
        )
        #expect(dose.releaseForm == nil)
    }

    @Test
    func `Canonical staging claims no release form`() {
        let dose = StagedDose(substanceName: "Methylphenidate", amount: 10, unit: "mg", route: .oral)
        #expect(dose.releaseForm == nil)
    }

    @Test
    func `Brand naming an isomer seeds the picker`() {
        let substance = SubstanceLibrary.timelineLookup("Methylphenidate")
        #expect(substance != nil)
        let seeded = DoseTrayModel.seedIsomer(productName: "Focalin", librarySubstance: substance, route: .oral)
        #expect(seeded == "D", "the user named the enantiomer by typing it; don't make them re-answer")
    }

    @Test
    func `Isomer seed falls back when the route has no such ladder`() {
        // Methylphenidate has a D ladder on oral but not insufflation. The alias
        // names a substance-wide fact; the ladder is per-route.
        let substance = SubstanceLibrary.timelineLookup("Methylphenidate")
        let seeded = DoseTrayModel.seedIsomer(productName: "Focalin", librarySubstance: substance, route: .insufflation)
        #expect(seeded == substance?.defaultIsomer(for: .insufflation))
    }

    @Test
    func `Vyvanse stays a prodrug, not a release form`() {
        // Lisdexamfetamine's duration comes from enzymatic conversion, not a
        // delivery matrix. This is why the product name — not the release axis —
        // is the general mechanism. Guards PSIDResolutionTests:71 from the other side.
        let hit = match("vyvanse")
        #expect(hit?.substance.name == "Lisdexamfetamine")
        #expect(hit?.matchedAlias == "Vyvanse")
        let dose = StagedDose(
            substanceName: "Lisdexamfetamine", amount: 50, unit: "mg", route: .oral,
            productName: "Vyvanse",
        )
        #expect(dose.releaseForm == nil)
    }

    // MARK: - The canonical name is never displaced

    @Test
    func `Product name is not a lookup key`() {
        // LB-1: `substance` stays canonical so every downstream resolve keeps
        // working. If a product name ever became the key, interactions, PK, and
        // dedup would all start missing.
        let dose = StagedDose(
            substanceName: "Methylphenidate", amount: 36, unit: "mg", route: .oral,
            productName: "Concerta",
        )
        #expect(dose.substanceName == "Methylphenidate")
        #expect(SubstanceLibrary.timelineLookup(dose.substanceName) != nil)
    }

    @Test
    func `Entry carries the product alongside the canonical substance`() {
        let entry = DoseEntry(
            substance: "Methylphenidate", amount: 36, unit: "mg", route: .oral,
            releaseForm: "XR", productName: "Concerta",
        )
        #expect(entry.substance == "Methylphenidate")
        #expect(entry.productName == "Concerta")
        #expect(entry.releaseForm == "XR")
    }

    @Test
    func `Entry defaults to no product`() {
        // Every pre-existing dose. Additive + optional is what keeps the schema
        // change a free lightweight migration.
        let entry = DoseEntry(substance: "Caffeine", amount: 100, unit: "mg", route: .oral)
        #expect(entry.productName == nil)
    }

    // MARK: - Alias ordering (D.1.7)

    @Test
    func `displayAliases lead with the brand name`() {
        // Alphabetical ordering buried Vyvanse behind Elvanse/LDX; `aliases.kind`
        // now floats the brand first, so the "Also known as" subtitle shows the
        // name people actually know. Findability is untouched (normalized index).
        let ldx = SubstanceLibrary.lookupByNameOrAlias("Lisdexamfetamine")
        #expect(ldx?.displayAliases.first == "Vyvanse")

        // A substance with many brands leads with the curated flagship (Ritalin,
        // brand_rank 0) ahead of the auto-derived form brands (Concerta, rank 1) —
        // not the alphabetically-first "Adhansia XR".
        let mph = SubstanceLibrary.lookupByNameOrAlias("Methylphenidate")
        #expect(mph?.displayAliases.first == "Ritalin")
        #expect(mph?.displayAliases.prefix(2).contains("Concerta") == true)
    }
}
