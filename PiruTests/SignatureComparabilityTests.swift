import Foundation
import Testing
@testable import Piru

/// The comparability gate is the whole reason the class signatures are allowed to exist. Every test
/// here stands for a rendering bug that shipped, or nearly did:
///
/// - MDMA rendered as a **95 % noradrenaline drug** off one mixed leg (a binding Kᵢ plotted against
///   a release EC₅₀), which is why the basis half of the gate is not optional.
/// - Morphine reads 94 % of DAMGO by Emax and **τ 0.18**, so an Emax-only axis makes every clinical
///   opioid a full agonist.
/// - ~20 nitazene/fentanyl rows carry a bare `intrinsic_activity_pct` of 100 with no
///   `comparable_set`; they must render hollow, never as full-activation ticks.
@Suite("Signature comparability gate")
struct SignatureComparabilityTests {
    // MARK: - Fixtures

    private static func leg(
        _ id: String,
        _ substance: String,
        _ target: SignatureTarget,
        ki: Double? = nil,
        ec50: Double? = nil,
        ic50: Double? = nil,
        tau: Double? = nil,
        intrinsic: Double? = nil,
        set: String? = nil,
        citation: Int64? = nil,
        species: String? = "human",
        assaySystem: String? = nil,
        reference: String? = nil,
        action: String? = nil,
    ) -> SignatureLeg {
        SignatureLeg(
            id: id, substanceName: substance, target: target, action: action,
            kiNm: ki, ec50Nm: ec50, ic50Nm: ic50,
            relativeTau: tau, intrinsicActivityPct: intrinsic, emaxPct: nil,
            comparableSet: set, citationID: citation, species: species,
            assaySystem: assaySystem, referenceAgonist: reference,
        )
    }

    // MARK: - The basis half of the gate

    @Test
    func `Mixed-basis legs are rejected`() {
        // The exact MDMA shape: a binding Kᵢ leg beside two release EC₅₀ legs, one citation.
        let legs = [
            Self.leg("1", "MDMA", .dat, ki: 22_000, citation: 1),
            Self.leg("2", "MDMA", .net, ec50: 77.4, citation: 1),
            Self.leg("3", "MDMA", .sert, ec50: 5_630, citation: 1),
        ]
        #expect(SignatureComparability.admits(legs) == nil)
    }

    @Test
    func `Single-basis legs from one citation are admitted`() {
        let legs = [
            Self.leg("1", "MDMA", .dat, ec50: 51.2, citation: 2),
            Self.leg("2", "MDMA", .net, ec50: 54.1, citation: 2),
            Self.leg("3", "MDMA", .sert, ec50: 49.6, citation: 2),
        ]
        let group = SignatureComparability.admits(legs)
        #expect(group?.basis == .ec50)
        #expect(group?.key == .citation(2, species: "human", assaySystem: nil))
    }

    @Test
    func `Legs from different citations are rejected even on one basis`() {
        let legs = [
            Self.leg("1", "MDMA", .dat, ec50: 51.2, citation: 2),
            Self.leg("2", "MDMA", .net, ec50: 54.1, citation: 3),
        ]
        #expect(SignatureComparability.admits(legs) == nil)
    }

    @Test
    func `Same citation but different species are separate groups`() {
        let legs = [
            Self.leg("1", "MDMA", .sert, ec50: 49.6, citation: 5, species: "rat"),
            Self.leg("2", "MDMA", .dat, ec50: 51.2, citation: 5, species: "rat"),
            Self.leg("3", "MDMA", .net, ec50: 54.1, citation: 5, species: "human"),
        ]
        #expect(SignatureComparability.admits(legs) == nil)
        let groups = SignatureComparability.partition(legs)
        #expect(groups.count == 2)
    }

    @Test
    func `Same citation and species but different assay systems are separate groups`() {
        let legs = [
            Self.leg("1", "MDMA", .sert, ec50: 49.6, citation: 5, species: "human", assaySystem: "synaptosome"),
            Self.leg("2", "MDMA", .dat, ec50: 51.2, citation: 5, species: "human", assaySystem: "synaptosome"),
            Self.leg("3", "MDMA", .net, ec50: 54.1, citation: 5, species: "human", assaySystem: "recombinant"),
        ]
        #expect(SignatureComparability.admits(legs) == nil)
        let groups = SignatureComparability.partition(legs)
        #expect(groups.count == 2)
    }

    @Test
    func `An uncited leg is never plottable`() {
        let legs = [Self.leg("1", "MDMA", .dat, ec50: 51.2)]
        #expect(SignatureComparability.admits(legs) == nil)
        #expect(SignatureComparability.partition(legs).isEmpty)
    }

    @Test
    func `A τ value and an intrinsic-activity value never share a group`() {
        // Morphine: τ 0.18 and 94 % of DAMGO are the same drug and incompatible axes.
        let legs = [
            Self.leg("1", "Morphine", .mu, tau: 0.18, set: "panel"),
            Self.leg("2", "Buprenorphine", .mu, intrinsic: 66, set: "panel"),
        ]
        #expect(SignatureComparability.admits(legs) == nil)
        // Partitioning yields two single-substance groups, not one ladder.
        let groups = SignatureComparability.partition(legs)
        #expect(groups.count == 2)
        #expect(groups.allSatisfy { $0.substanceNames.count == 1 })
    }

    // MARK: - comparable_set wins

    @Test
    func `A declared comparable set outranks the citation id`() {
        // Two papers, one curated panel: the panel is what makes them comparable.
        let legs = [
            Self.leg("1", "Morphine", .mu, tau: 0.18, set: "manandhar", citation: 10),
            Self.leg("2", "Oxycodone", .mu, tau: 0.16, set: "manandhar", citation: 11),
        ]
        let group = SignatureComparability.admits(legs)
        #expect(group?.key == .panel("manandhar"))
        #expect(group?.key.isDeclaredPanel == true)
        #expect(group?.substanceNames.count == 2)
    }

    @Test
    func `A panel row is not merged with a bare citation row that shares its paper`() {
        // Rows left out of a declared panel were left out on purpose; a shared paper must not
        // re-admit them.
        let legs = [
            Self.leg("1", "Morphine", .mu, intrinsic: 93, set: "toll-1998", citation: 20),
            Self.leg("2", "Dihydromorphine", .mu, intrinsic: 109, citation: 20),
        ]
        #expect(SignatureComparability.admits(legs) == nil)
        #expect(SignatureComparability.partition(legs).count == 2)
    }

    // MARK: - Target normalization

    @Test
    func `Target qualifiers are stripped but multi-target rows never match`() {
        #expect(SignatureTarget.normalized("MOR (μ1)") == .mu)
        #expect(SignatureTarget.normalized("CB1 (human)") == .cannabinoid1)
        #expect(SignatureTarget.normalized("μ-opioid receptor (human, hMOR)") == .mu)
        #expect(SignatureTarget.normalized("5-HT2A (rat cortex)") == .serotonin2A)
        #expect(SignatureTarget.normalized("NMDA (MK-801 site, racemate)") == .nmda)
        // Four receptors in one row is not one leg.
        #expect(SignatureTarget.normalized("MOR / DOR / KOR / NOP") == nil)
        #expect(SignatureTarget.normalized("TAAR1") == nil)
    }
}

/// The four renderings, resolved against synthetic legs — the gate's consequences rather than the
/// gate itself.
@Suite("Class signatures")
struct ClassSignatureTests {
    private static func leg(
        _ id: String,
        _ substance: String,
        _ target: SignatureTarget,
        ki: Double? = nil,
        ec50: Double? = nil,
        ic50: Double? = nil,
        tau: Double? = nil,
        intrinsic: Double? = nil,
        set: String? = nil,
        citation: Int64? = nil,
        species: String? = "human",
        assaySystem: String? = nil,
        reference: String? = nil,
        action: String? = nil,
    ) -> SignatureLeg {
        SignatureLeg(
            id: id, substanceName: substance, target: target, action: action,
            kiNm: ki, ec50Nm: ec50, ic50Nm: ic50,
            relativeTau: tau, intrinsicActivityPct: intrinsic, emaxPct: nil,
            comparableSet: set, citationID: citation, species: species,
            assaySystem: assaySystem, referenceAgonist: reference,
        )
    }

    // MARK: - Hollow markers

    @Test
    func `A bare intrinsic activity with no panel renders hollow`() {
        // The nitazene shape: 100 % of DAMGO, cited, but measured beside nothing.
        let legs = [
            Self.leg("1", "Metonitazene", .mu, intrinsic: 95.3, citation: 30, reference: "DAMGO", action: "agonist"),
            Self.leg("2", "Isotonitazene", .mu, intrinsic: 103.5, citation: 31, reference: "DAMGO", action: "agonist"),
            Self.leg("3", "Protonitazene", .mu, intrinsic: 93.0, citation: 32, reference: "DAMGO", action: "agonist"),
        ]
        guard case let .efficacy(model)? = ClassSignature.resolve(
            substanceName: "Metonitazene", category: .opioid, legs: legs,
        ) else {
            Issue.record("expected an efficacy axis")
            return
        }
        #expect(model.isGated == false)
        #expect(model.marks.allSatisfy { !$0.isGated })
        #expect(model.focus.name == "Metonitazene")
    }

    @Test
    func `A paper that calls four analogues "full agonists" is not a ladder`() {
        // Citation 1311's shape: four fentanyl analogues, all a bare 100 % of DAMGO, no panel tag.
        // They share a citation and a basis, so the raw gate would admit them — but four identical
        // full-activation ticks is the reading that makes every opioid a full agonist, so a
        // documented class never counts as a comparable measurement.
        let legs = [
            Self.leg("1", "Carfentanil", .mu, intrinsic: 100, citation: 1_311, reference: "DAMGO", action: "agonist"),
            Self.leg("2", "Alfentanil", .mu, intrinsic: 100, citation: 1_311, reference: "DAMGO", action: "agonist"),
            Self.leg("3", "Remifentanil", .mu, intrinsic: 100, citation: 1_311, reference: "DAMGO", action: "agonist"),
            Self.leg("4", "Lofentanil", .mu, intrinsic: 100, citation: 1_311, reference: "DAMGO", action: "agonist"),
        ]
        guard case let .efficacy(model)? = ClassSignature.resolve(
            substanceName: "Carfentanil", category: .opioid, legs: legs,
        ) else {
            Issue.record("expected an efficacy axis")
            return
        }
        #expect(model.isGated == false)
        #expect(model.marks.allSatisfy { !$0.isGated })
    }

    @Test
    func `A real measured series from one paper does gate`() {
        // Citation 1287's shape: thirteen nitazenes with genuinely varied fitted values.
        let legs = [
            Self.leg("1", "Metonitazene", .mu, intrinsic: 95.3, citation: 1_287, reference: "DAMGO", action: "agonist"),
            Self.leg("2", "Protonitazene", .mu, intrinsic: 93.0, citation: 1_287, reference: "DAMGO", action: "agonist"),
            Self.leg("3", "Clonitazene", .mu, intrinsic: 104.2, citation: 1_287, reference: "DAMGO", action: "agonist"),
        ]
        guard case let .efficacy(model)? = ClassSignature.resolve(
            substanceName: "Metonitazene", category: .opioid, legs: legs,
        ) else {
            Issue.record("expected an efficacy axis")
            return
        }
        #expect(model.isGated)
        // Hoisted out of `#expect`: SwiftFormat's preferKeyPath rewrites the closure
        // form to `allSatisfy(\.isGated)`, and inside the macro expansion the compiler
        // can no longer prove the `rethrows` call non-throwing ("call can throw, but it
        // is not marked with 'try'"). A plain `let` satisfies both the formatter and
        // the macro. `map(\.x)` inside `#expect` is fine — this bites `rethrows` only.
        let everyMarkGated = model.marks.allSatisfy(\.isGated)
        #expect(everyMarkGated)
    }

    @Test
    func `A panel member renders solid and its cross-study peers render hollow`() {
        let legs = [
            Self.leg("1", "Morphine", .mu, intrinsic: 93, set: "toll", citation: 40, reference: "DAMGO", action: "agonist"),
            Self.leg("2", "Fentanyl", .mu, intrinsic: 100, set: "toll", citation: 40, reference: "DAMGO", action: "agonist"),
            Self.leg("3", "Metonitazene", .mu, intrinsic: 95.3, citation: 41, reference: "DAMGO", action: "agonist"),
        ]
        guard case let .efficacy(model)? = ClassSignature.resolve(
            substanceName: "Morphine", category: .opioid, legs: legs,
        ) else {
            Issue.record("expected an efficacy axis")
            return
        }
        #expect(model.isGated)
        #expect(model.provenance.isDeclaredPanel)
        #expect(model.marks.first { $0.name == "Fentanyl" }?.isGated == true)
        #expect(model.marks.first { $0.name == "Metonitazene" }?.isGated == false)
    }

    @Test
    func `τ is preferred over intrinsic activity when both panels contain the compound`() {
        // Morphine sits in a τ panel and an Emax panel. τ is intrinsic efficacy and
        // system-independent, so it wins — and the axis then reads 18 %, not 93 %.
        let legs = [
            Self.leg("1", "Morphine", .mu, tau: 0.18, set: "tau-panel", citation: 50, reference: "DAMGO"),
            Self.leg("2", "Oxycodone", .mu, tau: 0.16, set: "tau-panel", citation: 50, reference: "DAMGO"),
            Self.leg("3", "Morphine", .mu, intrinsic: 93, set: "emax-panel", citation: 51, reference: "DAMGO"),
            Self.leg("4", "Fentanyl", .mu, intrinsic: 100, set: "emax-panel", citation: 51, reference: "DAMGO"),
        ]
        guard case let .efficacy(model)? = ClassSignature.resolve(
            substanceName: "Morphine", category: .opioid, legs: legs,
        ) else {
            Issue.record("expected an efficacy axis")
            return
        }
        #expect(model.provenance.basis == .tau)
        #expect(abs(model.focus.percent - 18) < 0.001)
        #expect(model.marks.contains { $0.name == "Fentanyl" } == false)
    }

    @Test
    func `A lone efficacy value degrades to a static readout`() {
        let legs = [
            Self.leg("1", "MT-45", .mu, intrinsic: 80, citation: 60, reference: "DAMGO", action: "agonist"),
        ]
        guard case let .efficacy(model)? = ClassSignature.resolve(
            substanceName: "MT-45", category: .opioid, legs: legs,
        ) else {
            Issue.record("expected an efficacy axis")
            return
        }
        #expect(model.isStaticReadout)
    }

    // MARK: - Balance

    @Test
    func `The balance needs both receptors from one experiment`() {
        let split = [
            Self.leg("1", "Mescaline", .serotonin1A, ki: 1_841, set: "pdsp", citation: 70),
            Self.leg("2", "Mescaline", .serotonin2A, ki: 6_300, citation: 71),
        ]
        guard case let .balance(model)? = ClassSignature.resolve(
            substanceName: "Mescaline", category: .psychedelic, legs: split,
        ) else {
            Issue.record("expected a balance rendering")
            return
        }
        // No arc: the 5-HT2A value stands alone and the card says why.
        #expect(model.focus == nil)
        #expect(model.withheldReason != nil)
    }

    @Test
    func `5-MeO-DMT reads 1A-selective from one panel`() {
        let legs = [
            Self.leg("1", "5-MeO-DMT", .serotonin1A, ki: 2.5, set: "panel", citation: 80),
            Self.leg("2", "5-MeO-DMT", .serotonin2A, ki: 250, set: "panel", citation: 80),
            Self.leg("3", "Psilocin", .serotonin1A, ki: 152, set: "panel", citation: 80),
            Self.leg("4", "Psilocin", .serotonin2A, ki: 49, set: "panel", citation: 80),
        ]
        guard case let .balance(model)? = ClassSignature.resolve(
            substanceName: "5-MeO-DMT", category: .psychedelic, legs: legs,
        ) else {
            Issue.record("expected a balance rendering")
            return
        }
        #expect(model.focus?.ratio == 100)
        #expect(model.ratioText == "100× 1A")
        // Psilocin is the mirror case and sits on the 5-HT2A side of parity.
        #expect((model.ticks.first { $0.name == "Psilocin" }?.position ?? 1) < 0.5)
        #expect((model.focus?.position ?? 0) > 0.5)
    }

    // MARK: - Ternary

    @Test
    func `MDMA yields two triples, a release basis and a blocker basis`() {
        let legs = [
            // Baumann 2012, rat synaptosome release EC₅₀ — a complete triple.
            Self.leg("1", "MDMA", .sert, ec50: 49.6, citation: 1_446, species: "rat"),
            Self.leg("2", "MDMA", .dat, ec50: 51.2, citation: 1_446, species: "rat"),
            Self.leg("3", "MDMA", .net, ec50: 54.1, citation: 1_446, species: "rat"),
            // Simmler 2013, human uptake IC₅₀ — a second complete triple…
            Self.leg("4", "MDMA", .sert, ic50: 1_360, citation: 1_444),
            Self.leg("5", "MDMA", .dat, ic50: 17_000, citation: 1_444),
            Self.leg("6", "MDMA", .net, ic50: 447, citation: 1_444),
            // …whose own paper also carries the binding legs that must NOT join it.
            Self.leg("7", "MDMA", .dat, ec50: 22_000, citation: 1_444),
            Self.leg("8", "MDMA", .sert, ec50: 5_630, citation: 1_444),
        ]
        guard case let .ternary(model)? = ClassSignature.resolve(
            substanceName: "MDMA", category: .empathogen, legs: legs,
        ) else {
            Issue.record("expected a ternary")
            return
        }
        #expect(model.triples.count == 2)
        #expect(Set(model.triples.map(\.provenance.basis)) == [.ec50, .ic50])
        // The mixed pair (DAT EC₅₀ 22 µM against NET IC₅₀ 447 nM) never forms a third triangle:
        // that combination is what once rendered MDMA as 95 % noradrenergic.
        #expect(model.triples.allSatisfy { $0.focus.values.dat != 22_000 })
    }

    @Test
    func `A compound whose transporter rows share no basis plots nothing`() {
        let legs = [
            Self.leg("1", "Ghostamine", .sert, ec50: 100, citation: 90),
            Self.leg("2", "Ghostamine", .dat, ki: 200, citation: 90),
            Self.leg("3", "Ghostamine", .net, ic50: 300, citation: 91),
        ]
        // SERT EC₅₀, DAT Kᵢ, NET IC₅₀ are three different bases: no single study
        // measured all three the same way, so no triangle forms and the card is
        // withheld entirely rather than plotting a point built across bases.
        #expect(ClassSignature.resolve(
            substanceName: "Ghostamine", category: .stimulant, legs: legs,
        ) == nil)
    }

    @Test
    func `Potency share puts the strongest transporter nearest its vertex`() {
        // Methamphetamine: NET 12.3 / DAT 24.5 / SERT 736 nM — NET-leading, serotonin negligible.
        let shares = TransporterTernaryModel.Shares.potencyShare(sert: 736, dat: 24.5, net: 12.3)
        #expect(shares.net > shares.dat)
        #expect(shares.dat > shares.sert)
        #expect(abs(shares.sert + shares.dat + shares.net - 1) < 1e-9)
        #expect(shares.sert < 0.03)
    }

    // MARK: - No signature

    @Test
    func `Dissociatives resolve to no card, not an invented NMDA axis`() {
        let legs = [
            Self.leg("1", "Ketamine", .nmda, ki: 659, citation: 939, species: "rat"),
            Self.leg("2", "Ketamine", .nmda, ki: 300, citation: 940, species: "rat"),
            Self.leg("3", "Ketamine", .nmda, ic50: 600, citation: 941),
        ]
        // NMDA-block potency is contested even for ketamine and isn't the axis
        // that separates dissociatives subjectively, so the class shows no
        // signature card at all — its receptor data lives in its own section.
        #expect(ClassSignature.resolve(
            substanceName: "Ketamine", category: .dissociative, legs: legs,
        ) == nil)
    }

    @Test
    func `A category with no signature resolves to nothing`() {
        #expect(ClassSignature.family(for: .supplement) == nil)
        #expect(ClassSignature.resolve(substanceName: "Vitamin D", category: .supplement, legs: []) == nil)
    }
}

/// The gate against the *shipped* database — the numbers the renderings actually light up with.
/// These are the coverage checks `substance-detail-data-issues.md` asks for: a signature that
/// quietly loses its data should fail here rather than render a blank card.
@Suite("Class signatures over the bundled database")
struct ClassSignatureDatabaseTests {
    @Test
    @MainActor
    func `MDMA carries two gated transporter triples in the shipped data`() {
        let legs = SubstanceStore.shared.signatureLegs(family: .transporters)
        guard case let .ternary(model)? = ClassSignature.resolve(
            substanceName: "MDMA", category: .empathogen, legs: legs,
        ) else {
            Issue.record("MDMA lost its gated transporter triples")
            return
        }
        #expect(model.triples.count >= 2)
        #expect(Set(model.triples.map(\.provenance.basis)).count >= 2)
    }

    @Test
    @MainActor
    func `Morphine's efficacy axis reads τ, not Emax`() {
        let legs = SubstanceStore.shared.signatureLegs(family: .muOpioid)
        guard case let .efficacy(model)? = ClassSignature.resolve(
            substanceName: "Morphine", category: .opioid, legs: legs,
        ) else {
            Issue.record("Morphine lost its efficacy axis")
            return
        }
        #expect(model.provenance.basis == .tau)
        #expect(model.isGated)
        // τ 0.18 of DAMGO — an Emax-only read would put this at 93-94 %.
        #expect(model.focus.percent < 30)
    }

    @Test
    @MainActor
    func `5-MeO-DMT's balance is 5-HT1A-dominant`() {
        let legs = SubstanceStore.shared.signatureLegs(family: .serotonin)
        guard case let .balance(model)? = ClassSignature.resolve(
            substanceName: "5-MeO-DMT", category: .psychedelic, legs: legs,
        ) else {
            Issue.record("5-MeO-DMT lost its balance rendering")
            return
        }
        #expect(model.focus != nil)
        #expect((model.focus?.ratio ?? 0) > 10)
    }

    @Test
    @MainActor
    func `Ketamine shows no dissociative signature card`() {
        let legs = SubstanceStore.shared.signatureLegs(family: .nmda)
        #expect(ClassSignature.resolve(
            substanceName: "Ketamine", category: .dissociative, legs: legs,
        ) == nil)
    }

    @Test
    @MainActor
    func `Sertraline's triangle is the blocker basis`() {
        let legs = SubstanceStore.shared.signatureLegs(family: .transporters)
        guard case let .ternary(model)? = ClassSignature.resolve(
            substanceName: "Sertraline", category: .antidepressant, legs: legs,
        ) else {
            Issue.record("Sertraline lost its ternary")
            return
        }
        #expect(model.triples.allSatisfy { $0.provenance.basis != .ec50 })
        #expect(model.triples[0].focus.shares.sert > 0.9)
    }

    /// The axis that explains why SCRAs hurt people and cannabis mostly does not.
    ///
    /// It was hollow for a year because THC's three `comparable_set`s are all radioligand
    /// **binding** panels — Ki with no Emax — so nothing could gate. Yano 2023 (BRET Gαi
    /// engagement, HEK-293T, human CB1, everything normalised to CP-55,940) measured THC
    /// beside AM-2201 and 5F-MDMB-PICA in one experiment, which is what a gate needs.
    @Test
    @MainActor
    func `THC's CB1 efficacy axis gates against the SCRAs measured beside it`() {
        let legs = SubstanceStore.shared.signatureLegs(family: .cannabinoid1)
        guard case let .efficacy(model)? = ClassSignature.resolve(
            substanceName: "THC", category: .cannabinoid, legs: legs,
        ) else {
            Issue.record("THC lost its CB1 efficacy axis")
            return
        }
        #expect(model.isGated)
        // Partial, and far below the reference full agonist: 36.1 % of CP-55,940.
        #expect(model.focus.percent < 50)
        // A ladder needs peers actually measured beside it, or it is one fact and a caption.
        let solid = model.marks.filter(\.isGated)
        #expect(solid.count >= 3)
        #expect(solid.contains { $0.name == "THC" })
        // The whole point of the axis: the synthetics sit at or above full activation while
        // THC sits at a third of it. If this inverts, the card is telling the opposite story.
        #expect(solid.filter { $0.name != "THC" }.allSatisfy { $0.percent > model.focus.percent })
    }
}
