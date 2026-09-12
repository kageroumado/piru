import Foundation
import SwiftData
import Testing
@testable import Piru

/// Acceptance for the 2026-09-12 family re-pin: a persisted `substanceUID`
/// stamped with a corrected-away OLD family is rewritten onto its NEW family in
/// a single pass, across every `@Model` that stores one, while a non-listed uid
/// is left alone and the map is applied exactly once (never chained).
@MainActor
@Suite("PSID re-pin migration")
struct PSIDRepinMigrationTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        return ModelContext(container)
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "psid-repin-tests-\(UUID().uuidString)")!
    }

    @Test
    func `Old family uids are rewritten; a non-listed uid is untouched`() throws {
        let context = try makeContext()
        let defaults = makeDefaults()

        let mapped = DoseEntry(substance: "1Cp-LSD", amount: 1, substanceUID: "BYIVGHIYNFQIJX")
        let untouched = DoseEntry(substance: "Caffeine", amount: 100, substanceUID: "RYYVLZVUVIJVGH")
        let nameOnly = DoseEntry(substance: "ZZUnknown", amount: 1) // substanceUID == nil
        context.insert(mapped)
        context.insert(untouched)
        context.insert(nameOnly)
        try context.save()

        PSIDRepinMigration.run(context: context, defaults: defaults, setsFlag: false)

        #expect(mapped.substanceUID == "RAFUPYYDHPFASC", "old 1Cp-LSD family re-pinned")
        #expect(untouched.substanceUID == "RYYVLZVUVIJVGH", "a uid outside the map is left alone")
        #expect(nameOnly.substanceUID == nil, "a name-only row stays name-only")
    }

    @Test
    func `The shared value is remapped once, not chained`() throws {
        // CIDMXLOVFPIHDS is both an OLD key (4-AcO-MET → OMDKHOOGGJRLLX) and a NEW
        // value (4-AcO-MiPT: 7XKAILDRTAUYWE → CIDMXLOVFPIHDS). A single-pass lookup
        // against each row's ORIGINAL value must land the 4-AcO-MET row on
        // OMDKHOOGGJRLLX and the 4-AcO-MiPT row on CIDMXLOVFPIHDS — chained
        // application would push the MiPT row on to OMDKHOOGGJRLLX, collapsing them.
        let context = try makeContext()
        let defaults = makeDefaults()

        let met = DoseEntry(substance: "4-AcO-MET", amount: 10, substanceUID: "CIDMXLOVFPIHDS")
        let mipt = DoseEntry(substance: "4-AcO-MiPT", amount: 10, substanceUID: "7XKAILDRTAUYWE")
        context.insert(met)
        context.insert(mipt)
        try context.save()

        PSIDRepinMigration.run(context: context, defaults: defaults, setsFlag: false)

        #expect(met.substanceUID == "OMDKHOOGGJRLLX", "4-AcO-MET re-pinned")
        #expect(mipt.substanceUID == "CIDMXLOVFPIHDS", "4-AcO-MiPT re-pinned once, not chained onward")
        #expect(met.substanceUID != mipt.substanceUID, "the two stay distinct families")
    }

    @Test
    func `Every model that stores a substanceUID is rewritten`() throws {
        let context = try makeContext()
        let defaults = makeDefaults()

        let dose = DoseEntry(substance: "Haloperidol", amount: 5, substanceUID: "GUTXTARXLVFHDK")
        let chip = QuickLogDose(
            substance: "Naloxone", route: .intramuscular, amount: 0.4, unit: "mg",
            sortOrder: 0, substanceUID: "RGPDIGOSVORSAK",
        )
        let fav = FavoriteSubstance(substance: "Sildenafil", substanceUID: "DEIYFTQMQPDXOT")
        let daily = DailyDoseItem(substance: "Varenicline", amount: 1, substanceUID: "TWYFGYXQSYOKLK")
        let occ = RoutineOccurrence(
            routineName: "Morning", substance: "Tianeptine", substanceUID: "APNKSKXHMUCNSY",
            route: .oral, dueDay: Date(timeIntervalSince1970: 1_700_000_000),
        )
        context.insert(dose)
        context.insert(chip)
        context.insert(fav)
        context.insert(daily)
        context.insert(occ)
        try context.save()

        PSIDRepinMigration.run(context: context, defaults: defaults, setsFlag: false)

        #expect(dose.substanceUID == "LNEPOXFFQSENCJ", "DoseEntry rewritten")
        #expect(chip.substanceUID == "UZHSEJADLWPNLE", "QuickLogDose rewritten")
        #expect(fav.substanceUID == "BNRNXUUZRGQAQC", "FavoriteSubstance rewritten")
        #expect(daily.substanceUID == "JQSHBVHOMNKWFT", "DailyDoseItem rewritten")
        #expect(occ.substanceUID == "JICJBGPOMZQUBB", "RoutineOccurrence rewritten")
    }

    @Test
    func `The run is once-only — the flag skips a second pass`() throws {
        let context = try makeContext()
        let defaults = makeDefaults()

        let dose = DoseEntry(substance: "Doip", amount: 10, substanceUID: "GYEHYVZVTYSXPS")
        context.insert(dose)
        try context.save()

        // First pass runs on this same context and sets the flag.
        PSIDRepinMigration.run(context: context, defaults: defaults)
        #expect(dose.substanceUID == "SPKSLAUXKHSASF", "first run re-pins")
        #expect(defaults.bool(forKey: PSIDRepinMigration.didRunKey), "the flag is now set")

        // A hand-corrupted value after the run must NOT be touched — the flag set
        // above makes runIfNeeded return before it looks at any row.
        dose.substanceUID = "GYEHYVZVTYSXPS"
        try context.save()
        PSIDRepinMigration.runIfNeeded(container: context.container, defaults: defaults)
        #expect(dose.substanceUID == "GYEHYVZVTYSXPS", "the flag blocks a second pass")
    }
}
