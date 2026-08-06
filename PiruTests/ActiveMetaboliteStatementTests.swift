import Testing
@testable import Piru

/// The "Also Active" headline resolver.
///
/// Every case here is a **real catalog row**, with the stored values inlined, so
/// the suite doubles as a record of which claim each substance produces. The
/// resolver previously fired its duration headline on a bare half-life ratio,
/// which stated something false for cotinine, desmethylsertraline,
/// didesmethylcitalopram, psilocin, d-amphetamine, cocaethylene and mCPP; those
/// are the negative cases below.
@Suite("ActiveMetabolite statement")
struct ActiveMetaboliteStatementTests {
    // MARK: Fixtures

    private static func metabolite(
        _ name: String,
        substanceName: String? = nil,
        enzymes: [String] = ["CYP3A4"],
        halfLifeMinutes: Double? = nil,
        formationFractionPct: Double? = nil,
        mechanism: SubstanceStore.MetaboliteMechanism = .scaled,
        potencies: [ActiveMetabolite.Potency] = [],
    ) -> ActiveMetabolite {
        ActiveMetabolite(
            name: name,
            substanceName: substanceName,
            enzymes: enzymes,
            halfLifeMinutes: halfLifeMinutes,
            formationFractionPct: formationFractionPct,
            formationFractionByRoute: [:],
            mechanism: mechanism,
            potencies: potencies,
            sourceSlug: "peer-review-primary",
            doi: nil,
            pmid: nil,
            hasSuppressedMagnitude: false,
        )
    }

    private static func potency(
        _ pct: Double,
        _ basis: SubstanceStore.MetabolitePotencyBasis,
        target: String? = nil,
    ) -> ActiveMetabolite.Potency {
        ActiveMetabolite.Potency(pct: pct, basis: basis, target: target)
    }

    private static func isOutlasting(_ statement: MetaboliteStatement) -> Bool {
        if case .outlastsDuration = statement { return true }
        return false
    }

    // MARK: A measured-small potency vetoes the duration claim

    @Test
    func `Cotinine does not claim to outlast nicotine's duration`() {
        // Nicotine → cotinine: metabolite t½ 1020 min against a ~90 min duration
        // and a 150 min parent t½ — it clears every purely temporal test. The
        // 1 % receptor affinity in the same row is what disqualifies it.
        let cotinine = Self.metabolite(
            "cotinine", enzymes: ["CYP2A6"], halfLifeMinutes: 1_020,
            potencies: [Self.potency(1, .receptorAffinity, target: "nAChR")],
        )

        #expect(!cotinine.isMateriallyActive)
        let statement = cotinine.statement(
            parentName: "Nicotine", parentHalfLifeMinutes: 150, parentDurationMinutes: 90,
        )
        #expect(!Self.isOutlasting(statement))
    }

    @Test
    func `Desmethylsertraline does not claim to outlast sertraline`() {
        let norsertraline = Self.metabolite(
            "desmethylsertraline", halfLifeMinutes: 3_960,
            potencies: [Self.potency(4, .receptorAffinity, target: "SERT")],
        )

        #expect(!norsertraline.isMateriallyActive)
        // No duration profile — an SSRI. The half-life fallback must be gated
        // too, or this reappears as `.persistsBeyondParent`.
        let statement = norsertraline.statement(
            parentName: "Sertraline", parentHalfLifeMinutes: 1_560, parentDurationMinutes: nil,
        )
        if case .persistsBeyondParent = statement {
            Issue.record("A 4 %-potency metabolite must not carry a persistence claim")
        }
    }

    @Test
    func `A metabolite nobody measured and we do not stock makes no claim`() {
        // Citalopram → didesmethylcitalopram: t½ 6000 min, no potency recorded,
        // not carried as a substance. Nothing supports a claim about effects.
        let didesmethyl = Self.metabolite("didesmethylcitalopram", halfLifeMinutes: 6_000)

        #expect(!didesmethyl.isMateriallyActive)
        let statement = didesmethyl.statement(
            parentName: "Citalopram", parentHalfLifeMinutes: 2_160, parentDurationMinutes: nil,
        )
        guard case .relationshipOnly = statement else {
            Issue.record("Expected relationshipOnly, got \(statement)")
            return
        }
    }

    @Test
    func `A metabolite we stock as its own drug counts as active without a potency`() {
        // Carisoprodol → meprobamate: no potency recorded, but meprobamate is a
        // controlled sedative in its own right with its own dose ladder.
        let meprobamate = Self.metabolite(
            "meprobamate", substanceName: "Meprobamate", halfLifeMinutes: 540,
        )
        #expect(meprobamate.isMateriallyActive)
    }

    // MARK: Prodrugs — the duration table already describes the metabolite

    @Test
    func `Psilocin does not claim to outlast psilocybin's duration`() {
        // The case that motivated measuring against the displayed duration
        // rather than the parent's half-life: psilocybin is inert with a 50 min
        // t½, so psilocin cleared `2 × parent` trivially — while the 6–8 h
        // duration table above the card was already psilocin's.
        let psilocin = Self.metabolite(
            "psilocin", substanceName: "Psilocin", enzymes: ["Alkaline phosphatase"],
            halfLifeMinutes: 150, potencies: [Self.potency(100, .clinical)],
        )

        #expect(psilocin.isMateriallyActive)
        let statement = psilocin.statement(
            parentName: "Psilocybin", parentHalfLifeMinutes: 50, parentDurationMinutes: 420,
        )
        #expect(!Self.isOutlasting(statement))
    }

    @Test
    func `Dextroamphetamine does not claim to outlast lisdexamfetamine's duration`() {
        let dAmphetamine = Self.metabolite(
            "d-amphetamine", substanceName: "Dextroamphetamine", enzymes: ["Peptidase"],
            halfLifeMinutes: 582, formationFractionPct: 100,
            potencies: [Self.potency(100, .clinical)],
        )

        let statement = dAmphetamine.statement(
            parentName: "Lisdexamfetamine", parentHalfLifeMinutes: 70, parentDurationMinutes: 720,
        )
        #expect(!Self.isOutlasting(statement))
    }

    // MARK: The claims that should survive

    @Test
    func `Nordazepam still says it outlasts diazepam`() {
        let nordazepam = Self.metabolite(
            "nordazepam", enzymes: ["CYP2C19/CYP3A4"], halfLifeMinutes: 6_000,
            potencies: [Self.potency(100, .clinical)],
        )

        let statement = nordazepam.statement(
            parentName: "Diazepam", parentHalfLifeMinutes: 2_760, parentDurationMinutes: 360,
        )
        #expect(Self.isOutlasting(statement))
    }

    @Test
    func `Norfluoxetine persists, worded for a substance with no duration table`() {
        // The founding case. SSRIs carry no acute duration profile, so the
        // sentence must not point at a "duration above" that isn't rendered.
        let norfluoxetine = Self.metabolite(
            "norfluoxetine", enzymes: ["CYP2D6"], halfLifeMinutes: 12_384,
            potencies: [Self.potency(100, .inVitro)],
        )

        let statement = norfluoxetine.statement(
            parentName: "Fluoxetine", parentHalfLifeMinutes: 2_880, parentDurationMinutes: nil,
        )
        guard case .persistsBeyondParent = statement else {
            Issue.record("Expected persistsBeyondParent, got \(statement)")
            return
        }
    }

    @Test
    func `A 20 % metabolite clears the materiality threshold`() {
        // Bupropion → threohydrobupropion. The threshold sits in an empty band:
        // measured potencies in the catalog are 1 %, 4 %, then 20 % and up.
        let threohydro = Self.metabolite(
            "threohydrobupropion", halfLifeMinutes: 2_220,
            potencies: [Self.potency(20, .inVitro)],
        )
        #expect(threohydro.isMateriallyActive)
    }

    // MARK: Divergent pharmacology outranks the duration story

    @Test
    func `mCPP is described as different, not as trazodone lasting longer`() {
        // mCPP is anxiogenic. "The same effects, drawn out" inverts it — which
        // is what the old ordering produced, because it tested duration first.
        let mCPP = Self.metabolite(
            "mCPP", halfLifeMinutes: 840, mechanism: .divergent,
            potencies: [Self.potency(100, .receptorAffinity, target: "SERT")],
        )

        let statement = mCPP.statement(
            parentName: "Trazodone", parentHalfLifeMinutes: 420, parentDurationMinutes: 540,
        )
        guard case .divergent = statement else {
            Issue.record("Expected divergent, got \(statement)")
            return
        }
    }

    @Test
    func `A divergent metabolite never shows a bare clinical multiplier`() {
        // Demerol → normeperidine, 50 % clinical. Printing "about 0.5× as
        // strong" under "acts differently" contradicts the headline and
        // quantifies the axis that did not change — normeperidine matters
        // because it is a convulsant, not because of its analgesia.
        let normeperidine = Self.metabolite(
            "normeperidine", halfLifeMinutes: 1_200, mechanism: .divergent,
            potencies: [Self.potency(50, .clinical)],
        )

        let statement = normeperidine.statement(
            parentName: "Demerol", parentHalfLifeMinutes: 240, parentDurationMinutes: 300,
        )
        #expect(normeperidine.secondaryPotency(for: statement) == nil)
    }

    @Test
    func `A divergent metabolite still shows a hedged affinity measurement`() {
        // Tramadol → M1 at 200× MOR affinity. It carries its own hedge and
        // cannot be misread as clinical strength, so it survives.
        let m1 = Self.metabolite(
            "O-desmethyltramadol", substanceName: "O-DSMT", enzymes: ["CYP2D6"],
            halfLifeMinutes: 402, mechanism: .divergent,
            potencies: [Self.potency(20_000, .receptorAffinity, target: "MOR")],
        )

        let statement = m1.statement(
            parentName: "Tramadol", parentHalfLifeMinutes: 336, parentDurationMinutes: 420,
        )
        #expect(m1.secondaryPotency(for: statement) != nil)
    }

    // MARK: "Dose for dose" requires knowing what fraction converts

    @Test
    func `Codeine's 10× is stated molecule-for-molecule, not dose-for-dose`() {
        // The most dangerous card in the catalog. 1000 % clinical is right
        // between the molecules and badly wrong between doses: only ~5–10 % of a
        // codeine dose is demethylated, so "10× as strong, dose for dose"
        // inverts the truth. `formation_fraction_pct` is NULL here, which is
        // exactly the condition that must block the dose claim.
        let morphine = Self.metabolite(
            "morphine", substanceName: "Morphine", enzymes: ["CYP2D6"],
            halfLifeMinutes: 174, potencies: [Self.potency(1_000, .clinical)],
        )

        let statement = morphine.statement(
            parentName: "Codeine", parentHalfLifeMinutes: 165, parentDurationMinutes: 300,
        )
        guard case let .strongerMolecule(ratio, _, _, convertedPct) = statement else {
            Issue.record("Expected strongerMolecule, got \(statement)")
            return
        }
        #expect(ratio == 10)
        // Codeine records no formation fraction, so the card must say the share
        // is unrecorded rather than imply one.
        #expect(convertedPct == nil)
    }

    @Test
    func `Oxycodone names the 11 % that becomes oxymorphone`() {
        // Oxycodone → oxymorphone carries both a 1000 % clinical ratio and an
        // 11 % formation fraction. Stating the ratio alone reads as a dose
        // claim; stating the fraction beside it is what makes it honest, and it
        // is the difference between this card and codeine's.
        let oxymorphone = Self.metabolite(
            "oxymorphone", substanceName: "Oxymorphone", enzymes: ["CYP2D6"],
            formationFractionPct: 11,
            potencies: [
                Self.potency(1_000, .clinical),
                Self.potency(4_000, .receptorAffinity, target: "MOR"),
            ],
        )

        let statement = oxymorphone.statement(
            parentName: "Oxycodone", parentHalfLifeMinutes: 210, parentDurationMinutes: 300,
        )
        guard case let .strongerMolecule(ratio, _, _, convertedPct) = statement else {
            Issue.record("Expected strongerMolecule, got \(statement)")
            return
        }
        #expect(ratio == 10)
        #expect(convertedPct == 11)
        // The affinity figure follows as a hedged secondary; the two bases must
        // never merge into one number.
        #expect(oxymorphone.secondaryPotency(for: statement)?.basis == .receptorAffinity)
    }

    @Test
    func `A fully-converting prodrug may still claim dose equivalence`() {
        let dAmphetamine = Self.metabolite(
            "d-amphetamine", substanceName: "Dextroamphetamine", enzymes: ["Peptidase"],
            halfLifeMinutes: 582, formationFractionPct: 100,
            potencies: [Self.potency(100, .clinical)],
        )

        let statement = dAmphetamine.statement(
            parentName: "Lisdexamfetamine", parentHalfLifeMinutes: 70, parentDurationMinutes: 720,
        )
        guard case .comparable = statement else {
            Issue.record("Expected comparable, got \(statement)")
            return
        }
    }

    // MARK: Which metabolites earn a section of their own

    @Test
    func `Only a metabolite that outlives the dose earns its own section`() {
        // Oxymorphone is oxycodone's principal, expected pathway and its 10 : 1
        // ratio is textbook — reference data, not news, and the Metabolism
        // disclosure below already carries it. Promoting it to a headline
        // overstates it.
        let oxymorphone = Self.metabolite(
            "oxymorphone", substanceName: "Oxymorphone", enzymes: ["CYP2D6"],
            formationFractionPct: 11, potencies: [Self.potency(1_000, .clinical)],
        )
        #expect(!oxymorphone.earnsOwnSection(parentHalfLifeMinutes: 210, parentDurationMinutes: 300))

        // Nordazepam is why a diazepam dose is still working tomorrow, which is
        // readable nowhere else on the screen.
        let nordazepam = Self.metabolite(
            "nordazepam", enzymes: ["CYP2C19/CYP3A4"], halfLifeMinutes: 6_000,
            potencies: [Self.potency(100, .clinical)],
        )
        #expect(nordazepam.earnsOwnSection(parentHalfLifeMinutes: 2_760, parentDurationMinutes: 360))

        // Same for a chronic medication with no duration table at all.
        let norfluoxetine = Self.metabolite(
            "norfluoxetine", enzymes: ["CYP2D6"], halfLifeMinutes: 12_384,
            potencies: [Self.potency(100, .inVitro)],
        )
        #expect(norfluoxetine.earnsOwnSection(parentHalfLifeMinutes: 2_880, parentDurationMinutes: nil))

        // A divergent metabolite is interesting but is not a duration fact.
        let m1 = Self.metabolite(
            "O-desmethyltramadol", substanceName: "O-DSMT", enzymes: ["CYP2D6"],
            halfLifeMinutes: 402, mechanism: .divergent,
            potencies: [Self.potency(20_000, .receptorAffinity, target: "MOR")],
        )
        #expect(!m1.earnsOwnSection(parentHalfLifeMinutes: 336, parentDurationMinutes: 420))
    }

    // MARK: Polymorphic conversion

    @Test
    func `CYP2D6 and CYP2C19 conversion is flagged as varying between people`() {
        #expect(Self.metabolite("morphine", enzymes: ["CYP2D6"]).conversionVariesByGenetics)
        #expect(Self.metabolite("nordazepam", enzymes: ["CYP2C19/CYP3A4"]).conversionVariesByGenetics)
        #expect(Self.metabolite("noribogaine", enzymes: ["CYP2D6 (O-demethylation)"])
            .conversionVariesByGenetics)
        #expect(!Self.metabolite("norquetiapine", enzymes: ["CYP3A4"]).conversionVariesByGenetics)
    }
}
