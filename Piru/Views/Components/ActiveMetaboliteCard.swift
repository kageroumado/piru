import SwiftUI

// The "Also Active" surface: what your body turns a substance into, when that
// byproduct is doing some of the work. Distinct from the Metabolism disclosure,
// which answers "how does my body clear this" — enzymes, clearance shares,
// citations — and stays pharma-nerd. This answers "is something other than what
// I took producing the effect", which is a fact about the user's experience
// rather than reference data, and so is surfaced a tier earlier.

/// One metabolite, folded from every ``SubstanceStore/MetabolismHit`` naming it.
///
/// Grouping is by metabolite rather than by enzyme (the table's axis) because a
/// reader cares which *molecule* is active, not which pathway made it — and a
/// metabolite is routinely produced by several enzymes (bromazepam's
/// 3-hydroxybromazepam comes off both CYP1A2 and CYP3A4), which as separate rows
/// would say the same thing twice.
struct ActiveMetabolite: Identifiable {
    let name: String
    /// Non-nil when the metabolite is itself in the library, making the card a
    /// link to its own screen — its real dose ranges and durations beat any
    /// summary we could restate here.
    let substanceName: String?
    let enzymes: [String]
    let halfLifeMinutes: Double?
    let formationFractionPct: Double?
    let mechanism: SubstanceStore.MetaboliteMechanism
    /// Every potency measurement recorded for this metabolite, at most one per
    /// basis. Kept as a list because bases answer different questions and must
    /// never be merged: oxycodone → oxymorphone is 4000% by receptor affinity
    /// *and* 1000% clinically, and an average of those answers neither.
    let potencies: [Potency]
    let sourceSlug: String
    let doi: String?
    let pmid: Int?
    /// A recorded magnitude we are declining to print, because its basis was
    /// never recorded. The reader may have met that figure elsewhere and is owed
    /// the fact that it isn't established — which is different from a strength
    /// nobody ever measured, where we say nothing rather than volunteering
    /// "unknown" on hundreds of cards.
    let hasSuppressedMagnitude: Bool

    var id: String {
        name
    }

    /// What to call this metabolite on screen. The library's own name wins when
    /// we carry it: the raw `metabolite_name` is a curator's string, so it
    /// arrives lowercase and often trailing a synonym — "nordazepam
    /// (N-desmethyldiazepam)" — which reads as noise beside a capitalized parent
    /// and overflows a chip. `Nordazepam` is the same molecule, better said.
    var displayName: String {
        substanceName ?? name
    }

    struct Potency {
        let pct: Double
        let basis: SubstanceStore.MetabolitePotencyBasis
        let target: String?
    }

    /// Fold the rows naming one metabolite into a single card model.
    ///
    /// Mechanism resolves by precedence — `divergent` > `scaled` > `unknown` —
    /// rather than by first-wins. `unknown` means "nobody classified this", so
    /// any classified sibling outranks it; and where two classified rows somehow
    /// disagree, `divergent` is the conservative answer because it is the one
    /// that *forbids* treating a potency as a multiplier.
    static func from(rows: [SubstanceStore.MetabolismHit]) -> ActiveMetabolite? {
        guard let first = rows.first, let name = first.metaboliteName else { return nil }

        var potencies: [Potency] = []
        var seenBases: Set<SubstanceStore.MetabolitePotencyBasis> = []
        for row in rows {
            guard let pct = row.metabolitePotencyVsParentPct,
                  let basis = row.metabolitePotencyBasis,
                  // A recorded zero is the marker for an inactive metabolite,
                  // not a magnitude — it must never reach the formatter and
                  // render as "0×".
                  pct > 0,
                  // An unknown basis is an uninterpretable number: nobody wrote
                  // down what was measured, so there is nothing to qualify it
                  // with and no honest way to state it.
                  basis != .unknown,
                  seenBases.insert(basis).inserted
            else { continue }
            potencies.append(Potency(pct: pct, basis: basis, target: row.metabolitePotencyTarget))
        }

        let mechanism: SubstanceStore.MetaboliteMechanism =
            if rows.contains(where: { $0.metaboliteMechanismVsParent == .divergent }) { .divergent }
            else if rows.contains(where: { $0.metaboliteMechanismVsParent == .scaled }) { .scaled }
            else { .unknown }

        return ActiveMetabolite(
            name: name,
            substanceName: rows.compactMap(\.metaboliteSubstanceName).first,
            enzymes: rows.map(\.enzyme).uniqued(),
            halfLifeMinutes: rows.compactMap(\.metaboliteHalfLifeMinutes).first,
            formationFractionPct: rows.compactMap(\.formationFractionPct).first,
            mechanism: mechanism,
            // Clinical first: it is the only basis that may lead a card, and the
            // resolver reads `potencies.first` when nothing better applies.
            potencies: potencies.sorted { lhs, _ in lhs.basis == .clinical },
            sourceSlug: first.sourceSlug,
            doi: rows.compactMap(\.doi).first,
            pmid: rows.compactMap(\.pmid).first,
            hasSuppressedMagnitude: potencies.isEmpty && rows.contains {
                ($0.metabolitePotencyVsParentPct ?? 0) > 0
            },
        )
    }

    /// Whether this metabolite has anything worth a card. Promoting every active
    /// row would print ~100 cards reading only "Active", which makes the common
    /// case worse rather than better — the section has to stay silent unless it
    /// can say something.
    var isWorthShowing: Bool {
        substanceName != nil || !potencies.isEmpty || halfLifeMinutes != nil
            || formationFractionPct != nil
    }

    /// Whether the metabolite is doing enough to be worth a claim about the
    /// user's *experience*, as opposed to merely existing.
    ///
    /// `metabolite_active` alone cannot answer this. The flag is set on trace
    /// species whose own potency column contradicts it — cotinine at 1 % of
    /// nicotine's receptor affinity, desmethylsertraline at 4 % — because
    /// "detectable and not wholly inert" is a different question from "does
    /// something you would notice". So a *measured* potency outranks the flag in
    /// both directions, and where nothing was measured we accept only the strong
    /// structural signal: carrying the metabolite as a drug in its own right,
    /// with its own sourced doses and durations.
    ///
    /// The threshold sits in a wide empty band — measured potencies in the
    /// catalog are 1 %, 4 %, then 20 % and up — so it is not a knife edge.
    var isMateriallyActive: Bool {
        if potencies.contains(where: { $0.pct >= Threshold.materialPotencyPct }) { return true }
        // Measured, and measured small. The row already told us.
        if !potencies.isEmpty { return false }
        return substanceName != nil
    }

    /// Whether conversion runs through a polymorphic enzyme, i.e. how much
    /// metabolite a given person makes is substantially genetic. Worth saying
    /// whenever the metabolite carries the effect: it is the difference between
    /// "tramadol did nothing for me" and "tramadol hit me hard", and it is the
    /// single most useful thing on a card like codeine's or tramadol's.
    var conversionVariesByGenetics: Bool {
        enzymes.contains { enzyme in
            Threshold.polymorphicEnzymes.contains { enzyme.uppercased().contains($0) }
        }
    }

    enum Threshold {
        /// Below this, a measured potency is evidence *against* the metabolite
        /// mattering, not for it.
        static let materialPotencyPct: Double = 10
        /// A metabolite may only be described as outlasting the parent's stated
        /// duration when this much of a dose is known to become it. Absent the
        /// figure we do not claim dose equivalence at all.
        static let doseEquivalentFormationPct: Double = 50
        /// Enzymes whose activity varies enough between people to change what a
        /// dose does. Matched as substrings so "CYP2D6 (O-demethylation)" hits.
        static let polymorphicEnzymes = ["CYP2D6", "CYP2C19"]
    }
}

private extension [String] {
    /// Order-preserving dedup — enzymes are displayed in the order the pathways
    /// were recorded.
    func uniqued() -> [String] {
        var seen: Set<String> = []
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - Statement

/// The user-facing claim a card leads with.
///
/// Every rendered sentence is produced from this enum, and there is deliberately
/// **no case that emits a bare multiplier**. A potency figure reads as clinical
/// strength whatever produced it, and most of ours are not that — so the only
/// case carrying an unqualified comparative is ``comparable``, which the
/// resolver reaches only for a `scaled` metabolite measured `clinical`ly. The
/// qualified case emits its claim and its hedge as one value, so a caller cannot
/// render the number and drop the caveat.
enum MetaboliteStatement {
    /// The metabolite is still going after the duration the reader just read.
    /// Measured against **the number displayed above the card**, not against the
    /// parent's half-life, because that is what the sentence actually claims.
    case outlastsDuration(metabolite: String, parent: String)
    /// The same fact where no duration profile exists to point at — the chronic
    /// medications (SSRIs and friends) that carry a half-life and no acute
    /// duration table. Worded to stand alone rather than referring upward at
    /// something that isn't there.
    case persistsBeyondParent(metabolite: String, parent: String)
    /// The only unqualified comparative in the app, and only when the share of
    /// the dose that converts is known to be high enough for "dose for dose" to
    /// mean anything.
    case comparable(ratio: Double, parent: String)
    /// A potency ratio between the two *molecules*, where too little of a dose
    /// converts for it to be a claim about doses. Codeine → morphine is the case
    /// that matters: 10× is right molecule-for-molecule and badly wrong
    /// dose-for-dose, because only a small part of a codeine dose is ever
    /// demethylated.
    ///
    /// `convertedPct` carries the share when we know it — oxycodone records that
    /// 11 % becomes oxymorphone, and stating that is far more use than the ratio
    /// alone. `nil` means unrecorded, which must be said rather than implied.
    case strongerMolecule(ratio: Double, parent: String, metabolite: String, convertedPct: Double?)
    /// A comparative that must carry its basis and target.
    case qualified(ratio: Double, parent: String, basis: SubstanceStore.MetabolitePotencyBasis, target: String?)
    /// Different pharmacology, not a stronger parent. Better described than
    /// quantified; any measurement is demoted to a caption.
    case divergent(parent: String)
    /// The relationship alone. Not a failure state — "your body turns diazepam
    /// into temazepam, which is active too" is new information to most readers,
    /// needs no number, and cannot be wrong.
    case relationshipOnly(parent: String, metabolite: String)
}

extension ActiveMetabolite {
    /// Resolve the headline claim.
    ///
    /// **Divergence is tested first.** A metabolite with different pharmacology
    /// is not the parent lasting longer, and describing it that way is wrong in
    /// the way most likely to be believed — trazodone's mCPP is anxiogenic, so
    /// "the same effects, drawn out" inverts what it does. The old ordering ran
    /// the duration test first and produced exactly that sentence.
    ///
    /// The duration claim then needs positive evidence on **every** axis, and
    /// degrades to the relationship alone when it cannot get it. It is an
    /// assertion about what the reader will feel, so:
    ///
    /// - ``isMateriallyActive`` — a metabolite at 1 % of the parent's affinity
    ///   changes nothing no matter how long it lingers. This is what a bare
    ///   `metabolite_active` flag misses.
    /// - Measured against `parentDurationMinutes`, the figure shown above the
    ///   card, rather than against the parent's half-life. The half-life
    ///   comparison selected *for* prodrugs — an inert parent has a short
    ///   half-life by definition, so psilocybin → psilocin and
    ///   lisdexamfetamine → d-amphetamine always cleared it, while the duration
    ///   table the sentence points at was already describing the metabolite.
    ///   Comparing against the displayed number makes the claim self-consistent:
    ///   it can only fire when there is genuinely something past the end of it.
    func statement(
        parentName: String,
        parentHalfLifeMinutes: Double?,
        parentDurationMinutes: Double?,
    ) -> MetaboliteStatement {
        if mechanism == .divergent {
            return .divergent(parent: parentName)
        }
        if isMateriallyActive, let mine = halfLifeMinutes {
            if let duration = parentDurationMinutes, duration > 0 {
                if mine >= duration {
                    return .outlastsDuration(metabolite: displayName, parent: parentName)
                }
            } else if let parent = parentHalfLifeMinutes, parent > 0, mine >= parent * 2 {
                return .persistsBeyondParent(metabolite: displayName, parent: parentName)
            }
        }
        if let clinical = potencies.first(where: { $0.basis == .clinical }), mechanism == .scaled {
            // "Dose for dose" is a claim about doses, and it is only true when
            // most of a dose actually becomes the metabolite. Without that term
            // the ratio still means something — it just means it about the
            // molecules, which is a different sentence.
            if let fraction = formationFractionPct, fraction >= Threshold.doseEquivalentFormationPct {
                return .comparable(ratio: clinical.pct / 100, parent: parentName)
            }
            return .strongerMolecule(
                ratio: clinical.pct / 100, parent: parentName, metabolite: displayName,
                convertedPct: formationFractionPct,
            )
        }
        if let measured = potencies.first {
            return .qualified(
                ratio: measured.pct / 100, parent: parentName,
                basis: measured.basis, target: measured.target,
            )
        }
        return .relationshipOnly(parent: parentName, metabolite: displayName)
    }

    /// Whether this metabolite has earned a section of its own.
    ///
    /// Only a **duration** consequence does. A metabolite is a normal, expected
    /// part of how a drug works, and saying so at section volume overstates it:
    /// oxymorphone is oxycodone's principal pathway and its 10 : 1 potency ratio
    /// is textbook, so promoting it to a headline implies news where there is
    /// none — and duplicates the Metabolism table sitting directly below.
    ///
    /// What the reader cannot get anywhere else on the screen is that the dose
    /// keeps working after the duration says it stopped. That is the whole
    /// warrant for this surface. Potency ratios, divergent pharmacology and bare
    /// relationships stay in the Metabolism disclosure, which is where reference
    /// data belongs.
    ///
    /// The resolver above deliberately still models every statement: it answers
    /// "what can honestly be said", and this answers the separate, editorial
    /// question of "what deserves a section". Keeping them apart means a future
    /// inline surface can use the rest without relaxing this gate.
    func earnsOwnSection(parentHalfLifeMinutes: Double?, parentDurationMinutes: Double?) -> Bool {
        switch statement(
            parentName: "", parentHalfLifeMinutes: parentHalfLifeMinutes,
            parentDurationMinutes: parentDurationMinutes,
        ) {
        case .outlastsDuration, .persistsBeyondParent: true
        case .comparable, .strongerMolecule, .qualified, .divergent, .relationshipOnly: false
        }
    }

    /// Any measurement that survives as a *secondary* line under the headline —
    /// the affinity figure beneath oxycodone's clinical one, or the lone
    /// measurement on a divergent card. Always rendered with basis and target.
    func secondaryPotency(for statement: MetaboliteStatement) -> Potency? {
        switch statement {
        case .comparable, .strongerMolecule:
            // The clinical claim is the headline; anything else is a different
            // question and follows it rather than replacing it.
            potencies.first { $0.basis != .clinical }
        case .divergent:
            // A clinical ratio is withheld here, not merely demoted. Printing
            // one under "acts differently" contradicts the headline in the same
            // breath, and it quantifies the axis that *didn't* change:
            // normeperidine's 50 % of pethidine's analgesia is true and beside
            // the point, since what makes it matter is that it is a convulsant.
            // Affinity and in-vitro figures survive — they carry their own
            // hedges and cannot be read as clinical strength.
            potencies.first { $0.basis != .clinical }
        case .outlastsDuration, .persistsBeyondParent:
            potencies.first
        case .qualified, .relationshipOnly:
            nil
        }
    }
}

/// Display names for the receptor a potency was measured at. A raw token is not
/// user-facing, and `clinical-effect` never renders — it *is* the clinical
/// claim, so naming it would be circular.
func metaboliteTargetName(_ raw: String?) -> String? {
    guard let raw, raw != "clinical-effect" else { return nil }
    switch raw.uppercased() {
    case "MOR": return String(localized: "µ-opioid receptor")
    case "KOR": return String(localized: "κ-opioid receptor")
    case "DOR": return String(localized: "δ-opioid receptor")
    case "SERT": return String(localized: "serotonin transporter")
    case "NET": return String(localized: "norepinephrine transporter")
    case "DAT": return String(localized: "dopamine transporter")
    case "GABA-A": return String(localized: "GABA-A receptor")
    case "NMDA": return String(localized: "NMDA receptor")
    case "NACHR": return String(localized: "nicotinic receptor")
    default: return raw
    }
}

// MARK: - Card

/// One metabolite, led by what it means for the reader rather than by its
/// chemistry. The name is the subject; the statement beneath it is the payload.
///
/// A number never out-ranks the sentence explaining it: claims sit at
/// `.subheadline`/`.primary`, every hedge and secondary measurement at
/// `.caption`/`Theme.secondaryLabel`.
struct ActiveMetaboliteCard: View {
    let metabolite: ActiveMetabolite
    let parentName: String
    let parentHalfLifeMinutes: Double?
    let accent: Color
    /// The total duration displayed above this card, which the duration claim is
    /// measured against. Nil for substances with no acute duration profile —
    /// chronic medications, where there is no "duration above" to outlast.
    let parentDurationMinutes: Double?
    /// Push the metabolite's own detail. Absent when it isn't in the library,
    /// which is the card's only degradation — every other band is identical, so
    /// a missing link never reads as missing information.
    var onOpenSubstance: ((String) -> Void)?

    private var statement: MetaboliteStatement {
        metabolite.statement(
            parentName: parentName,
            parentHalfLifeMinutes: parentHalfLifeMinutes,
            parentDurationMinutes: parentDurationMinutes,
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            nameRow
            VStack(alignment: .leading, spacing: 6) {
                primaryLine
                secondaryLines
            }
            chips
            sourceLine(
                slug: metabolite.sourceSlug, detail: nil,
                doi: metabolite.doi, pmid: metabolite.pmid, accent: accent,
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .themeCard()
    }

    // MARK: Bands

    @ViewBuilder
    private var nameRow: some View {
        if let target = metabolite.substanceName, let onOpenSubstance {
            Button { onOpenSubstance(target) } label: {
                HStack(spacing: 6) {
                    Text(verbatim: metabolite.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens this substance in the library."))
        } else {
            Text(verbatim: metabolite.displayName)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var primaryLine: some View {
        Text(primaryText)
            .font(.subheadline)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The hedge (when the claim needs one), any second measurement, and the
    /// note that a figure was withheld. All caption-weight — none may compete
    /// with the headline.
    @ViewBuilder
    private var secondaryLines: some View {
        if case let .qualified(_, _, basis, _) = statement {
            caption(hedge(for: basis))
        }
        if let extra = metabolite.secondaryPotency(for: statement) {
            caption(measurementText(extra, prefix: hasHeadlineClaim))
        }
        if metabolite.conversionVariesByGenetics {
            caption(String(localized: "How much of this you make is partly genetic — the same dose produces noticeably more in some people than others."))
        }
        if metabolite.hasSuppressedMagnitude {
            caption(String(localized: "How strong it is compared to \(parentName) hasn't been established."))
        }
    }

    /// `Made by`, the half-life pair, and the share of the dose that becomes
    /// this metabolite. The half-life pair is the answer to "why is this still
    /// going" as a *layout* rather than a sentence — nothing to translate.
    @ViewBuilder
    private var chips: some View {
        let halfLives = halfLifePair
        if !metabolite.enzymes.isEmpty || halfLives != nil || metabolite.formationFractionPct != nil {
            HStack(alignment: .top, spacing: 8) {
                if !metabolite.enzymes.isEmpty {
                    PKMetricChip(
                        label: "Made by",
                        value: metabolite.enzymes.joined(separator: ", "),
                    )
                }
                if let halfLives {
                    PKMetricChip(verbatimLabel: metabolite.displayName, value: halfLives.metabolite)
                    PKMetricChip(verbatimLabel: parentName, value: halfLives.parent)
                }
                if let fraction = metabolite.formationFractionPct {
                    PKMetricChip(
                        label: "Share of dose",
                        value: "~\(SubstanceDetailView.chemNumber(fraction))%",
                    )
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Copy

    private var hasHeadlineClaim: Bool {
        switch statement {
        case .comparable, .strongerMolecule: true
        case .outlastsDuration, .persistsBeyondParent, .qualified, .divergent, .relationshipOnly: false
        }
    }

    /// Both half-lives, or neither — a lone number invites the reader to compare
    /// it against something they don't have.
    private var halfLifePair: (metabolite: String, parent: String)? {
        guard let mine = metabolite.halfLifeMinutes, let parent = parentHalfLifeMinutes else { return nil }
        return (pkMinutes(mine), pkMinutes(parent))
    }

    private var primaryText: String {
        switch statement {
        case let .outlastsDuration(metabolite, parent):
            String(localized: "Effects can outlast the duration above — \(metabolite) clears much more slowly than \(parent).")
        case let .persistsBeyondParent(metabolite, parent):
            String(localized: "\(metabolite) stays active in your body long after \(parent) itself is gone.")
        case let .comparable(ratio, parent):
            ratio == 1
                ? String(localized: "About as strong as \(parent), dose for dose.")
                : String(localized: "About \(SubstanceDetailView.chemNumber(ratio))× as strong as \(parent), dose for dose.")
        case let .strongerMolecule(ratio, parent, metabolite, convertedPct):
            // A prodrug converting one-for-one lands here whenever its formation
            // fraction was never recorded (psilocybin → psilocin). "About 1× as
            // strong" is not a sentence, so parity gets its own wording.
            if ratio == 1 {
                String(localized: "Molecule for molecule, \(metabolite) is about as strong as \(parent).")
            } else if let convertedPct {
                // The useful sentence, and the one oxycodone can actually make:
                // the ratio is only half the story, and the other half is on the
                // row. Naming it is what stops "10× as strong" being read as a
                // dose claim.
                String(localized: "Molecule for molecule, \(metabolite) is about \(SubstanceDetailView.chemNumber(ratio))× as strong as \(parent) — but only about \(SubstanceDetailView.chemNumber(convertedPct))% of a dose becomes it.")
            } else {
                String(localized: "Molecule for molecule, \(metabolite) is about \(SubstanceDetailView.chemNumber(ratio))× as strong as \(parent) — but how much of a dose converts isn't recorded here.")
            }
        case let .qualified(ratio, parent, _, target):
            if let target = metaboliteTargetName(target) {
                ratio == 1
                    ? String(localized: "About as strong as \(parent) at the \(target).")
                    : String(localized: "About \(SubstanceDetailView.chemNumber(ratio))× \(parent)'s activity at the \(target).")
            } else {
                String(localized: "About \(SubstanceDetailView.chemNumber(ratio))× \(parent)'s activity, by one measurement.")
            }
        case let .divergent(parent):
            String(localized: "Acts differently from \(parent) — not simply stronger or weaker.")
        case let .relationshipOnly(parent, metabolite):
            String(localized: "Your body turns \(parent) into \(metabolite), which is active too.")
        }
    }

    private func hedge(for basis: SubstanceStore.MetabolitePotencyBasis) -> String {
        switch basis {
        case .receptorAffinity: String(localized: "A binding-affinity measurement, not clinical potency.")
        case .inVitro, .clinical, .unknown: String(localized: "A lab measurement, not clinical potency.")
        }
    }

    /// A measurement rendered as a full sentence carrying its own basis and
    /// target, so it can be read on its own without the headline above it.
    ///
    /// A **clinical** measurement takes the plain comparative and no hedge —
    /// describing it as "a lab measurement, not clinical potency" would be
    /// flatly untrue, and that is exactly what a single shared phrasing did to
    /// diazepam → nordazepam. Only affinity/in-vitro figures get hedged.
    private func measurementText(_ potency: ActiveMetabolite.Potency, prefix: Bool) -> String {
        let ratio = SubstanceDetailView.chemNumber(potency.pct / 100)
        if potency.basis == .clinical {
            // Same rule as the headline: "dose for dose" needs the share of the
            // dose that converts, or it is a molecule ratio wearing a dose
            // ratio's clothes.
            guard let fraction = metabolite.formationFractionPct,
                  fraction >= ActiveMetabolite.Threshold.doseEquivalentFormationPct
            else {
                return String(localized: "Molecule for molecule, about \(ratio)× as strong as \(parentName).")
            }
            return potency.pct == 100
                ? String(localized: "About as strong as \(parentName), dose for dose.")
                : String(localized: "About \(ratio)× as strong as \(parentName), dose for dose.")
        }
        let kind = potency.basis == .receptorAffinity
            ? String(localized: "binding affinity")
            : String(localized: "activity")
        guard let target = metaboliteTargetName(potency.target) else {
            return prefix
                ? String(localized: "Also measured at \(ratio)× \(parentName)'s \(kind) — a lab measurement, not clinical potency.")
                : String(localized: "Measured at \(ratio)× \(parentName)'s \(kind) — a lab measurement, not clinical potency.")
        }
        return prefix
            ? String(localized: "Also measured at \(ratio)× \(parentName)'s \(kind) at the \(target) — a lab measurement, not clinical potency.")
            : String(localized: "Measured at \(ratio)× \(parentName)'s \(kind) at the \(target) — a lab measurement, not clinical potency.")
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.secondaryLabel)
            .fixedSize(horizontal: false, vertical: true)
    }
}
