import Testing
@testable import Piru

/// The shared name-key mechanism the hardcoded pharmacology tables funnel
/// through, and the cross-table guarantees the unification rests on.
@Suite("PharmacologyNameKey")
@MainActor
struct PharmacologyNameKeyTests {
    /// `isCalibratedTrigger` resolves against the `model-calibrated` flag installed at index build, so
    /// this suite needs the store up rather than relying on another suite having warmed it.
    init() {
        _ = SubstanceStore.shared
    }

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
    func `Resolution tolerates trailing newlines and hops one alias`() {
        let data = ["amphetamine": 600.0]
        let aliases = PharmacologyNameKey.sharedAliases
        #expect(PharmacologyNameKey.resolve("amphetamine\n", in: data, aliases: aliases) == 600)
        #expect(PharmacologyNameKey.resolve("Adderall", in: data, aliases: aliases) == 600)
    }

    /// Brand names and synonyms fold onto the canonical spelling through the shared alias table.
    ///
    /// These used to run through `MechanismOfActionDatabase.mechanism(for:)`, which was only ever
    /// a convenient dictionary to resolve against — the table is gone and the fold is the subject,
    /// so a fixture says so directly.
    @Test
    func `Resolution folds brand names and synonyms onto the canonical key`() {
        // Only names the shared table actually folds. The old test also paired md-php/mdphp and
        // 3-chloromethcathinone/3-cmc, which agreed because the deleted Swift dictionary happened
        // to carry both spellings as direct keys — that was a fact about the table, not about the
        // fold, and it went with the table.
        let table = ["alprazolam": "benzo", "mephedrone": "cathinone", "phenylpiracetam": "racetam", "a-php": "pyrovalerone"]
        func resolve(_ name: String) -> String? {
            PharmacologyNameKey.resolve(name, in: table, aliases: PharmacologyNameKey.sharedAliases)
        }
        #expect(resolve("Xanax") == resolve("alprazolam"))
        #expect(resolve("4-MMC") == resolve("mephedrone"))
        #expect(resolve("carphedon") == resolve("phenylpiracetam"))
        #expect(resolve("alpha-pyrrolidinohexiophenone") == resolve("a-php"))
        #expect(resolve("Xanax") != nil, "the fold must land on a key, not merely agree on nil")
    }

    /// The two alias relations are separate on purpose: to the shared table lisdexamfetamine is its
    /// own name, while `SubstanceModelDatabase` aliases it to amphetamine because it must inherit
    /// amphetamine's model scalars. A merged table would break one side or the other.
    @Test
    func `The shared and model tables keep their own alias relations`() {
        #expect(PharmacologyNameKey.sharedAliases["lisdexamfetamine"] == nil)
        #expect(SubstanceModelDatabase.isCalibratedTrigger("lisdexamfetamine"))
    }

    /// A brand name reaches the `enzyme_modulators` rules through the shared
    /// aliases (Equetro → carbamazepine, a moderate 3A4 inducer). The rules' own
    /// matcher rows are a *third* relation again, so this gates that the hop from
    /// a brand to a rule still runs through the half-life table's aliases.
    @Test
    @MainActor
    func `Metabolic modulation matches brand names via the shared aliases`() {
        let catalog = SubstanceStore.shared.enzymeModulators()
        #expect(MetabolicModulation.contraceptiveEfficacyCaution(forSubstance: "Equetro", in: catalog) != nil)
        #expect(MetabolicModulation.contraceptiveEfficacyCaution(forSubstance: "Tegretol", in: catalog) != nil)
        #expect(MetabolicModulation.contraceptiveEfficacyCaution(forSubstance: "carbamazepine", in: catalog) != nil)
        #expect(MetabolicModulation.contraceptiveEfficacyCaution(forSubstance: "sertraline", in: catalog) == nil)
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
