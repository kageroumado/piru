import Foundation
import GRDB
import Testing
@testable import Piru

/// The 5-HT2B heart-valve warning, gated end-to-end against the bundled DB.
///
/// The one binding-derived claim on the substance page that is a safety
/// statement rather than a description, with two bases: the substance's own
/// rows, and its class's declaration (`class_warnings`). The failure modes run
/// both ways: missing a class member nobody assayed, or crying wolf on a
/// micromolar row nobody's dose reaches.
@Suite("5-HT2B valvular warning")
@MainActor
struct ValvularAntitargetTests {
    private func hit(
        _ target: String, _ action: String,
        kiNm: Double? = nil, ec50Nm: Double? = nil, tier: Int? = nil,
    ) -> BindingHit {
        BindingHit(
            id: 0, substanceName: "x", target: target, targetBase: nil, action: action,
            kiNm: kiNm, ec50Nm: ec50Nm, ic50Nm: nil, species: nil,
            sourceSlug: "peer-review-primary", doi: nil, pmid: nil, affinityTier: tier,
        )
    }

    /// Every (class, member) pair a `valvulopathy-5ht2b` declaration reaches,
    /// and the members it names as excluded.
    private func declaredMembership() throws -> (members: [(slug: String, name: String)], excluded: Set<String>) {
        try SubstanceStore.shared.substancesDB.read { db in
            let members = try Row.fetchAll(db, sql: """
                SELECT c.slug, s.canonical_name
                  FROM class_warnings w
                  JOIN class_contexts c ON c.id = w.class_context_id
                  JOIN substance_classes sc ON sc.class_context_id = w.class_context_id
                  JOIN substances s ON s.id = sc.substance_id
                 WHERE w.kind = ?
                   AND NOT EXISTS (SELECT 1 FROM class_warning_exclusions x
                                    WHERE x.class_warning_id = w.id AND x.substance_id = s.id)
                 ORDER BY c.slug, s.canonical_name
            """, arguments: [ValvularWarning.kind]).map { (slug: $0[0] as String, name: $0[1] as String) }
            let excluded = try String.fetchAll(db, sql: """
                SELECT s.canonical_name FROM class_warning_exclusions x
                  JOIN substances s ON s.id = x.substance_id
            """)
            return (members, Set(excluded))
        }
    }

    @Test
    func `Partial agonism counts and antagonism never does`() {
        // 25B-NBOMe's real row: partialAgonist, Ki 0.5 nM. Pergolide and
        // norfenfluramine are partial agonists too — it is the mechanism.
        #expect(ValvularWarning.engagesAntitarget([hit("5-HT2B", "partialAgonist", kiNm: 0.5)]))
        #expect(ValvularWarning.engagesAntitarget([hit("5-HT2B", "agonist", ec50Nm: 140)]))
        // Cariprazine, phentermine, viloxazine — all block it.
        #expect(!ValvularWarning.engagesAntitarget([hit("5-HT2B", "antagonist", kiNm: 0.5)]))
    }

    @Test
    func `A micromolar row is not an antitarget`() {
        // 4-fluoroamphetamine, EC50 14.4 µM. Flagging this would put a heart-valve
        // warning on every compound ever assayed at the receptor.
        #expect(!ValvularWarning.engagesAntitarget([hit("5-HT2B", "partialAgonist", ec50Nm: 14_400)]))
        // A curated row with no measurement speaks through its tier; one with
        // neither says nothing at all.
        #expect(ValvularWarning.engagesAntitarget([hit("5-HT2B", "agonist", tier: 3)]))
        #expect(!ValvularWarning.engagesAntitarget([hit("5-HT2B", "agonist")]))
    }

    @Test
    func `Either basis raises the warning and neither leaves it absent`() {
        let declaration = ClassWarning(
            kind: ValvularWarning.kind, classSlug: "c", classTitle: "C", references: [],
        )
        let engaged = [hit("5-HT2B", "agonist", kiNm: 5)]
        #expect(ValvularWarning.resolve(bindings: engaged, classWarnings: [])?.engagedByBindings == true)
        let byClass = ValvularWarning.resolve(bindings: [], classWarnings: [declaration])
        #expect(byClass?.engagedByBindings == false)
        #expect(byClass?.declaringClass?.classSlug == "c")
        #expect(ValvularWarning.resolve(bindings: [], classWarnings: []) == nil)
        let otherKind = ClassWarning(kind: "something-else", classSlug: "c", classTitle: "C", references: [])
        #expect(ValvularWarning.resolve(bindings: [], classWarnings: [otherKind]) == nil)
    }

    @Test
    func `An engaging metabolite raises it and a non-engaging one does not`() {
        let engaging = MetaboliteBindings(name: "M", bindings: [hit("5-HT2B", "agonist", kiNm: 52)])
        let weak = MetaboliteBindings(name: "W", bindings: [hit("5-HT2B", "agonist", kiNm: 4_134)])
        #expect(ValvularWarning.resolve(bindings: [], metabolites: [weak, engaging], classWarnings: [])?
            .engagingMetabolite == "M")
        #expect(ValvularWarning.resolve(bindings: [], metabolites: [weak], classWarnings: []) == nil)
    }

    @Test
    func `Fenfluramine shows it through norfenfluramine`() async throws {
        // Fenfluramine binds 5-HT2B at 4,134 nM itself; norfenfluramine, the
        // metabolite it is cleared to, at 52.1 nM (Rothman 2000).
        await SubstanceStore.shared.ensureAllLoaded()
        #expect(!ValvularWarning.engagesAntitarget(SubstanceStore.shared.bindings(forSubstanceName: "Fenfluramine")))
        let warning = try #require(SubstanceLibrary.valvularWarning(for: "Fenfluramine"))
        #expect(!warning.engagedByBindings)
        #expect(warning.engagingMetabolite == "Norfenfluramine")
        #expect(SubstanceLibrary.valvularWarning(for: "Norfenfluramine")?.engagedByBindings == true)
    }

    @Test
    func `A parent whose active metabolites do not engage 5-HT2B shows nothing`() async {
        // Ketamine → norketamine is a carried, active metabolite with no 5-HT2B
        // agonism; tramadol → O-DSMT likewise.
        await SubstanceStore.shared.ensureAllLoaded()
        for parent in ["Ketamine", "Tramadol"] {
            let metabolites = SubstanceStore.shared.activeMetaboliteBindings(forSubstanceName: parent)
            #expect(!metabolites.isEmpty, "\(parent) should carry a linked active metabolite")
            #expect(SubstanceLibrary.valvularWarning(for: parent) == nil, "\(parent) should carry no warning")
        }
    }

    @Test
    func `Every member of a declaring class shows the warning`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let (members, excluded) = try declaredMembership()
        #expect(members.count > 100, "the declarations reach \(members.count) members; expected the five classes")
        for member in members {
            let warning = SubstanceLibrary.valvularWarning(for: member.name)
            #expect(warning != nil, "\(member.name) is in \(member.slug), which declares the warning")
            #expect(warning?.declaringClass?.references.isEmpty == false, "\(member.name)'s class cites nothing")
        }
        for name in excluded {
            #expect(
                SubstanceLibrary.valvularWarning(for: name)?.declaringClass == nil,
                "\(name) is excluded from its class's declaration",
            )
        }
    }

    @Test
    func `All 22 substances whose bindings engage 5-HT2B show the warning`() async {
        // The audit's list (guards.md class 8): only five of these reached the
        // flag while it lived on the monoamine card.
        await SubstanceStore.shared.ensureAllLoaded()
        let engaging = [
            "25B-NBOMe", "25C-NBOMe", "25D-NBOMe", "25E-NBOMe", "25H-NBOMe", "25I-NBOH", "25I-NBOMe",
            "25N-NBOMe", "2C-B", "2C-B-FLY", "5-APB", "5-APDB", "6-APB", "6-APDB", "Bromo-DragonFLY",
            "DOB", "DOC", "DOET", "DOI", "DOM", "LSD", "Psilocin",
        ]
        for name in engaging {
            let warning = SubstanceLibrary.valvularWarning(for: name)
            #expect(warning?.engagedByBindings == true, "\(name)'s own bindings engage 5-HT2B")
        }
    }

    @Test
    func `A binding-only substance shows it with no class behind it`() async throws {
        // 2C-B belongs to no class in the bundled DB; its own Ki carries it.
        await SubstanceStore.shared.ensureAllLoaded()
        let warning = try #require(SubstanceLibrary.valvularWarning(for: "2C-B"))
        #expect(warning.engagedByBindings)
        #expect(warning.declaringClass == nil)
    }

    @Test
    func `MDMA shows it through its class, not its own rows`() async throws {
        // MDMA has no 5-HT2B row strong enough to engage the criterion; its class
        // declares the warning on Setola 2003 and Droogmans 2007.
        await SubstanceStore.shared.ensureAllLoaded()
        let mdma = try #require(SubstanceStore.shared.lookup("MDMA"))
        #expect(!ValvularWarning.engagesAntitarget(SubstanceStore.shared.bindings(forSubstanceName: mdma.name)))
        let warning = try #require(SubstanceLibrary.valvularWarning(for: mdma.name))
        #expect(warning.declaringClass?.classSlug == "methylenedioxy-entactogens")
    }

    @Test
    func `Unassayed class members reach it, and the undeclared and excluded do not`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        // No 5-HT2B row of their own; the class carries them.
        for name in ["1P-LSD", "25B-NBOH", "2C-D", "4-AcO-DMT", "5-MAPB"] {
            let warning = SubstanceLibrary.valvularWarning(for: name)
            #expect(warning?.declaringClass != nil, "\(name) should inherit its class's warning")
        }
        // The amphetamines declare nothing (phentermine has no 5-HT2B activity);
        // the scalines are the exception in the cited assay.
        for name in ["Amphetamine", "Phentermine", "Escaline", "Myristicin"] {
            #expect(SubstanceLibrary.valvularWarning(for: name) == nil, "\(name) should carry no warning")
        }
    }
}
