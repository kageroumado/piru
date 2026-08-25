import Testing
@testable import Piru

/// The shared name-key mechanism the hardcoded pharmacology tables funnel
/// through, and the cross-table guarantees the unification rests on.
@Suite("PharmacologyNameKey")
struct PharmacologyNameKeyTests {
    @Test
    func `fold lowercases and trims whitespace and newlines`() {
        #expect(PharmacologyNameKey.fold("  Caffeine\n") == "caffeine")
        #expect(PharmacologyNameKey.fold("MDMA") == "mdma")
    }

    @Test
    func `resolve prefers a direct data key over an alias claiming the same spelling`() {
        let data = ["a": 1, "b": 2]
        let aliases = ["a": "b", "c": "b"]
        #expect(PharmacologyNameKey.resolve("a", in: data, aliases: aliases) == 1)
        #expect(PharmacologyNameKey.resolve(" A ", in: data, aliases: aliases) == 1)
        #expect(PharmacologyNameKey.resolve("c", in: data, aliases: aliases) == 2)
        #expect(PharmacologyNameKey.resolve("x", in: data, aliases: aliases) == nil)
    }

    @Test
    func `canonical maps an alias to its target and leaves other names folded`() {
        let aliases = ["xanax": "alprazolam"]
        #expect(PharmacologyNameKey.canonical("Xanax", aliases: aliases) == "alprazolam")
        #expect(PharmacologyNameKey.canonical("Alprazolam ", aliases: aliases) == "alprazolam")
    }

    @Test
    func `HalfLifeDatabase resolves aliases and tolerates trailing newlines`() {
        #expect(HalfLifeDatabase.halfLife(for: "caffeine\n") == 300)
        #expect(HalfLifeDatabase.halfLife(for: "Adderall") == HalfLifeDatabase.halfLife(for: "amphetamine"))
    }

    /// Brand names and synonyms reach the same class template as the
    /// canonical spelling, via the shared alias table.
    @Test
    func `Mechanism lookup resolves pharmacology aliases`() {
        #expect(MechanismOfActionDatabase.mechanism(for: "Xanax")?.summary
            == MechanismOfActionDatabase.mechanism(for: "alprazolam")?.summary)
        #expect(MechanismOfActionDatabase.mechanism(for: "4-MMC")?.summary
            == MechanismOfActionDatabase.mechanism(for: "mephedrone")?.summary)
    }

    /// The DB canonical spellings that previously fell to a category-generic
    /// template now key the correct class template directly.
    @Test
    func `DB-canonical names key their class templates`() {
        #expect(MechanismOfActionDatabase.mechanism(for: "3-chloromethcathinone")?.summary
            == MechanismOfActionDatabase.mechanism(for: "3-cmc")?.summary)
        #expect(MechanismOfActionDatabase.mechanism(for: "carphedon")?.summary
            == MechanismOfActionDatabase.mechanism(for: "phenylpiracetam")?.summary)
        #expect(MechanismOfActionDatabase.mechanism(for: "md-php")?.summary
            == MechanismOfActionDatabase.mechanism(for: "mdphp")?.summary)
        #expect(MechanismOfActionDatabase.mechanism(for: "alpha-pyrrolidinohexiophenone")?.summary
            == MechanismOfActionDatabase.mechanism(for: "a-php")?.summary)
    }

    /// The two curated tables keep separate alias relations on purpose:
    /// lisdexamfetamine carries its own half-life but inherits amphetamine's
    /// model scalars. A merged alias table would break one side or the other.
    @Test
    func `Half-life and model tables keep their own alias relations`() {
        #expect(HalfLifeDatabase.halfLife(for: "lisdexamfetamine") == 720)
        #expect(HalfLifeDatabase.halfLife(for: "amphetamine") == 600)
        #expect(SubstanceModelDatabase.isCalibratedTrigger("lisdexamfetamine"))
    }

    /// A brand name reaches the metabolic-modulation catalog through the
    /// shared aliases (Equetro → carbamazepine, a moderate 3A4 inducer).
    @Test
    func `Metabolic modulation matches brand names via the shared aliases`() {
        #expect(MetabolicModulation.contraceptiveEfficacyCaution(forSubstance: "Equetro") != nil)
        #expect(MetabolicModulation.contraceptiveEfficacyCaution(forSubstance: "Tegretol") != nil)
        #expect(MetabolicModulation.contraceptiveEfficacyCaution(forSubstance: "carbamazepine") != nil)
        #expect(MetabolicModulation.contraceptiveEfficacyCaution(forSubstance: "sertraline") == nil)
    }
}

/// The receptor-target fold shared by the display canonicalizer, the binding
/// dedup key, and the signature-axis matcher.
@Suite("ReceptorTargetKey")
struct ReceptorTargetKeyTests {
    @Test
    func `display strips qualifiers, enantiomer prefixes, and receptor suffixes`() {
        #expect(ReceptorTargetKey.display("NMDA receptor (PCP site)") == "NMDA")
        #expect(ReceptorTargetKey.display("MOR (+)-tramadol") == "MOR")
        #expect(ReceptorTargetKey.display("(+)-MOR") == "MOR")
        #expect(ReceptorTargetKey.display("5-HT3 receptor") == "5-HT3")
        #expect(ReceptorTargetKey.display("5-HT2 receptors") == "5-HT2")
        #expect(ReceptorTargetKey.display("Glutamate receptors (NMDA/AMPA/kainate, low-affinity)") == "Glutamate")
    }

    @Test
    func `A leading parenthetical is the whole name and is kept`() {
        #expect(ReceptorTargetKey.display("(prodrug — no direct affinity)") == "(prodrug — no direct affinity)")
        #expect(ReceptorTargetKey.fold("(prodrug — no direct affinity)") == "(prodrug — no direct affinity)")
    }

    @Test
    func `fold lowercases and collapses whitespace`() {
        #expect(ReceptorTargetKey.fold("DAT  (release)") == "dat")
        #expect(ReceptorTargetKey.fold("α2δ-1 (porcine cortex)") == "α2δ-1")
    }

    @Test
    func `SignatureTarget matching folds through the shared key`() {
        #expect(SignatureTarget.normalized("SERT (human)") == .sert)
        #expect(SignatureTarget.normalized("MOR (mu-opioid receptor)") == .mu)
        #expect(SignatureTarget.normalized("NMDA receptor") == .nmda)
        // A multi-target row never masquerades as a single leg.
        #expect(SignatureTarget.normalized("MOR / DOR / KOR / NOP") == nil)
    }
}
