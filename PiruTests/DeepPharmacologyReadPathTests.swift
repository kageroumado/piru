import Foundation
import Testing
@testable import Piru

/// The read paths for four tables that shipped in the bundled database with no
/// query reading them: `pharmacogenetics` (305 rows), `downstream_signalling`
/// (690), `biased_agonism` + `neuroimaging` + `receptor_oligomers` (83), and
/// `concentration_effects` (23).
///
/// Each test asserts a *specific* row reaches the model, not merely that the
/// query returns something — a coverage-shaped assertion is what let the
/// effects hole pass for 77 substances.
@Suite("Deep pharmacology read paths")
@MainActor
struct DeepPharmacologyReadPathTests {
    // MARK: - Pharmacogenetics

    @Test
    func `A substance's pharmacogenetic rows load with their gene and study`() throws {
        let rows = SubstanceStore.shared.pharmacogenetics(forSubstanceName: "Codeine")
        #expect(!rows.isEmpty)
        let cyp2d6 = try #require(rows.first { $0.gene.hasPrefix("CYP2D6") })
        #expect(!cyp2d6.phenotypeEffects.isEmpty)
        #expect(cyp2d6.sourceSlug == "peer-review-primary")
    }

    @Test
    func `One row per gene, even when several papers cover it`() {
        // Ketamine carries four CYP2B6 rows; four statements about one gene
        // asks the reader to reconcile them.
        let rows = SubstanceStore.shared.pharmacogenetics(forSubstanceName: "Ketamine")
        let genes = rows.map { $0.gene.lowercased().split(separator: "*").first.map(String.init) ?? "" }
        #expect(genes.count == Set(genes).count)
    }

    @Test
    func `An allele suffix does not split one gene into two rows`() {
        // "CYP1A2*1F (rs762551)" and "CYP1A2" are the same gene.
        let rows = SubstanceStore.shared.pharmacogenetics(forSubstanceName: "Caffeine")
        #expect(rows.filter { $0.gene.uppercased().contains("CYP1A2") }.count <= 1)
    }

    @Test
    func `An unknown substance yields no rows rather than failing`() {
        #expect(SubstanceStore.shared.pharmacogenetics(forSubstanceName: "Notarealsubstance").isEmpty)
    }

    // MARK: - Signalling cascade

    @Test
    func `The cascade after binding loads for a substance that has one`() throws {
        let cascade = try #require(SubstanceStore.shared.signallingCascade(forSubstanceName: "Ketamine"))
        // The row is authored as the chain, which is the point of having it.
        #expect(cascade.summary.contains("NMDA"))
        #expect(cascade.summary.count > 40)
    }

    @Test
    func `A substance with no cascade row yields nil`() {
        #expect(SubstanceStore.shared.signallingCascade(forSubstanceName: "Notarealsubstance") == nil)
    }

    // MARK: - Target evidence

    @Test
    func `Target evidence merges three tables and labels each row's kind`() throws {
        let rows = SubstanceStore.shared.targetEvidence(forSubstanceName: "Morphine")
        #expect(!rows.isEmpty)
        let bias = try #require(rows.first { $0.kind == .bias })
        #expect(bias.subject == "MOR")
        #expect(!bias.finding.isEmpty)
    }

    @Test
    func `Row ids stay unique across the three tables they come from`() {
        // Each source table has its own autoincrement, so an id alone collides.
        for name in ["Morphine", "Ketamine", "Zolpidem", "Brivaracetam"] {
            let ids = SubstanceStore.shared.targetEvidence(forSubstanceName: name).map(\.id)
            #expect(ids.count == Set(ids).count, "duplicate evidence id for \(name)")
        }
    }

    @Test
    func `In vivo evidence sorts ahead of in vitro`() {
        let rows = SubstanceStore.shared.targetEvidence(forSubstanceName: "Brivaracetam")
        if let firstImaging = rows.firstIndex(where: { $0.kind == .imaging }),
           let firstOther = rows.firstIndex(where: { $0.kind != .imaging }) {
            #expect(firstImaging < firstOther)
        }
    }

    // MARK: - Concentration thresholds

    @Test
    func `Concentration thresholds load in ascending order`() throws {
        let rows = SubstanceStore.shared.concentrationThresholds(forSubstanceName: "Ketamine")
        #expect(rows.count >= 2)
        let thresholds = rows.compactMap(\.threshold)
        #expect(thresholds == thresholds.sorted())
        let anesthesia = try #require(rows.first { $0.effect.localizedCaseInsensitiveContains("anesthesia") })
        #expect(anesthesia.unit == "ng/mL")
        #expect((anesthesia.threshold ?? 0) > 0)
    }
}
