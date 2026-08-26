import Testing
@testable import Piru

/// The variants are `regional_names` rows now, installed into ``RegionalSubstanceName`` when the store
/// builds its indexes — so every test here needs the store up first. Touching the singleton in `init`
/// makes that dependency explicit rather than relying on some other suite having warmed it.
@Suite("RegionalSubstanceName")
@MainActor
struct RegionalSubstanceNameTests {
    init() {
        _ = SubstanceStore.shared
    }

    @Test
    func `US region shows the US adopted name`() {
        #expect(RegionalSubstanceName.resolve(canonicalName: "Acetaminophen", region: "US") == "Acetaminophen")
        #expect(RegionalSubstanceName.resolve(canonicalName: "Salbutamol", region: "US") == "Albuterol")
        #expect(RegionalSubstanceName.resolve(canonicalName: "Epinephrine", region: "US") == "Epinephrine")
    }

    @Test
    func `Canada and Japan follow US adopted names`() {
        for region in ["CA", "JP"] {
            #expect(RegionalSubstanceName.resolve(canonicalName: "Acetaminophen", region: region) == "Acetaminophen")
            #expect(RegionalSubstanceName.resolve(canonicalName: "Epinephrine", region: region) == "Epinephrine")
            // …but Albuterol is US-only; CA/JP keep the INN Salbutamol.
            #expect(RegionalSubstanceName.resolve(canonicalName: "Salbutamol", region: region) == "Salbutamol")
        }
    }

    @Test
    func `Rest of the world shows the international name`() {
        #expect(RegionalSubstanceName.resolve(canonicalName: "Acetaminophen", region: "GB") == "Paracetamol")
        #expect(RegionalSubstanceName.resolve(canonicalName: "Salbutamol", region: "GB") == "Salbutamol")
        #expect(RegionalSubstanceName.resolve(canonicalName: "Epinephrine", region: "AU") == "Adrenaline")
    }

    @Test
    func `Estradiol is the inverse — Oestradiol only in the UK and Commonwealth`() {
        // US and most of the world use the INN "Estradiol"…
        #expect(RegionalSubstanceName.resolve(canonicalName: "Estradiol", region: "US") == "Estradiol")
        #expect(RegionalSubstanceName.resolve(canonicalName: "Estradiol", region: "FR") == "Estradiol")
        #expect(RegionalSubstanceName.resolve(canonicalName: "Estradiol", region: "JP") == "Estradiol")
        // …only the UK and Commonwealth keep "Oestradiol".
        #expect(RegionalSubstanceName.resolve(canonicalName: "Estradiol", region: "GB") == "Oestradiol")
        #expect(RegionalSubstanceName.resolve(canonicalName: "Estradiol", region: "AU") == "Oestradiol")
    }

    @Test
    func `Resolution is independent of which spelling the DB uses as canonical`() {
        // canonical is the US spelling here (Acetaminophen) …
        #expect(RegionalSubstanceName.resolve(canonicalName: "Acetaminophen", region: "FR") == "Paracetamol")
        // … and the INN spelling here (Salbutamol) — both resolve correctly.
        #expect(RegionalSubstanceName.resolve(canonicalName: "Salbutamol", region: "FR") == "Salbutamol")
    }

    @Test
    func `Lookup is case-insensitive on the canonical name`() {
        #expect(RegionalSubstanceName.resolve(canonicalName: "acetaminophen", region: "GB") == "Paracetamol")
        #expect(RegionalSubstanceName.resolve(canonicalName: "ACETAMINOPHEN", region: "US") == "Acetaminophen")
    }

    @Test
    func `nil region falls back to the US default`() {
        #expect(RegionalSubstanceName.resolve(canonicalName: "Acetaminophen", region: nil) == "Acetaminophen")
    }

    @Test
    func `Substances without a regional variant return nil`() {
        #expect(RegionalSubstanceName.resolve(canonicalName: "Ketamine", region: "GB") == nil)
        #expect(RegionalSubstanceName.resolve(canonicalName: "MDMA", region: "US") == nil)
    }

    /// `displayTitle` consults the relabel first. Nothing else covers the interaction, and the
    /// substances carrying a regional row are precisely the ones a user relabels — so a regression
    /// here silently discards the relabel on paracetamol and four others, with no feedback.
    @Test
    func `A user relabel outranks the regional spelling`() {
        let relabelled = Substance(
            name: "Acetaminophen",
            displayName: "Doliprane",
            aliases: [],
            category: .other,
            defaultRoute: .oral,
            routes: [],
            effects: [],
        )
        #expect(relabelled.displayTitle == "Doliprane")

        let unlabelled = Substance(
            name: "Acetaminophen",
            aliases: [],
            category: .other,
            defaultRoute: .oral,
            routes: [],
            effects: [],
        )
        #expect(unlabelled.displayTitle == RegionalSubstanceName.resolve(canonicalName: "Acetaminophen"))
    }

    /// Every variant must name a substance the bundled DB actually carries, or the entry can never
    /// reach the screen: the only caller is ``Substance/displayTitle``, which is reached with a real
    /// substance's name. A norepinephrine entry sat in the old Swift table doing exactly this.
    @Test
    func `Every regional variant names a substance in the bundled DB`() {
        let variants = SubstanceReadModel.regionalNames(db: SubstanceStore.shared.substancesDB)
        #expect(variants.count == 5, "expected 5 regional variants, found \(variants.count)")
        for name in variants.keys {
            #expect(
                SubstanceStore.shared.substanceID(forNameOrAlias: name) != nil,
                "\(name) has a regional_names row but no substance",
            )
        }
    }
}
