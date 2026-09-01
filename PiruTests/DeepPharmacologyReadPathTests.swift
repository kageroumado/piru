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
    func `Genes sharing one finding collapse into a single row`() {
        // Ketamine's CYP2B6 study reports a null result for CYP3A4 and CYP3A5
        // in the same sentence, and it is filed as three rows carrying that
        // sentence — which rendered as the same paragraph three times under
        // three headings.
        let rows = SubstanceStore.shared.pharmacogenetics(forSubstanceName: "Ketamine")
        let findings = rows.map(\.phenotypeEffects)
        #expect(findings.count == Set(findings).count, "the same finding is shown more than once")
        #expect(rows.contains { $0.gene.contains("·") })
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

    // MARK: - Class context

    @Test
    func `A substance reads its class, its siblings and the class's references`() throws {
        let context = try #require(SubstanceStore.shared.classContext(forSubstanceName: "Alprazolam"))
        #expect(context.slug == "benzos-z-drugs")
        #expect(context.sharedMechanism?.isEmpty == false)
        #expect(context.hasBody)
        #expect(!context.siblings.isEmpty)
        #expect(!context.siblings.contains("Alprazolam"), "a substance is not its own sibling")
        #expect(!context.references.isEmpty)
    }

    @Test
    func `A membership contradicting the substance's own category is not shown`() {
        // The enrichment files tag comparison compounds with the class of the
        // file they appear in, so 2C-B shipped as an amphetamine-type monoamine
        // releaser, nitrazepam as a serotonergic phenethylamine psychedelic and
        // THC as a GABAergic depressant. No class is the honest answer; a wrong
        // one is a claim the reference must not make.
        for name in ["2C-B", "Nitrazepam", "THC", "Mescaline", "Propranolol"] {
            #expect(
                SubstanceStore.shared.classContext(forSubstanceName: name) == nil,
                "\(name) still carries a contradicting class",
            )
        }
    }

    @Test
    func `The class browse list carries only classes with something to read`() {
        let all = SubstanceStore.shared.classContexts()
        #expect(!all.isEmpty)
        for summary in all {
            let context = SubstanceStore.shared.classContext(slug: summary.slug)
            #expect(context?.hasBody == true, "\(summary.slug) has nothing to show")
        }
        #expect(Set(all.map(\.slug)).count == all.count)
    }

    @Test
    func `Classes group under the Library family their members belong to`() {
        let stimulants = SubstanceStore.shared.classContexts(in: .stimulant)
        #expect(stimulants.count >= 5)
        #expect(stimulants.allSatisfy { $0.category == .stimulant })
        // Ordered by member count, so the recognizable groups lead and the rare
        // ones fall to the bottom on their own.
        let counts = stimulants.map(\.memberCount)
        #expect(counts == counts.sorted(by: >))
        #expect(stimulants.first?.slug == "cathinones-beta-keto-stimulants")
    }

    @Test
    func `Class titles are short enough to be a browse row`() {
        // The authored names run to "First-generation H1 antihistamines with
        // anticholinergic deliriant activity"; the qualifier belongs in the
        // subtitle, not the row.
        for item in SubstanceStore.shared.classContexts() {
            #expect(item.title.count <= 46, "too long for a row: \(item.title)")
        }
    }

    @Test
    func `A class opened by slug lists all its members`() throws {
        // Opened from Tools rather than from a substance, so nobody is excluded.
        let context = try #require(SubstanceStore.shared.classContext(slug: "benzos-z-drugs"))
        let fromSubstance = try #require(
            SubstanceStore.shared.classContext(forSubstanceName: "Alprazolam"),
        )
        #expect(context.siblings.count == fromSubstance.siblings.count + 1)
        #expect(context.siblings.contains("Alprazolam"))
    }

    @Test
    func `A verified member survives the category check`() {
        // Levetiracetam is an Anticonvulsant in a class whose members are mostly
        // Nootropics, and the class's own write-up names it — the curated keep
        // list is what stops the rule dropping it.
        #expect(SubstanceStore.shared.classContext(forSubstanceName: "Levetiracetam")?.slug
            == "racetams-and-ampakines")
    }

    @Test
    func `Class membership survives an enrichment file that declares its context last`() {
        // The ingest built its slug table as it walked the file, so in the
        // fifteen files whose context record sits at the END every membership
        // was silently dropped. These four classes are all from such files.
        for name in ["Alprazolam", "Morphine", "Piracetam", "Fentanyl"] {
            #expect(
                SubstanceStore.shared.classContext(forSubstanceName: name) != nil,
                "\(name) has no class context",
            )
        }
    }

    @Test
    func `Class contexts that are notes about the source data never ship`() {
        // "Data integrity issues in source list" is a finding about the input,
        // not a class anybody belongs to.
        let excluded = ["data-error", "synthetic-cannabinoids", "tryptamine-related"]
        for name in ["2C-B", "Alprazolam", "Morphine", "JWH-018", "MDMA", "LSD"] {
            if let slug = SubstanceStore.shared.classContext(forSubstanceName: name)?.slug {
                #expect(!excluded.contains(slug))
            }
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

/// The Library category screen shows a one-card summary of the family with a
/// link into its class groups. The card and the link are independent: the link
/// appears when the category has class contexts, the card when the category has
/// a `classSummary`. A category that gains the first without the second renders
/// an empty card above a working link.
@Suite("Class summaries cover every category that has classes")
@MainActor
struct ClassSummaryCoverageTests {
    @Test
    func `Every category with class contexts has a summary to show`() {
        let withClasses = Set(SubstanceStore.shared.classContexts().compactMap(\.category))
        #expect(!withClasses.isEmpty, "no class contexts in the bundled database")
        let missing = withClasses.filter { $0.classSummary == nil }.map(\.rawValue).sorted()
        #expect(missing.isEmpty, "category has class groups but no summary card: \(missing)")
    }

    @Test
    func `A summary is prose, not a stub`() {
        // Guards the failure where a case is added to satisfy the test above
        // and left as a placeholder.
        for category in SubstanceCategory.allCases {
            guard let summary = category.classSummary else { continue }
            let text = String(localized: summary)
            #expect(text.count > 40, "\(category.rawValue) summary is too short to be real: \(text)")
            #expect(!text.localizedCaseInsensitiveContains("TODO"))
        }
    }

    @Test
    func `A family with one group links straight to it, not to a list of one`() {
        // Seven categories have exactly one class write-up. For those, the
        // group list is a single row standing between the reader and the only
        // thing behind it.
        let single = SubstanceCategory.allCases.filter {
            SubstanceStore.shared.classContexts(in: $0).count == 1
        }
        #expect(!single.isEmpty, "no single-group category in the bundled database")
        for category in single {
            let only = SubstanceStore.shared.classContexts(in: category).first
            #expect(only?.title.isEmpty == false, "\(category.rawValue)'s only group has no name to show")
        }
    }
}
