import Foundation
import SwiftData
import Testing
@testable import Piru

/// PSID D.2: recents, favorites, and daily items key on substance *identity*
/// (family + form facets), not a bare name — so a Concerta chip
/// (Methylphenidate·XR) and a Ritalin IR chip (Methylphenidate·IR) are distinct
/// cards, while "Concerta" and "Methylphenidate XR" (both ·XR) merge. These pin
/// the key derivation, the card split, favorite membership, and the backfill.
@MainActor
@Suite("QuickLogIdentityKey")
struct QuickLogIdentityKeyTests {
    // MARK: identityKey / makeKey

    @Test
    func `a facet-less row keys exactly as the old name scheme`() {
        // No uid, no facets → the lowercased name, byte-identical to pre-PSID.
        #expect(
            QuickLogDose.identityKey(substanceUID: nil, substance: "Methylphenidate", isomer: nil, releaseForm: nil, saltForm: nil)
                == "methylphenidate",
        )
        // The PSID unspecified sentinel "0" counts as absent.
        #expect(
            QuickLogDose.identityKey(substanceUID: nil, substance: "Methylphenidate", isomer: "0", releaseForm: "0", saltForm: "0")
                == "methylphenidate",
        )
    }

    @Test
    func `release form splits one family into distinct identities`() {
        let concerta = QuickLogDose.identityKey(substanceUID: "MPH", substance: "Methylphenidate", isomer: nil, releaseForm: "XR", saltForm: nil)
        let ritalinIR = QuickLogDose.identityKey(substanceUID: "MPH", substance: "Methylphenidate", isomer: nil, releaseForm: "IR", saltForm: nil)
        let plain = QuickLogDose.identityKey(substanceUID: "MPH", substance: "Methylphenidate", isomer: nil, releaseForm: nil, saltForm: nil)
        #expect(concerta != ritalinIR)
        #expect(concerta != plain)
        #expect(ritalinIR != plain)
        #expect(plain == "MPH") // an unfaceted resolved dose keys by bare family uid
    }

    @Test
    func `makeKey with no identity args matches the legacy string`() {
        // The drink-preset callers and the regression net (CustomDrinkPresetTests)
        // pass no identity — the output must not move.
        let legacy = "methylphenidate|oral|18.0|mg"
        #expect(QuickLogDose.makeKey(substance: "Methylphenidate", route: .oral, amount: 18, unit: "mg") == legacy)
    }

    @Test
    func `makeKey folds identity in so two forms never collide`() {
        let concerta = QuickLogDose.makeKey(
            substance: "Methylphenidate", route: .oral, amount: 18, unit: "mg",
            substanceUID: "MPH", releaseForm: "XR",
        )
        let ritalinIR = QuickLogDose.makeKey(
            substance: "Methylphenidate", route: .oral, amount: 18, unit: "mg",
            substanceUID: "MPH", releaseForm: "IR",
        )
        #expect(concerta != ritalinIR)
    }

    // MARK: Card split

    private func resolvedDose(_ substance: String, uid: String, release: String?, product: String?) -> QuickLogDose {
        QuickLogDose(
            substance: substance, route: .oral, amount: 18, unit: "mg", sortOrder: 0,
            substanceUID: uid, releaseForm: release, productName: product,
        )
    }

    @Test
    func `two forms of one substance build two cards`() {
        let content = QuickLogContentModel()
        let doses = [
            resolvedDose("Methylphenidate", uid: "MPH", release: "XR", product: "Concerta"),
            resolvedDose("Methylphenidate", uid: "MPH", release: "IR", product: "Ritalin IR"),
            resolvedDose("Methylphenidate", uid: "MPH", release: nil, product: nil),
        ]
        content.rebuildColorLookup(substanceColors: [])
        content.rebuildCards(quickLogDoses: doses, favorites: [])

        #expect(content.cachedCards.count == 3) // XR, IR, and plain are separate
        // The product card titles by the user's word; the plain one has no title.
        #expect(content.cachedCards.contains { $0.title == "Concerta" })
        #expect(content.cachedCards.contains { $0.title == "Ritalin IR" })
        #expect(content.cachedCards.contains { $0.title == nil })
    }

    @Test
    func `same family and facets merge into one card`() {
        let content = QuickLogContentModel()
        // "Concerta" and "Methylphenidate XR" both resolve to Methylphenidate·XR.
        let doses = [
            resolvedDose("Methylphenidate", uid: "MPH", release: "XR", product: "Concerta"),
            resolvedDose("Methylphenidate", uid: "MPH", release: "XR", product: "Methylphenidate XR"),
        ]
        content.rebuildColorLookup(substanceColors: [])
        content.rebuildCards(quickLogDoses: doses, favorites: [])
        #expect(content.cachedCards.count == 1)
    }

    // MARK: Favorites

    @Test
    func `a favorite pins one form, not the whole family`() {
        let content = QuickLogContentModel()
        let doses = [
            resolvedDose("Methylphenidate", uid: "MPH", release: "XR", product: "Concerta"),
            resolvedDose("Methylphenidate", uid: "MPH", release: nil, product: nil),
        ]
        // Favorite only Concerta (the ·XR form).
        let favorite = FavoriteSubstance(substance: "Methylphenidate", substanceUID: "MPH", releaseForm: "XR", productName: "Concerta")

        content.rebuildColorLookup(substanceColors: [])
        content.rebuildCards(quickLogDoses: doses, favorites: [favorite])

        #expect(content.cachedFavoriteCards.count == 1)
        #expect(content.cachedFavoriteCards.first?.title == "Concerta")
        // The plain Methylphenidate card is a recent, not a favorite.
        #expect(content.cachedNonFavoriteCards.contains { $0.title == nil })
        #expect(content.cachedNonFavoriteCards.contains { $0.title == "Concerta" } == false)
    }

    // MARK: Unmodeled-form PK badge

    @Test
    func `an unmodeled form draws no active-dose badge`() throws {
        let content = QuickLogContentModel()
        // A Concerta recents card (Methylphenidate·XR), and a dose of the same
        // form logged just now.
        let chip = resolvedDose("Methylphenidate", uid: "MPH", release: "XR", product: "Concerta")
        content.rebuildColorLookup(substanceColors: [])
        content.rebuildCards(quickLogDoses: [chip], favorites: [])
        let cardID = content.cachedCards.first?.id
        #expect(cardID != nil)

        let dose = DoseEntry(substance: "Methylphenidate", amount: 18, route: .oral, releaseForm: "XR", substanceUID: "MPH")
        content.rebuildEntryDerived(allEntries: [dose], dailyDoseItems: [], routines: [])

        // No "≈X active · Yh left" badge for a form whose kinetics we don't model —
        // that would be base-form timing wearing Concerta's name.
        #expect(try content.cachedMostRecent[#require(cardID)] == nil)
    }

    // MARK: Backfill

    /// A fresh in-memory container on the current schema.
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        return ModelContext(container)
    }

    @Test
    func `backfill never drops an unresolvable name and is idempotent`() throws {
        let ctx = try makeContext()
        // A name the catalog can't resolve stays name-only (substanceUID nil).
        let bogus = QuickLogDose(substance: "Zzqxwv Not A Drug", route: .oral, amount: 1, unit: "mg", sortOrder: 0)
        ctx.insert(bogus)
        try ctx.save()

        CuratedIdentityBackfillMigration.run(context: ctx)
        #expect(bogus.substanceUID == nil) // never dropped, never mis-resolved
        #expect(bogus.substance == "Zzqxwv Not A Drug") // retained string untouched

        // A second run finds the same straggler and changes nothing — idempotent.
        CuratedIdentityBackfillMigration.run(context: ctx)
        #expect(bogus.substanceUID == nil)
    }
}
