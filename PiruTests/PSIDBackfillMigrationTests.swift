import Foundation
import SwiftData
import Testing
@testable import Piru

/// Stage 0.3 acceptance — the once-only PSID backfill remaps logged doses onto
/// their `substanceUID` + `displayNameSnapshot`, additively and without row
/// loss, keeping the original name string and leaving the unresolvable
/// name-only. See `Specs/stereoisomer-and-release-form-axes.md`.
@MainActor
@Suite("PSID backfill migration")
struct PSIDBackfillMigrationTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        return ModelContext(container)
    }

    /// A fresh, isolated defaults suite so the kill-switch / snapshot flags never
    /// leak between tests or into the real app domain.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "psid-backfill-tests-\(UUID().uuidString)")!
    }

    /// A name guaranteed absent from the library, so it must stay name-only.
    private let unresolvable = "ZZTestSubstanceNotInLibrary"

    @Test
    func `Form-bearing and bare names resolve to the right FAMILY; unresolvable stays name-only`() throws {
        let context = try makeContext()
        let defaults = makeDefaults()

        let names = ["Concerta", "Adderall XR", "Methylphenidate", "Esketamine", unresolvable]
        for name in names {
            context.insert(DoseEntry(substance: name, amount: 10, timestamp: Date(timeIntervalSince1970: 1_700_000_000)))
        }
        try context.save()

        PSIDBackfillMigration.run(context: context, defaults: defaults, snapshotsStore: false)

        let rows = try context.fetch(FetchDescriptor<DoseEntry>())
        // Zero row loss.
        #expect(rows.count == names.count)
        let byName = Dictionary(uniqueKeysWithValues: rows.map { ($0.substance, $0) })

        // Every original string is retained.
        for name in names {
            #expect(byName[name] != nil, "row for \(name) must survive")
        }

        // A bare name resolves to the unspecified form and snapshots the
        // locale-stable CANONICAL name — not a region-resolved display title.
        let plain = try #require(byName["Methylphenidate"])
        let mph = try #require(SubstanceLibrary.timelineLookup("Methylphenidate"))
        #expect(plain.substanceUID == mph.substanceUID, "should carry its FAMILY uid")
        #expect(try PSID.isWellformedFamily(#require(plain.substanceUID)))
        #expect(plain.displayNameSnapshot == mph.name, "bare name snapshots its canonical name")
        #expect(plain.releaseForm == nil, "a bare name claims no release form")

        // Stage B: a release-form brand now recovers its facet and is titled by that
        // form, while still resolving to the parent's FAMILY (there is no separate
        // XR row — the facet is what distinguishes it).
        for (name, title) in [("Concerta", "Methylphenidate XR"), ("Adderall XR", "Amphetamine XR")] {
            let match = try #require(SubstanceLibrary.timelineLookup(name))
            let row = try #require(byName[name])
            #expect(row.substanceUID == match.substanceUID, "\(name) should carry its FAMILY uid")
            #expect(try PSID.isWellformedFamily(#require(row.substanceUID)))
            #expect(row.releaseForm == "XR", "\(name) recovers the extended-release form")
            #expect(row.displayNameSnapshot == title, "\(name) titled by its form")
        }

        // An isomer form-string (Esketamine) resolves its facet + form title (Stage
        // A), sharing the parent FAMILY but titled by its own recognized name.
        let esk = try #require(byName["Esketamine"])
        let ketamine = try #require(SubstanceLibrary.timelineLookup("Esketamine"))
        #expect(esk.substanceUID == ketamine.substanceUID, "Esketamine carries the Ketamine FAMILY")
        #expect(esk.isomer == "S", "Esketamine recovers the S-enantiomer form")
        #expect(esk.displayNameSnapshot == "Esketamine", "titled by its form")

        // Concerta and Methylphenidate share the methylphenidate FAMILY.
        #expect(byName["Concerta"]?.substanceUID == byName["Methylphenidate"]?.substanceUID)

        // The unresolvable name is never dropped: name-only, string retained.
        let orphan = try #require(byName[unresolvable])
        #expect(orphan.substanceUID == nil)
        #expect(orphan.displayNameSnapshot == nil)
        #expect(orphan.substance == unresolvable)
    }

    @Test
    func `The migration is idempotent — a second run changes nothing`() throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        context.insert(DoseEntry(substance: "Caffeine", amount: 100))
        try context.save()

        PSIDBackfillMigration.run(context: context, defaults: defaults, snapshotsStore: false)
        let uidAfterFirst = try context.fetch(FetchDescriptor<DoseEntry>()).first?.substanceUID
        #expect(uidAfterFirst != nil, "Caffeine should have resolved")

        PSIDBackfillMigration.runIfNeeded(container: context.container, defaults: defaults)
        let uidAfterSecond = try context.fetch(FetchDescriptor<DoseEntry>()).first?.substanceUID
        #expect(uidAfterFirst == uidAfterSecond)
    }

    @Test
    func `A form-bearing legacy string resolves its isomer facet + title`() throws {
        // Stage A extends the backfill: a logged enantiomer/brand string recovers
        // its form via the facet-annotated alias table, so it keeps its identity
        // and title instead of collapsing to the racemate — without ever dropping
        // the original string.
        let context = try makeContext()
        let defaults = makeDefaults()
        let focalin = DoseEntry(substance: "Dexmethylphenidate", amount: 10)
        context.insert(focalin)
        try context.save()

        PSIDBackfillMigration.run(context: context, defaults: defaults, snapshotsStore: false)

        #expect(focalin.substanceUID != nil, "resolves to the Methylphenidate FAMILY")
        #expect(focalin.isomer == "D", "recovers the D-enantiomer form")
        #expect(focalin.displayNameSnapshot == "Dexmethylphenidate", "titled by its form")
        #expect(focalin.substance == "Dexmethylphenidate", "original string retained")

        // A plain racemic string resolves the FAMILY with no isomer facet.
        let plain = DoseEntry(substance: "Methylphenidate", amount: 10)
        context.insert(plain)
        try context.save()
        PSIDBackfillMigration.run(context: context, defaults: defaults, snapshotsStore: false)
        #expect(plain.substanceUID == focalin.substanceUID, "same FAMILY as its enantiomer")
        #expect(plain.isomer == nil, "racemic — no isomer facet")
    }

    @Test
    func `A release-form brand resolves its release facet + title`() throws {
        // Stage B: a logged brand recovers the release form it named. Identity/label
        // only — no source carries a distinct extended-release duration, so this
        // records *which form was logged* and never implies a different curve.
        let context = try makeContext()
        let defaults = makeDefaults()
        let concerta = DoseEntry(substance: "Concerta", amount: 36)
        context.insert(concerta)
        try context.save()

        PSIDBackfillMigration.run(context: context, defaults: defaults, snapshotsStore: false)

        #expect(concerta.substanceUID != nil, "resolves to the Methylphenidate FAMILY")
        #expect(concerta.releaseForm == "XR", "recovers the extended-release form")
        #expect(concerta.isomer == nil, "Concerta is racemic — no isomer facet")
        #expect(concerta.displayNameSnapshot == "Methylphenidate XR", "titled by its form")
        #expect(concerta.substance == "Concerta", "original string retained")

        // The base brand names no release form — it must NOT be inferred as "IR".
        let adderall = DoseEntry(substance: "Adderall", amount: 20)
        context.insert(adderall)
        try context.save()
        PSIDBackfillMigration.run(context: context, defaults: defaults, snapshotsStore: false)
        #expect(adderall.releaseForm == nil, "a bare base brand is the unspecified form")
    }

    @Test
    func `A cross-axis brand resolves both facets into one title`() throws {
        // Focalin XR is the D-enantiomer AND extended-release. Recovering only the
        // release form would assert *racemic* methylphenidate XR — the wrong drug.
        let context = try makeContext()
        let defaults = makeDefaults()
        let focalinXR = DoseEntry(substance: "Focalin XR", amount: 20)
        context.insert(focalinXR)
        try context.save()

        PSIDBackfillMigration.run(context: context, defaults: defaults, snapshotsStore: false)

        #expect(focalinXR.isomer == "D", "the D-enantiomer, not the racemate")
        #expect(focalinXR.releaseForm == "XR")
        #expect(focalinXR.displayNameSnapshot == "Dexmethylphenidate XR", "both facets compose")
    }

    @Test
    func `Data-driven idempotency is self-healing — a later name-only row still migrates`() throws {
        // The guard is the row's own nil `substanceUID`, not a global flag: a dose
        // that arrives after the first run (an import, a store restore, or a name
        // that only resolves once the catalog updates) is picked up on a re-run.
        let context = try makeContext()
        let defaults = makeDefaults()
        context.insert(DoseEntry(substance: "Caffeine", amount: 100))
        try context.save()

        PSIDBackfillMigration.run(context: context, defaults: defaults, snapshotsStore: false)

        // Simulate a restored / imported row landing after the first run.
        context.insert(DoseEntry(substance: "Melatonin", amount: 3))
        try context.save()

        PSIDBackfillMigration.runIfNeeded(container: context.container, defaults: defaults)
        let byName = try Dictionary(
            uniqueKeysWithValues:
            context.fetch(FetchDescriptor<DoseEntry>()).map { ($0.substance, $0) },
        )
        #expect(byName["Caffeine"]?.substanceUID != nil)
        #expect(byName["Melatonin"]?.substanceUID != nil, "a post-run row must still resolve")
    }

    @Test
    func `The kill-switch skips the run and re-runs once cleared`() throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        defaults.set(true, forKey: PSIDBackfillMigration.disabledKey)
        context.insert(DoseEntry(substance: "Caffeine", amount: 100))
        try context.save()

        PSIDBackfillMigration.runIfNeeded(container: context.container, defaults: defaults)
        #expect(try context.fetch(FetchDescriptor<DoseEntry>()).first?.substanceUID == nil)

        // Clear the switch → it now runs and resolves.
        defaults.set(false, forKey: PSIDBackfillMigration.disabledKey)
        PSIDBackfillMigration.runIfNeeded(container: context.container, defaults: defaults)
        #expect(try context.fetch(FetchDescriptor<DoseEntry>()).first?.substanceUID != nil)
    }

    @Test
    func `An empty store is a no-op and takes no snapshot`() throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        PSIDBackfillMigration.run(context: context, defaults: defaults, snapshotsStore: false)
        #expect(try context.fetch(FetchDescriptor<DoseEntry>()).isEmpty)
        #expect(!defaults.bool(forKey: PSIDBackfillMigration.snapshotDoneKey))
    }
}
