import Foundation
import os
import SwiftUI

private nonisolated let logger = Logger(subsystem: "dev.yumeji.piru", category: "Interactions")

// MARK: - Interaction Severity

/// `CaseIterable` so the contrast gate in `ColorContrastTests` covers every
/// severity automatically — a new case must clear its legibility floor rather
/// than silently escaping a hardcoded list.
nonisolated enum InteractionSeverity: Int, Comparable, Codable, CaseIterable {
    case caution = 0
    case unsafe = 1
    case dangerous = 2

    /// The bundled DB stores severity as a lowercase name.
    init?(bundledName: String) {
        switch bundledName.lowercased() {
        case "dangerous": self = .dangerous
        case "unsafe": self = .unsafe
        case "caution": self = .caution
        default: return nil
        }
    }

    static func < (lhs: InteractionSeverity, rhs: InteractionSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: LocalizedStringResource {
        switch self {
        case .dangerous: "Dangerous"
        case .unsafe: "Unsafe"
        case .caution: "Caution"
        }
    }

    /// Mark colour — fills, bands, dots. Text uses ``labelColor``.
    ///
    /// `@MainActor` because Xcode's generated asset symbols are, under the
    /// project's `-default-isolation MainActor`. The raw system hues this
    /// replaced were nonisolated, so this is a real (small) constraint added in
    /// exchange for the values being gated and centrally defined.
    @MainActor var color: Color {
        switch self {
        case .caution: .Severity.Caution.accent
        case .unsafe: .Severity.Unsafe.accent
        case .dangerous: .Severity.Dangerous.accent
        }
    }

    /// Legible text variant, gated at WCAG AA against the card *and* against
    /// this severity's own tinted fill.
    ///
    /// ``color`` is a fill value: as small text it measured 1.39:1 for
    /// `.caution` and 3.27:1 for `.dangerous`.
    ///
    /// This is a three-step *scale*, not three `semantic/*` lookups. `.unsafe`
    /// sits between caution and danger, and the four-level semantic ladder has
    /// no middle tier — folding it into `danger` would erase a distinction the
    /// app deliberately makes. It kept failing at 2.12:1 until the ladder got
    /// its own scale.
    @MainActor var labelColor: Color {
        switch self {
        case .caution: .Severity.Caution.text
        case .unsafe: .Severity.Unsafe.text
        case .dangerous: .Severity.Dangerous.text
        }
    }
}

// MARK: - Interaction Source

/// Origin of an interaction warning.
///
/// ``pharmacokinetic`` is a different *kind* of claim from ``classRule``, not a
/// second opinion about the same one. A class rule says two mechanisms stack; a
/// PK row says a measured exposure changed, by a named enzyme, in a cited study.
/// They are surfaced together but never merged, and a PK row never sets a
/// severity — see ``PKInteractionFinding``.
enum InteractionSource {
    case classRule
    case pharmacokinetic

    var label: LocalizedStringResource {
        switch self {
        case .classRule: "Pharmacological"
        case .pharmacokinetic: "Measured exposure"
        }
    }
}

// MARK: - Pharmacokinetic Interaction Finding

/// A `drug_interactions_pk` row matched against something the person actually
/// logged: one drug measurably changing another's exposure, with the enzyme
/// mechanism and the study behind it.
///
/// **Deliberately carries no ``InteractionSeverity``.** The table has no severity
/// column because its sources assign none, and the app's three-step ladder is a
/// judgment about danger that "AUC increased ~2.6×" does not make. Rendering one
/// here would manufacture the single thing a reader leans on hardest. Views show
/// these as a measurement beside the severity-ranked warnings, never inside them.
struct PKInteractionFinding: Identifiable, Hashable {
    var id: Int64 {
        hit.id
    }
    let hit: SubstanceStore.PKInteractionHit
    /// The substance whose record carries the row.
    let substance: String
    /// The logged substance the row's counterpart resolved to.
    let counterpart: String

    var source: InteractionSource {
        .pharmacokinetic
    }
}

// MARK: - Drug Class (for interaction matching)

nonisolated enum DrugClass: String, Codable {
    case opioid
    case benzodiazepine
    /// Barbiturates (phenobarbital, pentobarbital, secobarbital, thiopental, …) and
    /// primidone, which is metabolized to phenobarbital. Separate from
    /// ``benzodiazepine`` because the mechanism differs where it matters most: a
    /// benzodiazepine only *modulates* GABA-A and its depression therefore plateaus,
    /// while a barbiturate opens the chloride channel directly and keeps going. That
    /// missing ceiling is why barbiturate + benzodiazepine is `dangerous` here where
    /// benzodiazepine × benzodiazepine is `unsafe`, and why the therapeutic-to-fatal
    /// margin is narrow enough that these were displaced clinically.
    case barbiturate
    case stimulant
    case psychedelic
    case dissociative
    case empathogen
    case cannabinoid
    case gabapentinoid
    case alcohol
    case ghb
    /// Dual orexin receptor antagonists (suvorexant, lemborexant, daridorexant — the
    /// modern DORA sleep meds). They block OX1R/OX2R rather than enhancing GABA, so they
    /// carry additive next-day sedation / psychomotor / fall risk with other CNS
    /// depressants but — critically — do NOT add brainstem respiratory depression. Hence
    /// only `.caution` rules, never the benzo/opioid respiratory-synergy danger tier.
    case orexinAntagonist
    case antihistamine
    case maoi
    case ssri
    case snri
    case tca
    /// Serotonin-*adding* agents with a genuine additive serotonin-toxicity risk — releasers or
    /// reuptake inhibitors that are NOT therapeutic antidepressant SERT blockers (which blunt
    /// empathogens). Tramadol, meperidine/pethidine, and dextromethorphan: they *stack* serotonergic
    /// load rather than competing it away, so they get danger rules, not the antidepressant blunting
    /// readout. Grounded in the Foundation-C serotonergic evidence run (2026-06-22).
    case serotonergic
    case lithium
    case antipsychotic
    /// Centrally-acting alpha-2 adrenergic agonists (clonidine, guanfacine, tizanidine, dexmedetomidine,
    /// lofexidine; the xylazine/medetomidine "tranq" adulterants). Additive sedation/bradycardia/
    /// hypotension; the alpha-2 component is NOT reversed by naloxone. Grounded in the Foundation-C
    /// alpha-2/beta-blocker run (2026-06-22).
    case alpha2Agonist
    /// Beta-adrenergic antagonists (propranolol, metoprolol, atenolol, carvedilol, …). The real
    /// "unopposed alpha" edge is alpha-2-agonist *withdrawal* while beta-blocked, NOT routine
    /// beta-blocker + stimulant (that contraindication is contested dogma — see the evidence run).
    case betaBlocker
    /// Vitamins, minerals, amino acids, herbal preparations. Like ``other`` it
    /// currently appears in **no rule**, so every substance routed here is
    /// interaction-invisible. Kept as its own case rather than folded into
    /// `other` because the rules it is missing are real and specific (5-HTP with
    /// a serotonergic; St John's Wort inducing CYP3A4; grapefruit inhibiting it)
    /// — this is where they go when they are sourced.
    case supplement
    case other

    /// The classes no rule mentions. Everything routed to one of these returns
    /// nothing for every pairing; `InteractionRuleTests` pins the set so a new
    /// class cannot join it unnoticed.
    static let unruled: Set<DrugClass> = [.other, .supplement]
}

// MARK: - Interaction Result

struct InteractionResult: Equatable {
    let severity: InteractionSeverity
    let substanceA: String
    let substanceB: String
    let description: String

    /// The class pair whose rule produced this warning — the identity a
    /// display surface groups on. Empty when the result was made by hand
    /// (tests, previews) rather than by a rule firing.
    let ruleKey: String

    /// Temporal effect-curve overlap of the two doses, `[0, 1]`. The peak of
    /// the product of both doses' subjective-effect curves over wall-clock
    /// time. `1` when no timestamps were available (the manual picker / report)
    /// — i.e. "unknown, treat as concurrent". A low value means the two effect
    /// curves barely co-occur (kratom in the morning vs a benzo at night).
    let overlapFactor: Double

    /// Combined dose-presence weight, `[0, 1]`. The product of each
    /// participant's presence (≈1 at a meaningful dose, →0 for a clearly
    /// sub-threshold one). `1` when the amounts are unknown.
    let doseFactor: Double

    init(
        severity: InteractionSeverity,
        substanceA: String,
        substanceB: String,
        description: String,
        ruleKey: String = "",
        overlapFactor: Double = 1,
        doseFactor: Double = 1,
    ) {
        self.severity = severity
        self.substanceA = substanceA
        self.substanceB = substanceB
        self.description = description
        self.ruleKey = ruleKey
        self.overlapFactor = overlapFactor
        self.doseFactor = doseFactor
    }

    /// Relevance-weighted score used to order warnings and, on warn surfaces,
    /// to decide what to hide. Reserves the top of the list — and the red
    /// treatment — for genuinely concurrent, meaningful-dose, dangerous pairs.
    /// With no temporal/dose data both factors are `1`, so this collapses back
    /// to the base severity rank and ordering is unchanged.
    var displayScore: Double {
        (Double(severity.rawValue) + 1) * relevance
    }

    /// `overlapFactor · doseFactor` — how much this pair actually matters here,
    /// independent of its base severity. `1` when nothing is known.
    var relevance: Double {
        overlapFactor * doseFactor
    }

    /// `true` when good data shows the pair is unlikely to matter at these
    /// doses/timing. Demotes the finding one prominence step; the explorer
    /// still lists it.
    var isLowRelevance: Bool {
        relevance < InteractionChecker.lowRelevanceThreshold
    }

    /// The mechanism in the fewest words that still say what happens —
    /// everything before the em dash, or the first sentence.
    ///
    /// Every rule's description is written the same way: the effect, an em
    /// dash, then the elaboration ("Combined respiratory depression — the
    /// leading cause of overdose death."). Compact surfaces show the first
    /// half, which is the part that is not already implied by a red dot.
    var leadClause: String {
        if let dash = description.range(of: " — ") {
            return String(description[description.startIndex ..< dash.lowerBound])
        }
        if let stop = description.firstIndex(of: ".") {
            return String(description[description.startIndex ... stop])
        }
        return description
    }

    /// How loudly this finding has earned the right to arrive.
    ///
    /// Severity says how bad a pairing is. Prominence says whether it may
    /// interrupt. Two stimulants is a real `caution` — combined cardiovascular
    /// strain, worth knowing — but arriving in the same red, at the same size,
    /// at the moment someone logs a coffee is how a person learns to dismiss
    /// the row that says opioid + benzodiazepine. Every surface takes a floor;
    /// what falls below it becomes a count, not a sentence.
    var prominence: InteractionProminence {
        let base: InteractionProminence = switch severity {
        case .dangerous: .blocking
        case .unsafe: .notable
        case .caution: .background
        }
        return isLowRelevance ? base.demoted : base
    }
}

/// Where a finding is allowed to appear. Ordered, so a surface can take a floor.
enum InteractionProminence: Int, Comparable, CaseIterable {
    /// True, and low-stakes here. Belongs in the explorer and in a count.
    case background = 0
    /// Worth reading before continuing.
    case notable = 1
    /// Worth stopping for.
    case blocking = 2

    var demoted: InteractionProminence {
        InteractionProminence(rawValue: rawValue - 1) ?? .background
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension [InteractionResult] {
    /// The findings this surface admits, most prominent first.
    func admitted(_ floor: InteractionProminence) -> [InteractionResult] {
        filter { $0.prominence >= floor }
    }

    /// How many fall below the floor — the number behind "N more".
    func belowFloor(_ floor: InteractionProminence) -> Int {
        count { $0.prominence < floor }
    }

    /// The split between what a review surface shows and what it folds.
    ///
    /// Folding buys nothing when there is almost nothing to fold: one or two
    /// findings fit, whatever they are, and hiding one behind a disclosure that
    /// says "1 more" costs a tap and reads as an error. Past that, the quiet
    /// ones move out of the way so the loud ones are visible — and when *all* of
    /// them are quiet the whole set folds, because then the count is the honest
    /// summary and no single row deserves the space.
    func partitionedForReview() -> (shown: [InteractionResult], folded: [InteractionResult]) {
        guard count > 2 else { return (self, []) }
        return (admitted(.notable), filter { $0.prominence < .notable })
    }
}

// MARK: - Interaction Policy

/// How aggressively the checker gates warnings, set per surface.
enum InteractionPolicy {
    /// Log-time warnings (dose entry, daily-dose batch). Hide a pair when good
    /// data — real effect curves or dose amounts — shows it is confidently
    /// irrelevant (a clearly sub-threshold dose, or two doses whose effect
    /// curves never overlap). Everything uncertain is still shown, ranked by
    /// relevance.
    case warn

    /// The Tools ▸ Interactions explorer. Never hide a matched rule — surface
    /// every possible interaction unconditionally, marking low-relevance ones
    /// via ``InteractionResult/isLowRelevance`` instead of suppressing them.
    case explore
}

// MARK: - Interaction Rule

private struct InteractionRule {
    let classA: DrugClass
    let classB: DrugClass
    let severity: InteractionSeverity
    let description: String

    init(classA: DrugClass, classB: DrugClass, severity: InteractionSeverity, description: LocalizedStringResource) {
        self.classA = classA
        self.classB = classB
        self.severity = severity
        self.description = String(localized: description)
    }

    /// For a rule read from the bundled database. Its note is source prose, not
    /// a catalog key, so it ships in English regardless of locale — the same
    /// treatment every other DB-authored string gets.
    init(classA: DrugClass, classB: DrugClass, severity: InteractionSeverity, note: String) {
        self.classA = classA
        self.classB = classB
        self.severity = severity
        description = note
    }

    /// The class pair this rule is written against, order-independent. This is
    /// the rule's identity: two pairs firing the same rule share a cause, which
    /// two pairs merely sharing boilerplate prose do not.
    var key: String {
        [classA.rawValue, classB.rawValue].sorted().joined(separator: "|")
    }

    /// A hard pharmacological edge whose danger **outlasts the subjective
    /// effect curve** — irreversible MAO inhibition (lethal days after the
    /// felt effects fade), lithium, or a chronic serotonergic at steady state
    /// (an SSRI taken today is effectively present for weeks). These are *not*
    /// gated on effect-curve overlap and are never suppressed on dose; they
    /// keep firing on co-presence within the existing long pharmacological
    /// window. The additive depressant/cardio pile (where the false reds and
    /// the wall-of-red live) is everything else, and gets the full gate.
    var isPersistent: Bool {
        InteractionChecker.persistentClasses.contains(classA)
            || InteractionChecker.persistentClasses.contains(classB)
    }
}

// MARK: - Interaction Checker

/// The drug-interaction engine. Resolves substance pairs into severity-ranked
/// warnings using hand-curated pharmacological class rules and returns the
/// worst-case match per pair.
///
/// ## Source layers
///
/// **Class-pair rules** (``rules``) keyed by ``DrugClass`` pairs are the only
/// active source. The earlier design included TripSit combo data and parsed
/// FDA-label warnings as fallback layers; those were removed when the runtime
/// API fetches went away with the SQLite migration. Restoring them means
/// populating the bundled SQLite's `interaction_rules` table and adding a
/// SQL-backed source layer here — tracked separately.
///
/// ## Severity ordering
///
/// ``InteractionSeverity`` orders `dangerous > unsafe > caution`. Batch
/// deduplication keeps the highest-severity result for each substance pair so
/// users always see the worst-case warning.
///
/// ## Caveats
///
/// ``DrugClass/other`` participates in **zero** rules. Any substance that
/// `categoryToDrugClass` maps to `.other` (analgesics, cardiovascular,
/// antimicrobials, GI, respiratory, endocrine, immunological, depressants not
/// otherwise classified, etc.) is interaction-invisible: with class rules as
/// the only active layer, it returns nothing for every pairing. The fix is an
/// entry in ``substanceClassOverrides`` lifting the substance into a real
/// class — that is how barbiturates and methylene blue were recovered.
enum InteractionChecker {
    // MARK: - Public API

    /// Check a prospective substance against a list of active dose entries.
    ///
    /// On the ``InteractionPolicy/warn`` surfaces this reads the same effect
    /// curves the timeline draws: a pair only warns where the two doses'
    /// effects genuinely co-occur and both are at a meaningful dose. A pair the
    /// data confidently shows to be irrelevant — non-concurrent, or with a
    /// clearly sub-threshold participant — is dropped, not reddened. Hard
    /// pharmacological edges (MAOI, lithium, chronic serotonergics) bypass the
    /// effect-overlap gate; see ``InteractionRule/isPersistent``.
    ///
    /// On ``InteractionPolicy/explore`` nothing is hidden — every matched rule
    /// is returned, ranked by relevance.
    static func check(
        _ substanceName: String,
        against activeEntries: [DoseEntry],
        policy: InteractionPolicy = .warn,
    ) -> [InteractionResult] {
        let newClasses = drugClasses(for: substanceName)
        guard !newClasses.isEmpty else { return [] }

        // The prospective dose's effect track (it starts "now"). Only built for
        // temporal gating on warn surfaces; nil when the substance has no curve
        // data, in which case the temporal gate degrades to "unknown" and the
        // pair is shown.
        let prospective = policy == .warn ? prospectiveTrack(for: substanceName) : nil

        var byPair: [String: InteractionResult] = [:]
        for entry in activeEntries {
            guard entry.substance.lowercased() != substanceName.lowercased() else { continue }

            guard let rule = worstRule(newClasses, drugClasses(for: entry.substance)) else { continue }

            var overlapFactor = 1.0
            var doseFactor = 1.0
            if policy == .warn {
                let gate = gatePair(prospective: prospective, active: track(for: entry), persistent: rule.isPersistent)
                if gate.suppress { continue }
                overlapFactor = gate.overlapFactor
                doseFactor = gate.doseFactor
            }

            let result = InteractionResult(
                severity: rule.severity,
                substanceA: substanceName,
                substanceB: entry.substance,
                description: rule.description,
                ruleKey: rule.key,
                overlapFactor: overlapFactor,
                doseFactor: doseFactor,
            )
            merge(result, into: &byPair)
        }

        return byPair.values.sorted { $0.displayScore > $1.displayScore }
    }

    /// Check all substances in a batch against each other and against active entries.
    static func checkBatch(
        _ substances: [String],
        against activeEntries: [DoseEntry],
        policy: InteractionPolicy = .warn,
    ) -> [InteractionResult] {
        var byPair: [String: InteractionResult] = [:]

        // Each substance (logged "now") against the already-active entries.
        if !activeEntries.isEmpty {
            for substance in substances {
                for result in check(substance, against: activeEntries, policy: policy) {
                    merge(result, into: &byPair)
                }
            }
        }

        // Within the batch the substances are co-administered, so they are
        // concurrent by construction (overlap = 1) and carry no amounts here
        // (dose = 1) — the rule fires at its base severity.
        for i in 0 ..< substances.count {
            for j in (i + 1) ..< substances.count {
                guard let rule = worstRule(drugClasses(for: substances[i]), drugClasses(for: substances[j])) else { continue }
                merge(InteractionResult(
                    severity: rule.severity,
                    substanceA: substances[i],
                    substanceB: substances[j],
                    description: rule.description,
                    ruleKey: rule.key,
                ), into: &byPair)
            }
        }

        return byPair.values.sorted { $0.displayScore > $1.displayScore }
    }

    /// The highest-severity rule across every class-pair combination of two
    /// substances, or `nil` if none interact.
    private static func worstRule(_ classesA: [DrugClass], _ classesB: [DrugClass]) -> InteractionRule? {
        var best: InteractionRule?
        for a in classesA {
            for b in classesB {
                if let rule = findRule(a, b), best == nil || rule.severity > best!.severity {
                    best = rule
                }
            }
        }
        return best
    }

    /// Keep the highest-scoring result per substance pair.
    private static func merge(_ result: InteractionResult, into byPair: inout [String: InteractionResult]) {
        let key = pairKey(result.substanceA, result.substanceB)
        if let existing = byPair[key], existing.displayScore >= result.displayScore { return }
        byPair[key] = result
    }

    private static func pairKey(_ a: String, _ b: String) -> String {
        [a.lowercased(), b.lowercased()].sorted().joined(separator: "|")
    }

    // MARK: - Pharmacokinetic Interactions

    /// The `drug_interactions_pk` rows that name something in `activeEntries`.
    ///
    /// Read in both directions: a row lives on one substance's record and names
    /// the other in free text, and which side got the row is an artifact of which
    /// paper was read, not of which drug is affected. Ketamine's record carries
    /// "clarithromycin"; clarithromycin's record carries nothing.
    ///
    /// Matching resolves each counterpart name through ``SubstanceLibrary`` and
    /// compares canonical names, so an alias on either side still connects. About
    /// a third of the table names a real drug this way; the rest names a *class*
    /// ("CYP3A4 inhibitors", "MAOIs") and matches nothing here by design — an
    /// unresolved name is skipped rather than string-matched, because "SSRIs"
    /// substring-matching a logged SSRI would be the checker inferring a claim the
    /// row does not make. Those rows still render in full on the substance's own
    /// Metabolism Interactions card, which is where a class-named row belongs.
    static func pharmacokineticInteractions(
        _ substanceName: String,
        against activeEntries: [DoseEntry],
    ) -> [PKInteractionFinding] {
        let logged = Dictionary(
            activeEntries.compactMap { entry -> (String, String)? in
                guard let canonical = canonicalName(for: entry.substance) else { return nil }
                return (canonical, entry.substance)
            },
            uniquingKeysWith: { first, _ in first },
        )
        guard !logged.isEmpty, let subject = canonicalName(for: substanceName) else { return [] }

        var findings: [PKInteractionFinding] = []
        var seen: Set<Int64> = []

        func collect(rowsFor owner: String, matching candidates: [String: String]) {
            for hit in SubstanceStore.shared.pkInteractions(forSubstanceName: owner) {
                guard !seen.contains(hit.id) else { continue }
                for name in hit.counterpartNames {
                    guard let resolved = canonicalName(for: name), let match = candidates[resolved] else { continue }
                    seen.insert(hit.id)
                    findings.append(PKInteractionFinding(hit: hit, substance: owner, counterpart: match))
                    break
                }
            }
        }

        // The prospective substance's own rows, against everything logged…
        collect(rowsFor: substanceName, matching: logged)
        // …then each logged substance's rows, against the prospective one.
        for entry in activeEntries where entry.substance.lowercased() != substanceName.lowercased() {
            collect(rowsFor: entry.substance, matching: [subject: substanceName])
        }
        return findings
    }

    /// A name resolved to the catalog's canonical spelling, lowercased for
    /// comparison. Nil when the catalog does not carry it — which is the signal to
    /// skip, never to fall back to raw string comparison.
    private static func canonicalName(for name: String) -> String? {
        SubstanceLibrary.lookup(name)?.name.lowercased()
    }

    // MARK: - Drug Class Mapping

    /// Specific substance name → drug class overrides
    private static let substanceClassOverrides: [String: [DrugClass]] = {
        var map: [String: [DrugClass]] = [:]

        // MAOIs
        for name in [
            "Phenelzine",
            "Tranylcypromine",
            "Isocarboxazid",
            "Selegiline",
            "Moclobemide",
            "Syrian Rue",
        ] {
            map[name.lowercased()] = [.maoi]
        }

        // SSRIs
        for name in [
            "Sertraline",
            "Fluoxetine",
            "Paroxetine",
            "Citalopram",
            "Escitalopram",
            "Fluvoxamine",
        ] {
            map[name.lowercased()] = [.ssri]
        }

        // SNRIs
        for name in [
            "Venlafaxine",
            "Duloxetine",
            "Desvenlafaxine",
            "Levomilnacipran",
            "Milnacipran",
        ] {
            map[name.lowercased()] = [.snri]
        }

        // TCAs
        for name in [
            "Amitriptyline",
            "Nortriptyline",
            "Imipramine",
            "Desipramine",
            "Clomipramine",
            "Doxepin",
            "Trimipramine",
            "Protriptyline",
        ] {
            map[name.lowercased()] = [.tca]
        }

        // Dual-class substances. Tramadol, meperidine, and DXM are serotonin *adders* (releaser /
        // reuptake inhibitor), NOT antidepressant SERT blockers — so they ride `.serotonergic` (genuine
        // serotonin-toxicity danger) rather than `.ssri/.snri` (which now read as empathogen *blunting*).
        // Evidence: Foundation-C serotonergic run, 2026-06-22 (tramadol SS grade B/HIGH + seizure A/HIGH).
        map["tramadol"] = [.opioid, .serotonergic]
        // Tapentadol is NRI-dominant with minimal SERT activity (low SS risk) — plain opioid, so it
        // neither blunts an empathogen nor carries the serotonergic danger.
        map["tapentadol"] = [.opioid]
        map["meperidine"] = [.opioid, .serotonergic]
        map["pethidine"] = [.opioid, .serotonergic]
        map["dxm"] = [.dissociative, .serotonergic]
        map["dextromethorphan"] = [.dissociative, .serotonergic]
        map["mdma"] = [.empathogen, .stimulant]
        map["mda"] = [.empathogen, .stimulant]
        map["mdea"] = [.empathogen, .stimulant]

        // Lithium
        map["lithium"] = [.lithium]
        map["lithium carbonate"] = [.lithium]
        map["lithium orotate"] = [.lithium]

        // GHB/GBL
        map["ghb"] = [.ghb]
        map["gbl"] = [.ghb]
        map["ghb/gbl"] = [.ghb]
        map["1,4-butanediol"] = [.ghb]

        // Alcohol
        map["alcohol"] = [.alcohol]
        map["ethanol"] = [.alcohol]

        // Gabapentinoids
        map["phenibut"] = [.gabapentinoid]
        map["gabapentin"] = [.gabapentinoid]
        map["pregabalin"] = [.gabapentinoid]
        map["baclofen"] = [.ghb]

        // Stimulants (common names)
        for name in [
            "Caffeine",
            "Nicotine",
            "Methamphetamine",
            "Cocaine",
            "Amphetamine",
            "Dextroamphetamine",
            "Lisdexamfetamine",
            "Methylphenidate",
            "Modafinil",
            "Armodafinil",
            "DMAA",
        ] {
            map[name.lowercased()] = [.stimulant]
        }

        // Opioids (common names/variants)
        map["kratom"] = [.opioid]
        map["heroin"] = [.opioid]
        map["fentanyl"] = [.opioid]

        // Atypical antidepressants
        map["bupropion"] = [.stimulant] // NDRI — stimulant-like, lowers seizure threshold
        map["trazodone"] = [.ssri] // SARI — serotonergic, reasonable SSRI proxy
        map["vortioxetine"] = [.ssri] // Multimodal serotonergic
        map["vilazodone"] = [.ssri] // SSRI + 5-HT1A partial agonist
        map["agomelatine"] = [.other] // Melatonin agonist — minimal serotonin interactions
        map["reboxetine"] = [.snri] // NRI — norepinephrine-selective

        // Antihistamines
        for name in [
            "Diphenhydramine",
            "DPH",
            "Hydroxyzine",
            "Promethazine",
            "Doxylamine",
            "Chlorpheniramine",
            "Cetirizine",
            "Meclizine",
            "Dimenhydrinate",
        ] {
            map[name.lowercased()] = [.antihistamine]
        }

        // Z-drugs (GABA-A agonists — interact like benzos)
        for name in ["Zolpidem", "Zopiclone", "Eszopiclone", "Zaleplon"] {
            map[name.lowercased()] = [.benzodiazepine]
        }

        // Buspirone (5-HT1A partial agonist — serotonin syndrome risk)
        map["buspirone"] = [.ssri] // Serotonergic proxy for interaction matching

        // Quetiapine (sedating antipsychotic — also acts as antihistamine at low doses)
        map["quetiapine"] = [.antipsychotic, .antihistamine]

        // Alpha-2 adrenergic agonists (clonidine/guanfacine for ADHD/BP; tizanidine muscle relaxant;
        // dexmedetomidine/lofexidine). Additive sedation/bradycardia/hypotension; naloxone-irreversible.
        for name in ["Clonidine", "Guanfacine", "Tizanidine", "Dexmedetomidine", "Lofexidine", "Xylazine", "Medetomidine"] {
            map[name.lowercased()] = [.alpha2Agonist]
        }

        // Beta-blockers. NOT split selective vs non-selective: the actionable interaction rules
        // (alpha-2-withdrawal hypertensive crisis, additive hypotension) don't turn on selectivity, and
        // the beta-blocker + stimulant "unopposed alpha" contraindication is contested dogma (evidence run).
        for name in [
            "Propranolol", "Metoprolol", "Atenolol", "Bisoprolol", "Carvedilol", "Labetalol",
            "Nebivolol", "Nadolol", "Sotalol", "Pindolol", "Timolol", "Esmolol", "Acebutolol",
        ] {
            map[name.lowercased()] = [.betaBlocker]
        }

        // Mirtazapine (NaSSA): a strong H1 antagonist that raises 5-HT/NE *release* via presynaptic
        // α2 blockade while antagonising postsynaptic 5-HT2/5-HT3 — it does NOT inhibit serotonin
        // reuptake, so it is neither a SERT blocker (`.ssri`, which would predict false MDMA blunting)
        // nor a dangerous serotonin adder (`.serotonergic`). Modeled by its faithful acute property:
        // antihistaminergic sedation.
        map["mirtazapine"] = [.antihistamine]

        // ── RC-expansion (2026-06-23): cathinones, designer benzos, eugeroics ──
        // Grounded in the Foundation-C RC evidence runs. The cathinone class is NOT a
        // uniform "releaser" family: membership is set per the substance's measured
        // mechanism flag (releaser vs hybrid vs pure blocker) and DAT:SERT lean, so the
        // engine applies the right interaction rules (empathogen blunting/serotonin
        // danger vs plain stimulant) instead of a class-wide assumption.

        // Substrate RELEASERS — balanced DAT:SERT (~1.8–2.4) reads empathogen-like
        // (mephedrone/methylone/4-CMC), so they ride the MDMA-style [.empathogen, .stimulant]
        // bucket (SSRI blunting + MAOI serotonin-toxicity rules apply).
        for name in ["Mephedrone", "4-MMC", "Methylone", "bk-MDMA", "4-CMC", "Clephedrone", "Ethylone", "bk-MDEA"] {
            map[name.lowercased()] = [.empathogen, .stimulant]
        }
        // Catecholamine-leaning releasers (DAT:SERT ≥4) and the uncharacterised CMC/MMC
        // isomers → stimulant-leaning. Kept SEPARATE from their para-isomers (no aliasing).
        for name in ["3-MMC", "Metaphedrone", "2-MMC", "3-CMC", "Clophedrone", "2-CMC"] {
            map[name.lowercased()] = [.stimulant]
        }
        // HYBRIDS — a single α-alkyl/N-ethyl substituent flips DAT substrate→blocker.
        // SERT-substrate hybrids keep a mild empathogenic lean; DAT/NET-blocker hybrids
        // and the pure blocker NEP are stimulant-only (NOT empathogens, despite mis-sale).
        for name in ["Butylone", "bk-MBDB", "4-MEC", "Mexedrone"] {
            map[name.lowercased()] = [.stimulant, .empathogen]
        }
        for name in ["Pentylone", "Eutylone", "bk-EBDB", "N-Ethylpentylone", "NEP", "Ephylone"] {
            map[name.lowercased()] = [.stimulant]
        }
        // Pure pyrrolidinophenone reuptake BLOCKERS — stimulant ONLY (must NOT ride the
        // empathogen/releaser bucket). SERT-sparing → no serotonergic edge.
        for name in ["MDPV", "Alpha-PVP", "α-PVP", "a-PVP", "Flakka", "Alpha-PHP", "α-PHP", "Alpha-PiHP", "α-PiHP", "MDPBP", "MDPPP"] {
            map[name.lowercased()] = [.stimulant]
        }
        // …EXCEPT naphyrone — the family outlier that potently blocks SERT (~46 nM), a
        // genuine serotonin adder. Data-driven edge; the rest of the family does NOT inherit it.
        for name in ["Naphyrone", "NRG-1", "Naphthylpyrovalerone"] {
            map[name.lowercased()] = [.stimulant, .serotonergic]
        }
        // 4-MA: balanced serotonin releaser + MAO-A inhibitor (PMA-class) — serotonin-toxicity /
        // hyperthermia danger. RING-POSITION-SPECIFIC: do NOT propagate to the fluoro isomers.
        for name in ["4-MA", "4-methylamphetamine", "PAL-313"] {
            map[name.lowercased()] = [.stimulant, .serotonergic]
        }
        // Fluoro/methyl amphetamine analogues — plain stimulant releasers (catecholamine-
        // selective; 4-FA's para serotonergic lean is character, not a danger-class flag).
        for name in ["2-FA", "3-FA", "4-FA", "2-FMA", "3-FMA", "4-FMA"] {
            map[name.lowercased()] = [.stimulant]
        }
        // Memantine — moderate-affinity, FAST-off NMDA open-channel blocker. Routed to
        // .dissociative (no dedicated NMDA bucket), but it is NOT ketamine/PCP-strength.
        map["memantine"] = [.dissociative]
        // Adrafinil — hepatic prodrug of modafinil; bromantane — weak indirect dopaminergic
        // (TH/AAAD upregulation). Both stimulant-like. (Modafinil/armodafinil already .stimulant.)
        map["adrafinil"] = [.stimulant]
        map["bromantane"] = [.stimulant]
        // O-DSMT (M1) — potent pure µ-agonist (the opioid limb of tramadol). Plain opioid:
        // the serotonergic/seizure liability lives with the PARENT, not the metabolite.
        map["o-dsmt"] = [.opioid]
        map["o-desmethyltramadol"] = [.opioid]
        // Designer benzodiazepines — interact like classical benzos (additive CNS/respiratory
        // depression with opioids/alcohol/Z-drugs). Diazepam-equivalence is a separate honesty
        // problem (see BenzoEquivalence) — class membership here only drives interaction rules.
        for name in [
            "Clonazolam", "Flualprazolam", "Flubromazolam", "Bromazolam", "Diclazepam",
            "Flubromazepam", "Etizolam", "Deschloroetizolam", "Metizolam", "Flunitrazolam",
            "Adinazolam", "Nifoxipam", "Norflurazepam", "Pyrazolam", "Meclonazepam",
        ] {
            map[name.lowercased()] = [.benzodiazepine]
        }

        // Barbiturates. Category `Depressant` routes to `.other`, so without this every
        // barbiturate pairing — including with opioids and benzodiazepines — returned
        // nothing at all. Primidone belongs here because it is metabolized to
        // phenobarbital; its own anticonvulsant category says nothing about that.
        for name in [
            "Phenobarbital", "Pentobarbital", "Secobarbital", "Amobarbital", "Butalbital",
            "Barbital", "Allobarbital", "Hexobarbital", "Thiopental", "Butabarbital",
            "Methohexital", "Aprobarbital", "Talbutal", "Primidone",
        ] {
            map[name.lowercased()] = [.barbiturate]
        }

        // Methylene blue is a potent reversible MAO-A inhibitor at doses used clinically,
        // and serotonin toxicity with serotonergic drugs is the documented consequence —
        // an FDA drug-safety communication exists for exactly this pair. Its `Nootropic`
        // category routed it to `.other`, so every MAOI rule missed it.
        map["methylene blue"] = [.maoi]
        map["methylthioninium chloride"] = [.maoi]

        return map
    }()

    /// Lazy cache mapping lowercased substance names (and aliases) to their
    /// resolved drug classes. Filled on first lookup via ``SubstanceLibrary``.
    /// Memoised drug-class lookups. `OSAllocatedUnfairLock` owns the dictionary,
    /// so it can only be touched inside `withLock` — safe from the parallel
    /// contexts this `nonisolated` static is called from (notably Swift Testing's
    /// concurrent tasks, where an unsynchronized static `Dictionary` mutation
    /// crashes with a spurious "index out of range").
    private static let drugClassCache = OSAllocatedUnfairLock<[String: [DrugClass]]>(initialState: [:])

    /// Get drug classes for a substance name. Falls back to a `SubstanceLibrary`
    /// lookup (canonical name or alias) when not in the overrides table; the
    /// result is memoised for subsequent calls. Misses are deliberately NOT
    /// memoised: a transient lookup failure (store not yet warm, or a startup
    /// race) must not permanently poison a substance's interactions.
    static func drugClasses(for substanceName: String) -> [DrugClass] {
        let lower = substanceName.lowercased()

        if let override = substanceClassOverrides[lower] {
            return override
        }

        if let cached = drugClassCache.withLock({ $0[lower] }) {
            return cached
        }

        guard let substance = SubstanceLibrary.lookup(substanceName) else {
            return []
        }
        // Re-check the overrides under the canonical name: the table is keyed by one
        // spelling, and a logged dose may carry any alias ("Nembutal", "Luminal",
        // "Blue Heavens"). Without this an override silently loses to the category
        // fallback for every name but the one it was written under.
        let resolved = substanceClassOverrides[substance.name.lowercased()]
            ?? [categoryToDrugClass(substance.category)]
        drugClassCache.withLock { $0[lower] = resolved }
        return resolved
    }

    private static func categoryToDrugClass(_ category: SubstanceCategory) -> DrugClass {
        switch category {
        case .opioid: .opioid
        case .benzodiazepine: .benzodiazepine
        case .stimulant: .stimulant
        case .psychedelic: .psychedelic
        case .dissociative: .dissociative
        // KOR agonists are pharmacologically closer to dissociatives than to
        // classical psychedelics — they don't engage 5-HT2A, but the kappa
        // mechanism shares acute dissociation/derealisation phenomenology and
        // (more importantly for interaction modeling) compounds with
        // dissociatives or sedatives. Route to `.dissociative` until we add a
        // dedicated `.kappaAgonist` class with its own rule set.
        case .dysdelic: .dissociative
        case .empathogen: .empathogen
        case .cannabinoid: .cannabinoid
        case .gabapentinoid: .gabapentinoid
        case .ampakine: .other
        // Eugeroics block DAT/NET like stimulants and stack badly with serotonergics
        // and MAOIs — treat as `.stimulant` for interaction purposes.
        case .eugeroic: .stimulant
        // Default fallback for the `.antidepressant` category. SSRI is the
        // most common subtype, so this is the safest serotonergic proxy when
        // we have no better information. **Failure mode:** any imported MAOI,
        // SNRI, or TCA that lacks a name/alias hit in
        // `substanceClassOverrides` will silently land here and be matched
        // against SSRI rules — missing MAOI×stimulant or SNRI×empathogen
        // warnings, for instance. When such a gap is discovered, add the
        // substance to `substanceClassOverrides` with the correct subtype.
        case .antidepressant: .ssri
        case .antipsychotic: .antipsychotic
        case .supplement: .supplement
        case .nootropic: .other
        case .depressant: .other
        case .orexinAntagonist: .orexinAntagonist
        case .analgesic: .other
        case .antihistamine: .antihistamine
        // Deliriants are anticholinergic/antimuscarinic; their dominant interaction
        // concern is additive anticholinergic toxicity, the same profile as the
        // first-gen antihistamines they were split out of. Route to `.antihistamine`
        // so those rules (and the sedative/anticholinergic stacking warnings) apply.
        case .deliriant: .antihistamine
        case .cardiovascular: .other
        case .antimicrobial: .other
        case .gastrointestinal: .other
        case .respiratory: .other
        case .endocrine: .other
        case .immunological: .other
        case .peptide: .other
        // Anticonvulsants are pharmacologically heterogeneous (sodium-channel
        // blockers, SV2A ligands, gabapentinoids, GABAergics) — no single
        // safe class proxy. Route to `.other` and let
        // `substanceClassOverrides` map specific drugs (gabapentin,
        // pregabalin → `.gabapentinoid`; benzo-class anticonvulsants
        // → `.benzodiazepine`) where the subtype is known.
        case .anticonvulsant: .other
        case .other: .other
        }
    }

    // MARK: - Interaction Rules

    private static let rules: [InteractionRule] = [
        // === DANGEROUS ===

        InteractionRule(
            classA: .opioid,
            classB: .benzodiazepine,
            severity: .dangerous,
            description: "Combined respiratory depression — the leading cause of overdose death.",
        ),
        InteractionRule(
            classA: .opioid,
            classB: .ghb,
            severity: .dangerous,
            description: "Severe respiratory depression — both substances suppress breathing.",
        ),
        InteractionRule(
            classA: .opioid,
            classB: .alcohol,
            severity: .dangerous,
            description: "Respiratory depression and CNS shutdown — potentially fatal combination.",
        ),
        InteractionRule(
            classA: .maoi,
            classB: .empathogen,
            severity: .dangerous,
            description: "Risk of fatal serotonin syndrome — do not combine.",
        ),
        InteractionRule(
            classA: .maoi,
            classB: .ssri,
            severity: .dangerous,
            description: "Serotonin syndrome — potentially fatal. Allow 2+ week washout.",
        ),
        InteractionRule(
            classA: .maoi,
            classB: .snri,
            severity: .dangerous,
            description: "Serotonin syndrome — potentially fatal. Allow 2+ week washout.",
        ),
        InteractionRule(
            classA: .maoi,
            classB: .tca,
            severity: .dangerous,
            description: "Risk of serotonin syndrome and hypertensive crisis.",
        ),
        InteractionRule(
            classA: .maoi,
            classB: .stimulant,
            severity: .dangerous,
            description: "Hypertensive crisis — potentially fatal spike in blood pressure.",
        ),
        InteractionRule(
            classA: .maoi,
            classB: .opioid,
            severity: .dangerous,
            description: "Risk of serotonin syndrome, especially with meperidine/pethidine, tramadol, and tapentadol.",
        ),
        InteractionRule(
            classA: .lithium,
            classB: .psychedelic,
            severity: .dangerous,
            description: "Risk of seizures and serotonin toxicity — well-documented dangerous combination.",
        ),
        InteractionRule(
            classA: .ghb,
            classB: .alcohol,
            severity: .dangerous,
            description: "Respiratory depression and loss of consciousness — very narrow safety margin.",
        ),
        InteractionRule(
            classA: .ghb,
            classB: .benzodiazepine,
            severity: .dangerous,
            description: "Severe respiratory depression — both are GABAergic depressants.",
        ),
        InteractionRule(
            classA: .benzodiazepine,
            classB: .alcohol,
            severity: .dangerous,
            description: "Life-threatening respiratory depression — this combination is a leading cause of overdose death.",
        ),

        // === UNSAFE ===

        InteractionRule(
            classA: .opioid,
            classB: .gabapentinoid,
            severity: .unsafe,
            description: "Enhanced respiratory depression — gabapentinoids increase opioid overdose risk.",
        ),
        InteractionRule(
            classA: .opioid,
            classB: .opioid,
            severity: .unsafe,
            description: "Stacking opioids is unpredictable — respiratory depression risk compounds.",
        ),
        InteractionRule(
            classA: .opioid,
            classB: .antihistamine,
            severity: .unsafe,
            description: "Additive CNS and respiratory depression — antihistamines potentiate opioid sedation.",
        ),
        InteractionRule(
            classA: .opioid,
            classB: .stimulant,
            severity: .unsafe,
            description: "Stimulants mask overdose signs — when they wear off, respiratory depression can emerge.",
        ),
        InteractionRule(
            classA: .benzodiazepine,
            classB: .gabapentinoid,
            severity: .unsafe,
            description: "Excessive sedation and respiratory depression risk.",
        ),
        InteractionRule(
            classA: .benzodiazepine,
            classB: .antihistamine,
            severity: .unsafe,
            description: "Compounded CNS depression — excessive sedation and impaired breathing.",
        ),
        // Antidepressant SERT blockers + empathogen: a myth-buster, not a danger. These compete for
        // SERT and *blunt* the empathogen (it may feel much weaker or not work) — on their own they do
        // not cause serotonin syndrome; the real lethal serotonergic edge is the MAOI rules above. Kept
        // visible (and bypassing the relevance gate via `persistentClasses`) so people aren't blindsided
        // when their dose does nothing, but colored `.caution`, not danger.
        InteractionRule(
            classA: .ssri,
            classB: .empathogen,
            severity: .caution,
            description: "SSRIs usually blunt MDMA — it may feel much weaker, so people often redose into trouble (overheating, heart strain). On their own they don't cause serotonin syndrome.",
        ),
        InteractionRule(
            classA: .snri,
            classB: .empathogen,
            severity: .caution,
            description: "SNRIs usually blunt MDMA — it may feel weaker, so people often redose into trouble (overheating, heart strain). On their own they don't cause serotonin syndrome.",
        ),
        InteractionRule(
            classA: .tca,
            classB: .empathogen,
            severity: .caution,
            description: "TCAs usually blunt MDMA rather than boosting it, so people may redose; the bigger concern is added strain on heart rate and blood pressure.",
        ),

        // === SEROTONIN-ADDING AGENTS (tramadol, meperidine, DXM) ===
        // Genuine additive serotonin-toxicity risk — these RAISE serotonin (unlike antidepressant SERT
        // blockers, which blunt empathogens), so they stack rather than compete. Grounded in the
        // Foundation-C serotonergic evidence run (2026-06-22): tramadol SS grade B/HIGH, seizure A/HIGH.
        InteractionRule(
            classA: .serotonergic,
            classB: .empathogen,
            severity: .dangerous,
            description: "Serotonin syndrome risk — these drugs add serotonin on top of an empathogen's surge. Some (tramadol, meperidine) can also trigger seizures.",
        ),
        InteractionRule(
            classA: .serotonergic,
            classB: .maoi,
            severity: .dangerous,
            description: "Serotonin syndrome — potentially fatal. Do not combine.",
        ),
        InteractionRule(
            classA: .serotonergic,
            classB: .serotonergic,
            severity: .unsafe,
            description: "Serotonin syndrome risk — two serotonin-raising drugs stacked together.",
        ),
        InteractionRule(
            classA: .serotonergic,
            classB: .ssri,
            severity: .unsafe,
            description: "Serotonin syndrome risk — a serotonin-raising drug stacked with an SSRI.",
        ),
        InteractionRule(
            classA: .serotonergic,
            classB: .snri,
            severity: .unsafe,
            description: "Serotonin syndrome risk — a serotonin-raising drug stacked with an SNRI.",
        ),
        InteractionRule(
            classA: .serotonergic,
            classB: .tca,
            severity: .unsafe,
            description: "Serotonin syndrome risk — a serotonin-raising drug stacked with a tricyclic antidepressant.",
        ),
        InteractionRule(
            classA: .serotonergic,
            classB: .lithium,
            severity: .unsafe,
            description: "Increased serotonin syndrome risk — lithium adds to the serotonergic load.",
        ),

        // === ALPHA-2 AGONISTS & BETA-BLOCKERS ===
        // Grounded in the Foundation-C alpha-2/beta-blocker evidence run (2026-06-22). Key corrections:
        // the alpha-2 + opioid danger is the xylazine/"tranq" reality (naloxone won't reverse the alpha-2
        // part); the genuine "unopposed alpha" is alpha-2 *withdrawal* while beta-blocked, NOT routine
        // beta-blocker + stimulant (that contraindication is contested dogma → caution, not danger).
        InteractionRule(
            classA: .alpha2Agonist,
            classB: .opioid,
            severity: .dangerous,
            description: "Heavy sedation with a dangerously slow heart rate and breathing. Naloxone reverses the opioid but NOT the alpha-2 part — give rescue breaths and call for help even after naloxone.",
        ),
        InteractionRule(
            classA: .alpha2Agonist,
            classB: .alcohol,
            severity: .caution,
            description: "Adds up sedation and lowers blood pressure further — expect stronger drowsiness and dizziness. Use less and don't drive.",
        ),
        InteractionRule(
            classA: .alpha2Agonist,
            classB: .benzodiazepine,
            severity: .caution,
            description: "Compounded sedation and low blood pressure — stronger drowsiness and dizziness.",
        ),
        InteractionRule(
            classA: .alpha2Agonist,
            classB: .gabapentinoid,
            severity: .caution,
            description: "Additive sedation and low blood pressure — increased drowsiness and dizziness.",
        ),
        InteractionRule(
            classA: .alpha2Agonist,
            classB: .tca,
            severity: .caution,
            description: "Tricyclics can cancel out clonidine-type blood-pressure lowering, so blood pressure may rise — a medical issue more than an overdose risk.",
        ),
        InteractionRule(
            classA: .betaBlocker,
            classB: .alpha2Agonist,
            severity: .unsafe,
            description: "Don't stop the clonidine-type drug suddenly while on a beta-blocker — it can spike blood pressure to dangerous levels. Taper it slowly.",
        ),
        InteractionRule(
            classA: .betaBlocker,
            classB: .stimulant,
            severity: .caution,
            description: "The old \u{201C}never mix\u{201D} warning is largely a medical myth — large reviews found no real harm. Both still strain the heart, so it isn't a green light to combine them.",
        ),
        InteractionRule(
            classA: .betaBlocker,
            classB: .alcohol,
            severity: .caution,
            description: "Both can lower blood pressure and add to dizziness — you may feel faint, especially standing up.",
        ),

        // === OREXIN ANTAGONISTS (DORAs) ===
        // Suvorexant / lemborexant / daridorexant. Grounded in the FDA labels + respiratory-safety
        // literature: DORAs block OX1R/OX2R rather than enhancing GABA, so combining with other CNS
        // depressants adds next-day sedation and psychomotor/fall risk, but they do NOT depress the
        // brainstem respiratory drive — so the lethal respiratory synergy of benzo+opioid does not
        // apply. All `.caution`, deliberately two tiers below that danger, with wording that says so.
        InteractionRule(
            classA: .orexinAntagonist,
            classB: .opioid,
            severity: .caution,
            description: "Added drowsiness and next-day grogginess, with more fall and coordination risk. Unlike a benzo, an orexin antagonist doesn't suppress breathing, so this isn't the deadly opioid+benzo combination — but still use less, and don't drive.",
        ),
        InteractionRule(
            classA: .orexinAntagonist,
            classB: .alcohol,
            severity: .caution,
            description: "Alcohol stacks psychomotor and memory impairment on top of the sleep med (and raises lemborexant's blood levels) — expect worse next-day grogginess and unsteadiness. The labels advise against drinking with these.",
        ),
        InteractionRule(
            classA: .orexinAntagonist,
            classB: .benzodiazepine,
            severity: .caution,
            description: "Two sleep-promoting drugs stacked — additive next-day sedation and fall risk, and largely redundant. Not the respiratory danger of benzo+opioid, but heavier grogginess and impaired coordination.",
        ),
        InteractionRule(
            classA: .orexinAntagonist,
            classB: .gabapentinoid,
            severity: .caution,
            description: "Additive sedation and next-day grogginess — more drowsiness, dizziness, and fall risk. Use less and avoid driving.",
        ),
        InteractionRule(
            classA: .orexinAntagonist,
            classB: .ghb,
            severity: .caution,
            description: "Compounded sedation — stronger, deeper drowsiness. The orexin antagonist doesn't add respiratory depression itself, but GHB can, so keep doses low and don't combine when alone.",
        ),
        InteractionRule(
            classA: .orexinAntagonist,
            classB: .antihistamine,
            severity: .caution,
            description: "Both cause drowsiness — expect additive next-day sedation and grogginess. Use less and don't drive.",
        ),
        InteractionRule(
            classA: .dissociative,
            classB: .opioid,
            severity: .unsafe,
            description: "Respiratory depression risk — dissociatives can mask overdose signs.",
        ),
        InteractionRule(
            classA: .opioid,
            classB: .antipsychotic,
            severity: .unsafe,
            description: "Additive CNS and respiratory depression.",
        ),
        InteractionRule(
            classA: .lithium,
            classB: .ssri,
            severity: .unsafe,
            description: "Increased risk of serotonin syndrome and lithium toxicity.",
        ),
        InteractionRule(
            classA: .lithium,
            classB: .snri,
            severity: .unsafe,
            description: "Increased risk of serotonin syndrome and lithium toxicity.",
        ),
        InteractionRule(
            classA: .maoi,
            classB: .dissociative,
            severity: .unsafe,
            description: "Serotonin syndrome risk — especially with DXM and other serotonergic dissociatives.",
        ),

        // === BARBITURATES ===
        // Kept as one block across all three severities because the ordering is the point:
        // a barbiturate sits ABOVE a benzodiazepine on every depressant pairing, not level
        // with it. Direct chloride-channel opening has no modulator ceiling, so the
        // respiratory depression keeps deepening with dose instead of plateauing.
        InteractionRule(
            classA: .barbiturate,
            classB: .opioid,
            severity: .dangerous,
            description: "Combined respiratory depression with no ceiling — barbiturates deepen an opioid's suppression of breathing until it stops.",
        ),
        InteractionRule(
            classA: .barbiturate,
            classB: .benzodiazepine,
            severity: .dangerous,
            description: "Life-threatening respiratory depression. A barbiturate opens the GABA-A channel directly rather than modulating it, so this stacks past the point where benzodiazepines alone level off.",
        ),
        InteractionRule(
            classA: .barbiturate,
            classB: .alcohol,
            severity: .dangerous,
            description: "Life-threatening respiratory depression and loss of consciousness — the classic fatal combination.",
        ),
        InteractionRule(
            classA: .barbiturate,
            classB: .ghb,
            severity: .dangerous,
            description: "Severe respiratory depression — two direct-acting depressants with no shared ceiling.",
        ),
        InteractionRule(
            classA: .barbiturate,
            classB: .barbiturate,
            severity: .dangerous,
            description: "Doses add with no plateau, and the gap between a sedating dose and a fatal one is narrow to begin with.",
        ),
        InteractionRule(
            classA: .barbiturate,
            classB: .gabapentinoid,
            severity: .unsafe,
            description: "Additive sedation and respiratory depression.",
        ),
        InteractionRule(
            classA: .barbiturate,
            classB: .antihistamine,
            severity: .unsafe,
            description: "Heavy additive sedation — profound drowsiness and impaired breathing.",
        ),
        InteractionRule(
            classA: .barbiturate,
            classB: .dissociative,
            severity: .unsafe,
            description: "Additive CNS and respiratory depression, with a raised risk of vomiting while unresponsive.",
        ),
        InteractionRule(
            classA: .barbiturate,
            classB: .alpha2Agonist,
            severity: .caution,
            description: "Additive sedation, low blood pressure, and slow heart rate.",
        ),
        InteractionRule(
            classA: .barbiturate,
            classB: .orexinAntagonist,
            severity: .caution,
            description: "Additive sedation and next-day impairment.",
        ),
        InteractionRule(
            classA: .barbiturate,
            classB: .cannabinoid,
            severity: .caution,
            description: "Additive sedation, dizziness, and slowed reaction time.",
        ),
        InteractionRule(
            classA: .barbiturate,
            classB: .antipsychotic,
            severity: .caution,
            description: "Additive CNS depression — increased sedation and impairment.",
        ),

        // === CAUTION ===

        InteractionRule(
            classA: .stimulant,
            classB: .stimulant,
            severity: .caution,
            description: "Cardiovascular strain — combined stimulants increase heart rate and blood pressure.",
        ),
        InteractionRule(
            classA: .stimulant,
            classB: .psychedelic,
            severity: .caution,
            description: "Increased anxiety and vasoconstriction — stimulants can intensify difficult trips.",
        ),
        InteractionRule(
            classA: .cannabinoid,
            classB: .psychedelic,
            severity: .caution,
            description: "Unpredictable intensification — cannabis can trigger anxiety or thought loops.",
        ),
        InteractionRule(
            classA: .dissociative,
            classB: .alcohol,
            severity: .unsafe,
            description: "Risk of respiratory depression, aspiration, and loss of consciousness.",
        ),
        InteractionRule(
            classA: .dissociative,
            classB: .benzodiazepine,
            severity: .unsafe,
            description: "Significant respiratory depression risk and profound loss of consciousness.",
        ),
        InteractionRule(
            classA: .benzodiazepine,
            classB: .benzodiazepine,
            severity: .unsafe,
            description: "Stacking benzodiazepines dramatically increases sedation and respiratory depression risk.",
        ),
        InteractionRule(
            classA: .ssri,
            classB: .psychedelic,
            severity: .caution,
            description: "SSRIs typically reduce psychedelic effects but may increase risk with some compounds.",
        ),
        InteractionRule(
            classA: .ssri,
            classB: .ssri,
            severity: .caution,
            description: "Serotonin accumulation risk — combining serotonergic agents increases toxicity chance.",
        ),
        InteractionRule(
            classA: .ssri,
            classB: .snri,
            severity: .unsafe,
            description: "Overlapping serotonin reuptake inhibition — increased serotonin syndrome risk.",
        ),
        InteractionRule(
            classA: .ssri,
            classB: .tca,
            severity: .unsafe,
            description: "SSRIs inhibit TCA metabolism — risk of TCA toxicity and serotonin syndrome.",
        ),
        InteractionRule(
            classA: .stimulant,
            classB: .dissociative,
            severity: .caution,
            description: "Increased heart rate and blood pressure — cardiovascular strain.",
        ),
        InteractionRule(
            classA: .alcohol,
            classB: .stimulant,
            severity: .caution,
            description: "Stimulants mask alcohol impairment — risk of overconsumption.",
        ),
        InteractionRule(
            classA: .alcohol,
            classB: .antihistamine,
            severity: .caution,
            description: "Compounded drowsiness and impaired coordination.",
        ),
        InteractionRule(
            classA: .alcohol,
            classB: .antipsychotic,
            severity: .caution,
            description: "Additive CNS depression — increased sedation and impairment.",
        ),
        InteractionRule(
            classA: .gabapentinoid,
            classB: .alcohol,
            severity: .unsafe,
            description: "Enhanced CNS depression — risk of respiratory depression and death.",
        ),
        InteractionRule(
            classA: .gabapentinoid,
            classB: .gabapentinoid,
            severity: .caution,
            description: "Stacking gabapentinoids compounds sedation and respiratory depression risk.",
        ),
        InteractionRule(
            classA: .dissociative,
            classB: .dissociative,
            severity: .caution,
            description: "Compounded dissociation — disorientation and loss of motor control.",
        ),
        InteractionRule(
            classA: .empathogen,
            classB: .empathogen,
            severity: .caution,
            description: "Serotonin depletion and neurotoxicity risk — allow adequate recovery between uses.",
        ),
        InteractionRule(
            classA: .lithium,
            classB: .empathogen,
            severity: .dangerous,
            description: "Risk of seizures and serotonin toxicity — potentially fatal combination.",
        ),
        InteractionRule(
            classA: .lithium,
            classB: .maoi,
            severity: .unsafe,
            description: "Risk of serotonin syndrome and lithium toxicity.",
        ),

        // Additional rules from audit
        InteractionRule(
            classA: .stimulant,
            classB: .ssri,
            severity: .caution,
            description: "Some combinations increase serotonin or seizure risk — monitor for symptoms.",
        ),
        InteractionRule(
            classA: .stimulant,
            classB: .snri,
            severity: .caution,
            description: "Cardiovascular strain and potential serotonin interaction — monitor heart rate and blood pressure.",
        ),
        InteractionRule(
            classA: .antipsychotic,
            classB: .antipsychotic,
            severity: .caution,
            description: "Combined QTc prolongation risk — monitor cardiac rhythm.",
        ),
        InteractionRule(
            classA: .gabapentinoid,
            classB: .antihistamine,
            severity: .caution,
            description: "Additive CNS depression — increased sedation and impaired coordination.",
        ),
        InteractionRule(
            classA: .cannabinoid,
            classB: .benzodiazepine,
            severity: .caution,
            description: "Additive sedation — may increase drowsiness and impaired coordination.",
        ),
        InteractionRule(
            classA: .cannabinoid,
            classB: .opioid,
            severity: .caution,
            description: "Additive CNS depression — may increase sedation and respiratory depression risk.",
        ),
        InteractionRule(
            classA: .cannabinoid,
            classB: .alcohol,
            severity: .caution,
            description: "Additive impairment — increased dizziness, drowsiness, and slowed reaction time.",
        ),
    ]

    /// Precomputed rule lookup keyed by sorted class pairs for O(1) access.
    /// Whether any rule mentions `drugClass`. A class no rule mentions makes
    /// every substance routed to it interaction-invisible.
    static func hasAnyRule(_ drugClass: DrugClass) -> Bool {
        rules.contains { $0.classA == drugClass || $0.classB == drugClass }
    }

    /// Class pairs declared more than once. `ruleLookup` is keyed on the sorted
    /// pair and last-wins, so a duplicate silently discards the earlier rule —
    /// harmless while both say the same thing, and invisible when they stop.
    static var duplicateRuleKeys: [String] {
        var seen: Set<String> = []
        var duplicates: [String] = []
        for rule in rules {
            if !seen.insert(rule.key).inserted { duplicates.append(rule.key) }
        }
        return duplicates
    }

    private static let ruleLookup: [String: InteractionRule] = {
        var dict: [String: InteractionRule] = [:]
        // Bundled rules FIRST, so a hand-written one overwrites them. TripSit's
        // matrix is community consensus; the table below carries adjudications
        // that deliberately contradict folk ordering — MDMA + SSRI is blockade,
        // not danger, and the real danger there is MAOI. Where the two disagree
        // the curated verdict is the one that has been checked.
        for bundled in SubstanceStore.shared.classInteractionRules() {
            guard let classA = DrugClass(rawValue: bundled.classA),
                  let classB = DrugClass(rawValue: bundled.classB),
                  let severity = InteractionSeverity(bundledName: bundled.severity)
            else { continue }
            let key = [classA.rawValue, classB.rawValue].sorted().joined(separator: "|")
            dict[key] = InteractionRule(
                classA: classA, classB: classB, severity: severity, note: bundled.note,
            )
        }
        for rule in rules {
            let key = [rule.classA.rawValue, rule.classB.rawValue].sorted().joined(separator: "|")
            dict[key] = rule
        }
        return dict
    }()

    private static func findRule(_ a: DrugClass, _ b: DrugClass) -> InteractionRule? {
        let key = [a.rawValue, b.rawValue].sorted().joined(separator: "|")
        return ruleLookup[key]
    }

    // MARK: - Relevance Gating

    /// Drug classes whose interactions outlast the subjective effect curve, so
    /// they bypass the effect-overlap gate and are never suppressed on dose.
    /// See ``InteractionRule/isPersistent``.
    static let persistentClasses: Set<DrugClass> = [.maoi, .lithium, .ssri, .snri, .tca]

    /// Below this relevance (`overlap · dose`) the explorer marks a pair as
    /// low-likelihood; warn surfaces suppress earlier, on the confident-low
    /// signals in ``gatePair(prospective:active:persistent:)``.
    static let lowRelevanceThreshold = 0.25

    /// Effect-overlap peak below which two doses are treated as not concurrent.
    private static let overlapSuppressThreshold = 0.05

    /// Dose magnitude (`amount / heavy`) at or below which a participant is
    /// treated as confidently sub-threshold — its presence in the pair is
    /// negligible, so the *interaction* (not the drug itself) is irrelevant.
    ///
    /// This equals ``ActiveSubstanceState/minimumIntensity``, the floor
    /// `computeDoseMagnitude` clamps to: a substance *with* dose-range data
    /// whose magnitude bottoms out here is ≤5 % of a heavy dose. Substances
    /// with no dose data resolve to ``ActiveSubstanceState/unknownIntensity``
    /// (0.60) instead, so they are never mistaken for trivial — exactly the
    /// "only suppress when we have good data" requirement.
    private static let trivialMagnitude = ActiveSubstanceState.minimumIntensity

    /// Magnitude window over which dose presence ramps `0 → 1` (smoothstep). At
    /// or above ``presenceFull`` a dose counts fully; below ``presenceLow`` it
    /// barely registers.
    private static let presenceLow = 0.04
    private static let presenceFull = 0.25

    /// One dose's subjective-effect track on the wall clock: when it was taken
    /// and the state whose ``TimelineCurveModel/effectShape(at:for:)`` gives its
    /// strength over time.
    private struct EffectTrack {
        let state: ActiveSubstanceState
        let start: Date
        /// `false` when the amount is unknown (a prospective / name-only dose),
        /// so dose presence is treated as neutral rather than confident.
        let amountKnown: Bool

        var magnitude: Double {
            state.doseMagnitude
        }
        var effectEndMinutes: Double {
            max(state.offsetEndMinutes, state.totalMinutes)
        }
    }

    private struct GateResult {
        let overlapFactor: Double
        let doseFactor: Double
        let suppress: Bool
    }

    /// Grade a single pair: its temporal overlap, combined dose presence, and
    /// whether good data makes it confidently irrelevant (and so suppressible
    /// on a warn surface). `persistent` rules skip both the effect-overlap and
    /// dose suppression — they fire whenever co-present in the long window.
    private static func gatePair(prospective: EffectTrack?, active: EffectTrack?, persistent: Bool) -> GateResult {
        let presenceProspective = prospective.map { $0.amountKnown ? presence($0.magnitude) : 1.0 } ?? 1.0
        let presenceActive = active.map { $0.amountKnown ? presence($0.magnitude) : 1.0 } ?? 1.0
        let doseFactor = presenceProspective * presenceActive

        let doseConfidentLow = !persistent && (
            (active?.amountKnown == true && active!.magnitude <= trivialMagnitude)
                || (prospective?.amountKnown == true && prospective!.magnitude <= trivialMagnitude)
        )

        var overlapFactor = 1.0
        var overlapConfidentLow = false
        if !persistent, let p = prospective, let a = active {
            overlapFactor = effectOverlap(p, a)
            overlapConfidentLow = overlapFactor < overlapSuppressThreshold
        }

        return GateResult(
            overlapFactor: overlapFactor,
            doseFactor: doseFactor,
            suppress: overlapConfidentLow || doseConfidentLow,
        )
    }

    /// Peak of the product of two doses' effect curves over the window where
    /// they could co-occur. `0` when the curves never overlap in wall-clock
    /// time (a morning dose long faded by an evening one).
    private static func effectOverlap(_ a: EffectTrack, _ b: EffectTrack) -> Double {
        let laterStart = max(a.start, b.start)
        let endA = a.start.addingTimeInterval(a.effectEndMinutes * 60)
        let endB = b.start.addingTimeInterval(b.effectEndMinutes * 60)
        let windowEnd = min(endA, endB)
        guard windowEnd > laterStart else { return 0 }

        let steps = 64
        let span = windowEnd.timeIntervalSince(laterStart)
        var peak = 0.0
        for i in 0 ... steps {
            let t = laterStart.addingTimeInterval(span * Double(i) / Double(steps))
            let shapeA = TimelineCurveModel.effectShape(at: t.timeIntervalSince(a.start) / 60, for: a.state)
            let shapeB = TimelineCurveModel.effectShape(at: t.timeIntervalSince(b.start) / 60, for: b.state)
            peak = max(peak, shapeA * shapeB)
        }
        return peak
    }

    /// Dose-presence weight in `[0, 1]`: ≈1 at a meaningful dose, →0 for a
    /// clearly sub-threshold one. Smoothstep over `[presenceLow, presenceFull]`.
    private static func presence(_ magnitude: Double) -> Double {
        let t = min(1, max(0, (magnitude - presenceLow) / (presenceFull - presenceLow)))
        return t * t * (3 - 2 * t)
    }

    /// Build the effect track for an already-logged entry (amount known).
    private static func track(for entry: DoseEntry) -> EffectTrack? {
        guard let state = ActiveSubstanceState.from(entry: entry, colorHex: "") else { return nil }
        return EffectTrack(state: state, start: entry.timestamp, amountKnown: true)
    }

    /// Build the effect track for a prospective dose from its name alone — it
    /// starts "now" on its default route, and its amount is treated as unknown
    /// (only the *shape* of the curve, which is dose-independent, is used).
    private static func prospectiveTrack(for substanceName: String) -> EffectTrack? {
        guard let substance = SubstanceLibrary.lookup(substanceName) else { return nil }
        let entry = DoseEntry(substance: substanceName, amount: 1, route: substance.defaultRoute)
        guard let state = ActiveSubstanceState.from(entry: entry, colorHex: "") else { return nil }
        return EffectTrack(state: state, start: entry.timestamp, amountKnown: false)
    }

    // MARK: - Active Entry Detection

    /// Filter entries to those still pharmacologically active
    static func activeEntries(from entries: [DoseEntry]) -> [DoseEntry] {
        let now = Date.now
        return entries.filter { entry in
            guard let substance = SubstanceLibrary.lookup(entry.substance) else {
                // Unknown substance — assume active for 24h as safety fallback
                return entry.timestamp.addingTimeInterval(86_400) > now
            }
            if let duration = substance.duration(for: entry.route) {
                return entry.timestamp.addingTimeInterval(duration.estimatedTotalMinutes * 60) > now
            }
            if let halfLife = substance.halfLifeMinutes {
                // 5 half-lives ≈ 97% eliminated
                return entry.timestamp.addingTimeInterval(halfLife * 5 * 60) > now
            }
            // No duration or half-life data — assume active for 24h
            return entry.timestamp.addingTimeInterval(86_400) > now
        }
    }
}
