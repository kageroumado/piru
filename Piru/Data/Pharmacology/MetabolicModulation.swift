import Foundation

/// The **metabolic-modulation graph** — curated edges where something (a co-active drug, a lifestyle
/// context, or the substance itself) changes how fast another drug is *cleared*, by inhibiting or
/// inducing the metabolic enzyme that clears it (`Specs/pharmacology-axis-meta-plan.md`, Foundation B +
/// Stage 4c). It is the clearance-axis sibling of ``ToleranceModulation`` (which scales tolerance
/// development `μ`): same idea, but the modulated parameter is metabolism.
///
/// ## Readout-only (v1)
/// This is a **readout layer**, not a change to the PK/occupancy math. A CYP3A4 inhibitor onboard does
/// **not** (yet) raise the substrate's concentration curve everywhere; instead we surface the
/// *direction and qualitative strength* of the effect — "grapefruit raises this drug's levels", "smoking
/// lowers it" — as education (substance detail), a log-time note (the dose form), and a factor in the
/// interaction checker. No fabricated fold-change number is ever shown; every figure is
/// "predicted (model, confidence)". (Threading a time-varying `ke` into the closed-form PK is deferred —
/// see the meta-plan's Stage-4c "model depth" decision.)
///
/// ## Curated modulator × data-driven substrate
/// The bundled DB knows *which enzyme clears a substance* (the `metabolism` table → ``majorEnzymes``);
/// the modulator side is the `enzyme_modulators` table, joined against it on the substrate side. A
/// substance is "affected" only when a *major* share of its clearance runs through the modulated
/// enzyme, so the readout fires on real data and stays silent otherwise. The rows arrive through
/// ``SubstanceStore/enzymeModulators()``; every function here takes the catalog it works on, so the
/// matching stays pure and testable.
nonisolated enum MetabolicModulation {
    // MARK: - Enzymes

    /// The metabolic enzymes for which we curate modulators. Recreational/clinical PK is dominated by a
    /// handful of CYPs; this is the subset with both well-evidenced modulators and real DB coverage.
    ///
    /// The raw value is the token matched (case-insensitive, substring) against a `metabolism.enzyme`
    /// cell and stored in `enzyme_modulators.enzyme`. The cells are free text and may name several
    /// enzymes ("CYP2C19, CYP3A4", "CYP2D6 (major)"), so detection is contains-based. The tokens are
    /// mutually non-overlapping ("CYP2C19" never contains "CYP2C9").
    enum Enzyme: String, CaseIterable, Hashable, Sendable {
        case cyp3a4 = "CYP3A4"
        case cyp1a2 = "CYP1A2"
        case cyp2d6 = "CYP2D6"
        case cyp2c19 = "CYP2C19"
        case cyp2c9 = "CYP2C9"
        case cyp2b6 = "CYP2B6"

        /// Human-facing enzyme name for the readout copy.
        var displayName: String {
            rawValue
        }

        /// Every curated enzyme named by a `metabolism.enzyme` cell (may be empty for generic/other rows).
        static func all(inDBString raw: String) -> Set<Enzyme> {
            let upper = raw.uppercased()
            return Set(Enzyme.allCases.filter { upper.contains($0.rawValue) })
        }
    }

    /// A quantified clearance share at or above this percent — or any *unquantified* listed pathway — is
    /// treated as a **major** route. Unquantified rows are listed by the curators precisely because they
    /// matter, so they count; quantified minor pathways below the threshold are ignored to avoid noise.
    static let majorClearanceThresholdPct = 15.0

    /// The enzymes carrying a *major* share of a substance's clearance, from its `metabolism` rows.
    /// Pure (takes the rows) so it is unit-testable without the store.
    static func majorEnzymes(metabolism: [SubstanceStore.MetabolismHit]) -> Set<Enzyme> {
        var result = Set<Enzyme>()
        for hit in metabolism where (hit.fractionOfClearancePct ?? 100) >= majorClearanceThresholdPct {
            result.formUnion(Enzyme.all(inDBString: hit.enzyme))
        }
        return result
    }

    // MARK: - Direction & strength

    /// Which way a modulator moves the substrate's exposure.
    enum Direction: String, Hashable, Sendable {
        /// Enzyme **inhibition** → slower clearance → **higher** levels.
        case inhibits
        /// Enzyme **induction** → faster clearance → **lower** levels.
        case induces

        /// `true` when the modulator raises the substrate's levels (inhibition).
        var raisesLevels: Bool {
            self == .inhibits
        }
    }

    /// Qualitative magnitude — never a fabricated fold-change. Surfaced as a word, not a number.
    enum Strength: String, Comparable, Sendable {
        case weak
        case moderate
        case strong

        private var rank: Int {
            switch self {
            case .weak: 0
            case .moderate: 1
            case .strong: 2
            }
        }

        static func < (lhs: Strength, rhs: Strength) -> Bool {
            lhs.rank < rhs.rank
        }
    }

    // MARK: - Modulator identity + copy

    /// The modulators the app has copy for, keyed by `enzyme_modulators.modulator_id`.
    ///
    /// A row whose id is not a case here is dropped at load: the readout *is* a sentence, so a rule with
    /// no sentence has nothing to show, and a DB row can never ship an untranslated one. The pairing is
    /// gated both ways by `MetabolicModulationTests`, so a curated id and its copy cannot drift apart.
    enum ModulatorID: String, CaseIterable, Hashable, Sendable {
        case grapefruit
        case smoking
        case ritonavir
        case fluvoxamine
        case carbamazepine
        case rifampicin
        case stJohnsWort = "st-johns-wort"
        case modafinil
        case armodafinil
        case mdmaCYP2D6 = "mdma-cyp2d6"

        /// The modulator's name as the reader sees it.
        var displayName: LocalizedStringResource {
            switch self {
            case .grapefruit: "Grapefruit"
            case .smoking: "Tobacco smoking"
            case .ritonavir: "Ritonavir"
            case .fluvoxamine: "Fluvoxamine"
            case .carbamazepine: "Carbamazepine"
            case .rifampicin: "Rifampicin"
            case .stJohnsWort: "St John's Wort"
            case .modafinil: "Modafinil"
            case .armodafinil: "Armodafinil"
            case .mdmaCYP2D6: "MDMA"
            }
        }

        /// One-line educational explanation of the mechanism and direction.
        var note: LocalizedStringResource {
            switch self {
            case .grapefruit:
                "Grapefruit (and related citrus) inhibits intestinal CYP3A4 for roughly 1–3 days, raising the levels of drugs cleared by it."
            case .smoking:
                "Tobacco smoke induces CYP1A2, lowering the levels of drugs cleared by it. Quitting reverses this over about a week and can raise levels."
            case .ritonavir:
                "Ritonavir strongly inhibits CYP3A4, sharply raising the levels of drugs cleared by it."
            case .fluvoxamine:
                "Fluvoxamine strongly inhibits CYP1A2, raising the levels of drugs cleared by it."
            case .carbamazepine:
                "Carbamazepine induces CYP3A4, lowering the levels of drugs cleared by it."
            case .rifampicin:
                "Rifampicin strongly induces CYP3A4, markedly lowering the levels of drugs cleared by it."
            case .stJohnsWort:
                "St John's Wort induces CYP3A4, lowering the levels of drugs cleared by it (magnitude varies by product)."
            case .modafinil:
                "Modafinil induces CYP3A4, lowering the levels of drugs cleared by it — including the hormones in systemic contraception."
            case .armodafinil:
                "Armodafinil induces CYP3A4, lowering the levels of drugs cleared by it — including the hormones in systemic contraception."
            case .mdmaCYP2D6:
                "MDMA inactivates the CYP2D6 that clears it, so repeated or closely-spaced doses build up disproportionately rather than in proportion to the dose. The enzyme recovers over about 10 days."
            }
        }
    }

    // MARK: - Modulator

    /// One curated source of metabolic modulation: a logged drug, a lifestyle context, or a substance's
    /// effect on its own clearing enzyme. Built from an `enzyme_modulators` row.
    struct Modulator: Identifiable, Hashable, Sendable {
        /// Where the modulation comes from — drives where/when it is surfaced.
        enum Origin: String, Hashable, Sendable {
            /// A *logged* co-active drug (ritonavir, carbamazepine, …).
            case substance
            /// A non-dose lifestyle flag — grapefruit (per-dose) or smoking (profile).
            case context
            /// The substance modulating the enzyme that clears *itself* (MDMA ⊣ CYP2D6).
            case selfEdge = "self"
        }

        let id: ModulatorID
        let origin: Origin
        let enzyme: Enzyme
        let direction: Direction
        let strength: Strength
        let confidence: ConfidenceTier
        /// Lowercased names/aliases identifying the modulating (or self) substance. Empty for a pure
        /// context flag that is never logged as a dose (grapefruit, smoking).
        let matchers: [String]

        var displayName: LocalizedStringResource {
            id.displayName
        }

        var note: LocalizedStringResource {
            id.note
        }
    }

    // MARK: - Effect

    /// One predicted metabolic-modulation effect on a substrate. Carries direction, qualitative strength,
    /// and a confidence tier — never a fabricated fold-change.
    struct Effect: Identifiable {
        let modulatorID: ModulatorID
        let origin: Modulator.Origin
        /// The affected substance (display name as supplied).
        let substrate: String
        let enzyme: Enzyme
        let direction: Direction
        let confidence: ConfidenceTier

        var id: String {
            "\(substrate.lowercased())|\(modulatorID.rawValue)|\(enzyme.rawValue)"
        }

        var modulatorName: LocalizedStringResource {
            modulatorID.displayName
        }

        var note: LocalizedStringResource {
            modulatorID.note
        }

        /// `true` when levels go up (inhibition).
        var raisesLevels: Bool {
            direction.raisesLevels
        }
    }

    private static func makeEffect(_ m: Modulator, substrate: String) -> Effect {
        Effect(
            modulatorID: m.id,
            origin: m.origin,
            substrate: substrate,
            enzyme: m.enzyme,
            direction: m.direction,
            confidence: m.confidence,
        )
    }

    // MARK: - Contraceptive-efficacy caution

    /// When `name` is a meaningful **CYP3A4 inducer**, the catalog entry behind a heads-up that it can
    /// lower the levels — and thus the efficacy — of systemic hormonal contraception. The estrogen and
    /// progestin in the combined pill, patch, ring, implant and hormonal IUD are CYP3A4 substrates, so
    /// any drug that meaningfully induces 3A4 (rifampicin, carbamazepine, St John's Wort, modafinil,
    /// armodafinil) can reduce them. This is a *class property* of being a 3A4 inducer, derived from the
    /// catalog rather than hard-coded per drug. Weak inducers are excluded (the threshold is `.moderate`).
    /// Returns `nil` for everything that is not such an inducer.
    static func contraceptiveEfficacyCaution(forSubstance name: String, in catalog: [Modulator]) -> Modulator? {
        // Canonicalize through the shared alias table so a brand name
        // ("Equetro") matches its compound's catalog entry.
        let key = PharmacologyNameKey.canonical(name, aliases: HalfLifeDatabase.sharedAliases)
        return catalog.first {
            $0.origin == .substance && $0.enzyme == .cyp3a4 && $0.direction == .induces
                && $0.strength >= .moderate && $0.matchers.contains(key)
        }
    }

    // MARK: - Analysis

    /// Pure match: the catalog modulators in `modulators` whose enzyme is one of `substrateEnzymes`,
    /// rendered as effects on `substrateName`. The caller pre-filters `modulators` to those actually
    /// active in context; this stays pure for testing.
    static func effects(
        substrateName: String,
        substrateEnzymes: Set<Enzyme>,
        modulators: [Modulator],
    ) -> [Effect] {
        modulators
            .filter { substrateEnzymes.contains($0.enzyme) }
            .map { makeEffect($0, substrate: substrateName) }
    }

    /// **Educational** effects for a substance's detail card — the context modifiers (grapefruit,
    /// smoking) and self-edge that *could* affect it, independent of the user's profile or what else is
    /// logged. "Grapefruit raises levels of this drug", "smoking lowers them". Empty when no major
    /// clearance enzyme is modulated.
    static func educationalEffects(
        forSubstance name: String,
        metabolism: [SubstanceStore.MetabolismHit],
        catalog: [Modulator],
    ) -> [Effect] {
        let enzymes = majorEnzymes(metabolism: metabolism)
        guard !enzymes.isEmpty else { return [] }
        let key = PharmacologyNameKey.canonical(name, aliases: HalfLifeDatabase.sharedAliases)
        let mods = catalog.filter { m in
            switch m.origin {
            case .context: true
            case .selfEdge: m.matchers.contains(key)
            case .substance: false
            }
        }
        return effects(substrateName: name, substrateEnzymes: enzymes, modulators: mods)
    }

    /// **Interaction-checker** effects among a set of hypothetically co-present substances: each pair
    /// where one selected substance is a curated modulator of an enzyme that clears another. Context
    /// flags and self-edges are excluded (the checker reasons about substance combinations only).
    @MainActor
    static func checkerEffects(among substances: [String]) -> [Effect] {
        let catalog = SubstanceStore.shared.enzymeModulators()
        var results: [Effect] = []
        for substrate in substances {
            let enzymes = majorEnzymes(metabolism: SubstanceStore.shared.metabolism(forSubstanceName: substrate))
            guard !enzymes.isEmpty else { continue }
            let substrateLower = substrate.lowercased()
            for m in catalog where m.origin == .substance && enzymes.contains(m.enzyme) {
                let modPresent = substances.contains { other in
                    other.lowercased() != substrateLower
                        && m.matchers.contains(PharmacologyNameKey.canonical(other, aliases: HalfLifeDatabase.sharedAliases))
                }
                if modPresent { results.append(makeEffect(m, substrate: substrate)) }
            }
        }
        return results
    }
}
