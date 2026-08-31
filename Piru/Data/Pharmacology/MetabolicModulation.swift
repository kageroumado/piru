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

        /// The enzymes a cell names as a **major** route, dropping those its own prose calls minor.
        ///
        /// One cell routinely mixes weights — `CYP3A4, CYP1A2 (major); CYP2D6 (minor)`,
        /// `CYP2D6 (dominant; CYP2C8/CYP2E1/CYP2A6 minor — CYP1A2 contribution is negligible)`. Scanning
        /// the whole cell with ``all(inDBString:)`` promoted every enzyme in it, so a pathway the source
        /// wrote down as *negligible* fanned modulator callouts out as though it were dominant. Splitting
        /// on the punctuation those qualifiers scope over, then dropping a whole clause that carries one,
        /// is what the cell already means.
        ///
        /// A clause with no enzyme token contributes nothing, so an unparseable cell reads as silence
        /// rather than as a guess.
        static func major(inDBString raw: String) -> Set<Enzyme> {
            raw.split(whereSeparator: { ";—–".contains($0) })
                .filter { clause in
                    let lowered = clause.lowercased()
                    return !minorQualifiers.contains { lowered.contains($0) }
                }
                .reduce(into: Set<Enzyme>()) { $0.formUnion(all(inDBString: String($1))) }
        }

        /// Words that demote every enzyme in the clause carrying them.
        private static let minorQualifiers = ["minor", "negligible", "trace"]
    }

    /// A quantified clearance share at or above this percent — or any *unquantified* listed pathway — is
    /// treated as a **major** route. Unquantified rows are listed by the curators precisely because they
    /// matter, so they count; quantified minor pathways below the threshold are ignored to avoid noise.
    static let majorClearanceThresholdPct = 15.0

    /// The enzymes carrying a *major* share of a substance's clearance, from its `metabolism` rows.
    /// Pure (takes the rows) so it is unit-testable without the store.
    ///
    /// Two gates, because a row can say "minor" in either of two places: the quantified share, and the
    /// prose of the cell itself. Neither subsumes the other — most cells carrying a qualifier have no
    /// fraction at all, which is why the unquantified default has to be generous.
    static func majorEnzymes(metabolism: [SubstanceStore.MetabolismHit]) -> Set<Enzyme> {
        var result = Set<Enzyme>()
        for hit in metabolism where (hit.fractionOfClearancePct ?? 100) >= majorClearanceThresholdPct {
            result.formUnion(Enzyme.major(inDBString: hit.enzyme))
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

    // MARK: - Modulator

    /// One source of metabolic modulation: a logged drug, a lifestyle context, or a substance's
    /// effect on its own clearing enzyme. Built from an `enzyme_modulators` row.
    ///
    /// Display text (`displayName`, `userNote`) is DB-driven — adding a new modulator is a
    /// pipeline change, not a Swift code change.
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

        let id: String
        let origin: Origin
        let enzyme: Enzyme
        let direction: Direction
        let strength: Strength
        let confidence: ConfidenceTier
        /// Lowercased names/aliases identifying the modulating (or self) substance. Empty for a pure
        /// context flag that is never logged as a dose (grapefruit, smoking).
        let matchers: [String]
        let displayName: String
        let userNote: String
    }

    // MARK: - Effect

    /// One predicted metabolic-modulation effect on a substrate. Carries direction, qualitative strength,
    /// and a confidence tier — never a fabricated fold-change.
    struct Effect: Identifiable {
        let modulatorID: String
        let origin: Modulator.Origin
        /// The affected substance (display name as supplied).
        let substrate: String
        let enzyme: Enzyme
        let direction: Direction
        let confidence: ConfidenceTier
        let modulatorName: String
        let userNote: String

        var id: String {
            "\(substrate.lowercased())|\(modulatorID)|\(enzyme.rawValue)"
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
            modulatorName: m.displayName,
            userNote: m.userNote,
        )
    }

    // MARK: - Contraceptive-efficacy caution

    /// When `name` is a meaningful **CYP3A4 inducer**, the catalog entry behind a heads-up that it can
    /// lower the levels — and thus the efficacy — of systemic hormonal contraception. The estrogen and
    /// progestin in the combined pill, patch, ring, implant and hormonal IUD are CYP3A4 substrates, so
    /// any drug that induces 3A4 (rifampicin, carbamazepine, St John's Wort, modafinil, armodafinil) can
    /// reduce them. This is a *class property* of being a 3A4 inducer, derived from the catalog rather
    /// than hard-coded per drug. Returns `nil` for everything that is not such an inducer.
    ///
    /// **There is deliberately no `strength` threshold here, and adding one back is a safety
    /// regression.** This filtered on `>= .moderate` while modafinil and armodafinil were graded
    /// moderate; when they were re-graded `weak` against their own FDA labels — which say in as many
    /// words that modafinil "is a weak inducer of CYP3A activity" — the threshold silently dropped the
    /// two drugs this caution's own doc comment names. The band and the risk come apart because they
    /// measure different things: the band grades how hard the inducer pushes, while contraceptive
    /// failure turns on how little margin the *substrate* has. The same label that grades modafinil weak
    /// tells patients to use an alternative contraceptive method during treatment and for a month after.
    static func contraceptiveEfficacyCaution(forSubstance name: String, in catalog: [Modulator]) -> Modulator? {
        // Canonicalize through the shared alias table so a brand name
        // ("Equetro") matches its compound's catalog entry.
        let key = PharmacologyNameKey.canonical(name, aliases: PharmacologyNameKey.sharedAliases)
        return catalog.first {
            $0.origin == .substance && $0.enzyme == .cyp3a4 && $0.direction == .induces
                && $0.matchers.contains(key)
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
        let key = PharmacologyNameKey.canonical(name, aliases: PharmacologyNameKey.sharedAliases)
        let mods = catalog.filter { m in
            switch m.origin {
            case .context: true
            case .selfEdge: m.matchers.contains(key)
            case .substance: false
            }
        }
        return effects(substrateName: name, substrateEnzymes: enzymes, modulators: mods)
    }

    /// **Interaction-checker** effects among a set of hypothetically co-present substances.
    ///
    /// Two layers, merged and deduplicated:
    /// 1. **Curated modulators** (`enzyme_modulators`): each pair where one selected substance is a
    ///    curated modulator of an enzyme that clears another. Rich per-modulator notes.
    /// 2. **Tag-derived** (`tag_enzyme_interactions`): every pair where one selected substance carries
    ///    a CYP inhibitor/inducer tag and the other a CYP substrate/prodrug tag on the same enzyme.
    ///    Broader coverage (324+ pairs), template-generated notes.
    ///
    /// When both layers fire on the same pair, the curated entry wins (it has the richer copy).
    /// Context flags and self-edges are excluded (the checker reasons about substance combinations only).
    @MainActor
    static func checkerEffects(among substances: [String]) -> [Effect] {
        let store = SubstanceStore.shared
        let catalog = store.enzymeModulators()
        var seen: Set<String> = []
        var results: [Effect] = []

        // Layer 1: curated modulators (richer copy, wins on overlap).
        for substrate in substances {
            let enzymes = majorEnzymes(metabolism: store.metabolism(forSubstanceName: substrate))
            guard !enzymes.isEmpty else { continue }
            let substrateLower = substrate.lowercased()
            for m in catalog where m.origin == .substance && enzymes.contains(m.enzyme) {
                let modPresent = substances.contains { other in
                    other.lowercased() != substrateLower
                        && m.matchers.contains(PharmacologyNameKey.canonical(other, aliases: PharmacologyNameKey.sharedAliases))
                }
                if modPresent {
                    results.append(makeEffect(m, substrate: substrate))
                    seen.insert("\(m.id)|\(substrate.lowercased())")
                }
            }
        }

        // Layer 2: tag-derived enzyme interactions (broader coverage).
        let tagIndex = store.tagEnzymeInteractions()
        let substanceLower = Set(substances.map { $0.lowercased() })
        let canonicalForDisplay = Dictionary(
            substances.map { ($0.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first },
        )
        for substance in substances {
            let key = SubstanceLibrary.lookup(substance)?.name.lowercased() ?? substance.lowercased()
            guard let victims = tagIndex[key] else { continue }
            for otherLower in substanceLower where otherLower != key {
                let otherCanonical = SubstanceLibrary.lookup(canonicalForDisplay[otherLower] ?? otherLower)?.name.lowercased() ?? otherLower
                guard let hit = victims[otherCanonical] else { continue }
                let dedup = "\(key)|\(otherCanonical)"
                guard !seen.contains(dedup) else { continue }
                seen.insert(dedup)
                guard let enzyme = Enzyme(rawValue: hit.enzyme) else { continue }
                let direction: Direction = hit.direction == "induces" ? .induces : .inhibits
                let perpetratorDisplay = canonicalForDisplay[key] ?? hit.perpetratorName
                let victimDisplay = canonicalForDisplay[otherLower] ?? hit.victimName
                let note = Self.templateNote(
                    perpetrator: perpetratorDisplay, enzyme: enzyme, direction: direction,
                    strength: hit.strength, victimType: hit.victimType,
                )
                results.append(Effect(
                    modulatorID: key,
                    origin: .substance,
                    substrate: victimDisplay,
                    enzyme: enzyme,
                    direction: direction,
                    confidence: .medium,
                    modulatorName: perpetratorDisplay,
                    userNote: note,
                ))
            }
        }

        return results
    }

    /// Generate a user-facing note for a tag-derived enzyme interaction.
    private static func templateNote(
        perpetrator: String, enzyme: Enzyme, direction: Direction,
        strength: String?, victimType: String,
    ) -> String {
        let strengthWord = strength.map { "\($0)ly " } ?? ""
        let verb = direction == .inhibits ? "inhibits" : "induces"
        let consequence = if victimType == "prodrug", direction == .inhibits {
            "blocking the activation pathway for prodrugs that depend on it"
        } else if direction == .inhibits {
            "raising the levels of drugs cleared by it"
        } else {
            "lowering the levels of drugs cleared by it"
        }
        return "\(perpetrator) \(strengthWord)\(verb) \(enzyme.displayName), \(consequence)."
    }
}
