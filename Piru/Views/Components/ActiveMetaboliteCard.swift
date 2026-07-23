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
    /// The metabolite outlives the parent enough to change the felt duration —
    /// derived from the half-life pair, so it needs no curation and cannot go
    /// stale. This outranks a potency line: "it lasts much longer than the
    /// duration table above" is the more useful fact when both are available.
    case durationConsequence(metabolite: String, parent: String)
    /// The only unqualified comparative in the app.
    case comparable(ratio: Double, parent: String)
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
    /// Resolve the headline claim. Order is deliberate: duration consequence
    /// first (most useful and most widely derivable), divergence next (a ratio
    /// would mislead), then comparatives in descending trustworthiness.
    func statement(parentName: String, parentHalfLifeMinutes: Double?) -> MetaboliteStatement {
        if let mine = halfLifeMinutes, let parent = parentHalfLifeMinutes, parent > 0, mine >= parent * 2 {
            return .durationConsequence(metabolite: displayName, parent: parentName)
        }
        if mechanism == .divergent {
            return .divergent(parent: parentName)
        }
        if let clinical = potencies.first(where: { $0.basis == .clinical }), mechanism == .scaled {
            return .comparable(ratio: clinical.pct / 100, parent: parentName)
        }
        if let measured = potencies.first {
            return .qualified(
                ratio: measured.pct / 100, parent: parentName,
                basis: measured.basis, target: measured.target,
            )
        }
        return .relationshipOnly(parent: parentName, metabolite: displayName)
    }

    /// Any measurement that survives as a *secondary* line under the headline —
    /// the affinity figure beneath oxycodone's clinical one, or the lone
    /// measurement on a divergent card. Always rendered with basis and target.
    func secondaryPotency(for statement: MetaboliteStatement) -> Potency? {
        switch statement {
        case .comparable:
            // The clinical claim is the headline; anything else is a different
            // question and follows it rather than replacing it.
            potencies.first { $0.basis != .clinical }
        case .divergent, .durationConsequence:
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
    /// Push the metabolite's own detail. Absent when it isn't in the library,
    /// which is the card's only degradation — every other band is identical, so
    /// a missing link never reads as missing information.
    var onOpenSubstance: ((String) -> Void)?

    private var statement: MetaboliteStatement {
        metabolite.statement(parentName: parentName, parentHalfLifeMinutes: parentHalfLifeMinutes)
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
        if case .comparable = statement { return true }
        return false
    }

    /// Both half-lives, or neither — a lone number invites the reader to compare
    /// it against something they don't have.
    private var halfLifePair: (metabolite: String, parent: String)? {
        guard let mine = metabolite.halfLifeMinutes, let parent = parentHalfLifeMinutes else { return nil }
        return (pkMinutes(mine), pkMinutes(parent))
    }

    private var primaryText: String {
        switch statement {
        case let .durationConsequence(metabolite, parent):
            String(localized: "Effects can outlast the duration above — \(metabolite) clears much more slowly than \(parent).")
        case let .comparable(ratio, parent):
            ratio == 1
                ? String(localized: "About as strong as \(parent), dose for dose.")
                : String(localized: "About \(SubstanceDetailView.chemNumber(ratio))× as strong as \(parent), dose for dose.")
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
