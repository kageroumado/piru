import Foundation
import Testing
@testable import Piru

/// A dose tier is a claim that a dose sits somewhere on a ladder. Every ladder the
/// app carries is measured on the base (immediate-release) form, so a dose in a
/// form the ladder doesn't describe gets no tier, never the base form's. The
/// motivating case: 36 mg of Concerta read "strong" against methylphenidate's
/// immediate-release numbers.
@Suite("Dose tiers by release form")
@MainActor
struct ReleaseFormDoseTierTests {
    private func methylphenidate() async throws -> Substance {
        await SubstanceStore.shared.ensureAllLoaded()
        return try #require(SubstanceLibrary.lookup("Methylphenidate"))
    }

    private func entry(
        _ substance: String = "Methylphenidate",
        amount: Double = 36,
        releaseForm: String? = nil,
        productName: String? = nil,
        timestamp: Date = .now,
        isUnknownDose: Bool = false,
    ) -> DoseEntry {
        DoseEntry(
            substance: substance, amount: amount, unit: "mg", route: .oral,
            releaseForm: releaseForm, productName: productName, timestamp: timestamp, isUnknownDose: isUnknownDose,
        )
    }

    // MARK: - The predicate

    @Test
    func `Only the unspecified form and IR are base forms`() {
        #expect(BaseReleaseForm.contains(nil))
        #expect(BaseReleaseForm.contains(""))
        #expect(BaseReleaseForm.contains("0"))
        #expect(BaseReleaseForm.contains("IR"))
        #expect(BaseReleaseForm.contains("ir"))
        #expect(!BaseReleaseForm.contains("XR"))
        #expect(!BaseReleaseForm.contains("DEP"))
    }

    // MARK: - The classifier

    @Test
    func `Concerta 36 mg has no tier`() async throws {
        let mph = try await methylphenidate()
        let concerta = entry(releaseForm: "XR", productName: "Concerta")
        #expect(mph.tierLadder(for: .oral, saltForm: nil, isomer: nil, releaseForm: "XR") == nil)
        #expect(concerta.doseLevel(on: mph) == nil)
    }

    @Test
    func `Plain methylphenidate 36 mg has a tier`() async throws {
        let mph = try await methylphenidate()
        #expect(entry().doseLevel(on: mph) != nil)
    }

    @Test
    func `An immediate-release brand keeps its tier`() async throws {
        let mph = try await methylphenidate()
        // Ritalin stages as the unspecified form; the classifier reads what the
        // staging recorded rather than assuming it.
        let ritalin = StagedDose(substanceName: "Methylphenidate", amount: 10, unit: "mg", route: .oral, productName: "Ritalin")
        #expect(entry(amount: 10, releaseForm: ritalin.releaseForm, productName: "Ritalin").doseLevel(on: mph) != nil)

        let amphetamine = try #require(SubstanceLibrary.lookup("Amphetamine"))
        #expect(entry("Amphetamine", amount: 10, releaseForm: "IR", productName: "Adderall IR").doseLevel(on: amphetamine) != nil)
        #expect(entry("Amphetamine", amount: 10, releaseForm: "XR", productName: "Adderall XR").doseLevel(on: amphetamine) == nil)
    }

    @Test
    func `An unknown amount has no tier in any form`() async throws {
        let mph = try await methylphenidate()
        #expect(entry(isUnknownDose: true).doseLevel(on: mph) == nil)
    }

    // MARK: - Surfaces that read it

    @Test
    func `A staged Concerta dose shows no tier in the tray`() async throws {
        let mph = try await methylphenidate()
        let concerta = StagedDose(
            substanceName: "Methylphenidate", amount: 36, unit: "mg", route: .oral,
            productName: "Concerta", librarySubstance: mph,
        )
        #expect(concerta.releaseForm == "XR")
        #expect(concerta.doseLevel == nil)

        let plain = StagedDose(substanceName: "Methylphenidate", amount: 36, unit: "mg", route: .oral, librarySubstance: mph)
        #expect(plain.doseLevel != nil)
    }

    @Test
    func `A Concerta journal row carries no tier`() async throws {
        _ = try await methylphenidate()
        let cores = DayEntryCore.make(from: [entry(releaseForm: "XR", productName: "Concerta"), entry()])
        #expect(cores[0].doseLevel == nil)
        #expect(cores[1].doseLevel != nil)
    }

    @Test
    func `Extended-release doses never raise the cumulative alert`() async throws {
        _ = try await methylphenidate()
        let earlier = (0 ..< 4).map { index in
            entry(amount: 54, releaseForm: "XR", productName: "Concerta", timestamp: .now.addingTimeInterval(Double(-index - 1) * 600))
        }
        let (_, _, alertsOnER) = SessionNotificationScheduler.checkCumulativeDose(
            substanceName: "Methylphenidate", newAmount: 54, unit: "mg", route: .oral,
            releaseForm: "XR", existingEntries: earlier,
        )
        #expect(!alertsOnER, "the base ladder doesn't describe an extended-release total")

        let (total, _, _) = SessionNotificationScheduler.checkCumulativeDose(
            substanceName: "Methylphenidate", newAmount: 10, unit: "mg", route: .oral,
            existingEntries: earlier,
        )
        #expect(total == 10, "earlier extended-release doses stay out of a base-form total")
    }
}
