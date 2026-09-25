import Foundation
import Testing
@testable import Piru

/// Logging a med from My Meds or Log Medications records the product the med
/// names, so the dose's title, extended-release curve, and tier rule are the
/// product's rather than the bare molecule's.
@Suite("Logging a med")
@MainActor
struct MedicationLoggingTests {
    @Test
    func `A Concerta med logs as Concerta`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        let med = DailyDoseItem(
            substance: "Methylphenidate", amount: 36, unit: "mg", sortOrder: 0, isBackgroundMed: true,
            substanceUID: SubstanceLibrary.substanceUID(for: "Methylphenidate"),
            isomer: SubstanceLibrary.isomer(for: "Concerta"),
            releaseForm: SubstanceLibrary.releaseForm(for: "Concerta"),
            productName: "Concerta",
        )
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let entry = DoseEntry.medication(med, at: at)

        #expect(entry.substance == "Methylphenidate")
        #expect(entry.amount == 36)
        #expect(entry.unit == "mg")
        #expect(entry.route == med.route)
        #expect(entry.timestamp == at)
        #expect(entry.isBackgroundMed)
        #expect(entry.productName == "Concerta")
        #expect(entry.releaseForm == "XR")
        #expect(entry.isomer == med.isomer)
        #expect(entry.saltForm == med.saltForm)
        #expect(entry.substanceUID != nil)
        #expect(entry.substanceUID == med.substanceUID)
        #expect(entry.identityKey == med.identityKey, "the logged dose checks the med off")
        #expect(DoseTitle.resolve(for: entry) == "Concerta")
        #expect(entry.displayNameSnapshot == DoseTitle.snapshot(canonicalName: "Methylphenidate", isomer: med.isomer, releaseForm: "XR"))
        #expect(entry.productDuration != nil, "the product's own curve, not the IR one")
    }
}
