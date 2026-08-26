import Foundation
import os
import SwiftUI

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
    case pharmacokinetic
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
    /// Piru's own localized sentence for the pair where it has one, and the
    /// database row's English note where it does not — see ``InteractionRuleCopy``.
    let description: String

    /// The class pair this rule is written against, order-independent. This is
    /// the rule's identity: two pairs firing the same rule share a cause, which
    /// two pairs merely sharing boilerplate prose do not.
    var key: String {
        InteractionRuleCopy.key(classA, classB)
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
/// Every rule comes from the bundled database's `interaction_rules`: Piru's own
/// adjudicated verdicts, and TripSit's combination matrix for the pairs those do
/// not cover. Which pair interacts and how badly is data; the *sentence* shown
/// for a pair Piru has adjudicated is localized copy and lives in
/// ``InteractionRuleCopy``, keyed by the same class pair.
///
/// ## Severity ordering
///
/// ``InteractionSeverity`` orders `dangerous > unsafe > caution`. Batch
/// deduplication keeps the highest-severity result for each substance pair so
/// users always see the worst-case warning.
///
/// ## Caveats
///
/// ``DrugClass/other`` participates in **zero** rules. Any substance whose
/// category resolves to `.other` (analgesics, cardiovascular, antimicrobials,
/// GI, respiratory, endocrine, immunological, depressants not otherwise
/// classified, etc.) is interaction-invisible: it returns nothing for every
/// pairing. The fix is a row in `substance_interaction_classes` lifting the
/// substance into a real class — that is how barbiturates and methylene blue
/// were recovered.
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
                if let rule = findRule(a, b), best.map({ rule.severity > $0.severity }) ?? true {
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
                    guard let resolved = canonicalName(for: name), candidates[resolved] != nil else { continue }
                    seen.insert(hit.id)
                    findings.append(PKInteractionFinding(hit: hit))
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

    /// Lazy cache mapping lowercased substance names (and aliases) to their
    /// resolved drug classes. Filled on first lookup via ``SubstanceLibrary``.
    /// Memoised drug-class lookups. `OSAllocatedUnfairLock` owns the dictionary,
    /// so it can only be touched inside `withLock` — safe from the parallel
    /// contexts this `nonisolated` static is called from (notably Swift Testing's
    /// concurrent tasks, where an unsynchronized static `Dictionary` mutation
    /// crashes with a spurious "index out of range").
    private static let drugClassCache = OSAllocatedUnfairLock<[String: [DrugClass]]>(initialState: [:])

    /// Get drug classes for a substance name. Falls back to a `SubstanceLibrary`
    /// lookup (canonical name or alias) when no override names it; the result is
    /// memoised for subsequent calls. Misses are deliberately NOT memoised: a
    /// transient lookup failure (store not yet warm, or a startup race) must not
    /// permanently poison a substance's interactions.
    static func drugClasses(for substanceName: String) -> [DrugClass] {
        let lower = substanceName.lowercased()
        let overrides = SubstanceStore.shared.interactionClasses()

        if let override = overrides[lower] {
            return override
        }

        if let cached = drugClassCache.withLock({ $0[lower] }) {
            return cached
        }

        guard let substance = SubstanceLibrary.lookup(substanceName) else {
            return []
        }
        // Re-check under the canonical name. The overrides already cover every
        // catalog alias, but `SubstanceLibrary` also resolves a user's own
        // relabel — someone who renames Alprazolam to "my anxiety pill" would
        // otherwise fall through to the category.
        let resolved = overrides[substance.name.lowercased()]
            ?? [categoryToDrugClass(substance.category)]
        drugClassCache.withLock { $0[lower] = resolved }
        return resolved
    }

    /// The interaction class a substance's category falls back to.
    ///
    /// `.other` is the default for a category `category_interaction_classes`
    /// does not name, and it participates in no rule — so an unmapped category
    /// makes every substance under it interaction-invisible. That default is in
    /// code because it is what "unmapped" *means*, not a judgment someone made.
    private static func categoryToDrugClass(_ category: SubstanceCategory) -> DrugClass {
        SubstanceStore.shared.categoryInteractionClasses()[category.rawValue] ?? .other
    }

    // MARK: - Interaction Rules

    /// Whether any rule mentions `drugClass`. A class no rule mentions makes
    /// every substance routed to it interaction-invisible.
    static func hasAnyRule(_ drugClass: DrugClass) -> Bool {
        ruleLookup.values.contains { $0.classA == drugClass || $0.classB == drugClass }
    }

    /// Class pairs the database declares more than once. `UNIQUE (class_a,
    /// class_b)` is on the **ordered** tuple, so the same pair written
    /// back-to-front by two ingesters satisfies it and then silently decides by
    /// row order here — harmless while both say the same thing, invisible when
    /// they stop.
    static var duplicateRuleKeys: [String] {
        var seen: Set<String> = []
        var duplicates: [String] = []
        for bundled in SubstanceStore.shared.classInteractionRules() {
            guard let classA = DrugClass(rawValue: bundled.classA),
                  let classB = DrugClass(rawValue: bundled.classB) else { continue }
            let key = InteractionRuleCopy.key(classA, classB)
            if !seen.insert(key).inserted { duplicates.append(key) }
        }
        return duplicates
    }

    /// Every `interaction_rules` row, keyed by its sorted class pair for O(1)
    /// lookup. A pair Piru has adjudicated shows its localized sentence; the
    /// rest show the row's own note, which is TripSit's prose in English.
    private static let ruleLookup: [String: InteractionRule] = {
        var dict: [String: InteractionRule] = [:]
        for bundled in SubstanceStore.shared.classInteractionRules() {
            guard let classA = DrugClass(rawValue: bundled.classA),
                  let classB = DrugClass(rawValue: bundled.classB),
                  let severity = InteractionSeverity(bundledName: bundled.severity)
            else { continue }
            let copy = InteractionRuleCopy.note(classA, classB)
            dict[InteractionRuleCopy.key(classA, classB)] = InteractionRule(
                classA: classA,
                classB: classB,
                severity: severity,
                description: copy.map { String(localized: $0) } ?? bundled.note,
            )
        }
        return dict
    }()

    private static func findRule(_ a: DrugClass, _ b: DrugClass) -> InteractionRule? {
        ruleLookup[InteractionRuleCopy.key(a, b)]
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

        func confidentlyTrivial(_ track: EffectTrack?) -> Bool {
            guard let track, track.amountKnown else { return false }
            return track.magnitude <= trivialMagnitude
        }
        let doseConfidentLow = !persistent && (confidentlyTrivial(active) || confidentlyTrivial(prospective))

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
            // The batch projection carries the durations and half-life this
            // filter reads — several callers pass the whole dose log, so the
            // full `resolveFull` here would be ~21 SQL per uncached substance.
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
