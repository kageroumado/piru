import Foundation

/// The **class signature** for a substance: one rendering, chosen by category, that says where this
/// compound sits among the compounds it is actually comparable to.
///
/// Three renderings, each reused by ≥2 classes, each gated by ``SignatureComparability``:
///
/// | Rendering | Classes | Axis |
/// |---|---|---|
/// | ``EfficacyAxisModel`` | opioid, analgesic, cannabinoid | partial → full activation |
/// | ``TargetBalanceModel`` | psychedelic | 5-HT2A ↔ 5-HT1A |
/// | ``TransporterTernaryModel`` | stimulant, empathogen, antidepressant | SERT / DAT / NET |
///
/// A class with no rankable signature draws nothing: `resolve` returns nil rather than plotting
/// rows that failed the gate.
nonisolated enum ClassSignature: Sendable {
    case efficacy(EfficacyAxisModel)
    case balance(TargetBalanceModel)
    case ternary(TransporterTernaryModel)

    /// Which target family a category's signature reads from — also what the store needs to fetch.
    /// `nil` for classes with no signature at all.
    static func family(for category: SubstanceCategory) -> SignatureFamily? {
        switch category {
        case .opioid, .analgesic: .muOpioid
        case .cannabinoid: .cannabinoid1
        case .psychedelic: .serotonin
        case .dissociative: .nmda
        case .stimulant, .empathogen, .antidepressant: .transporters
        default: nil
        }
    }

    /// Build the signature for one substance from the library-wide legs of its family.
    ///
    /// Returns `nil` when the substance has nothing of the kind at all — an absence card is for a
    /// rendering that was *withheld*, not for a compound the literature simply never measured.
    static func resolve(
        substanceName: String,
        category: SubstanceCategory,
        legs: [SignatureLeg],
    ) -> ClassSignature? {
        switch family(for: category) {
        case .muOpioid: efficacy(substanceName: substanceName, legs: legs, target: .mu)
        case .cannabinoid1: efficacy(substanceName: substanceName, legs: legs, target: .cannabinoid1)
        case .serotonin: balance(substanceName: substanceName, legs: legs)
        case .transporters: ternary(substanceName: substanceName, legs: legs)
        // Dissociatives show no signature card: NMDA-block potency is contested
        // even for ketamine and absent for most of the class, and it isn't the
        // axis that separates them subjectively. Their receptor data lives in the
        // Receptor Literature section — no card here asserting there's no card.
        case .nmda: nil
        case nil: nil
        }
    }
}

/// The store-side fetch a signature needs: which raw `target` rows to pull for the whole library.
nonisolated enum SignatureFamily: String, Hashable, Sendable {
    case transporters
    case serotonin
    case muOpioid
    case cannabinoid1
    case nmda
}

// MARK: - Efficacy axis (partial → full)

nonisolated extension ClassSignature {
    /// The efficacy axis: how far the receptor switches on once occupied — *not* potency, and not
    /// morphine-equivalence.
    ///
    /// Solid marks share an experiment with the focus and may be ranked against it. Hollow marks are
    /// the same measure against the same reference agonist from a **different** study; they are the
    /// only honest way to show the ~20 nitazene/fentanyl rows that carry a bare 100 % intrinsic
    /// activity with no `comparable_set`, and they never read as full-activation ticks on a τ axis
    /// because τ and intrinsic activity are separate bases that never share a rendering.
    static func efficacy(
        substanceName: String,
        legs: [SignatureLeg],
        target: SignatureTarget,
    ) -> ClassSignature? {
        let onTarget = legs.filter { $0.target == target }
        let focusLegs = onTarget.filter { $0.substanceName == substanceName && $0.hasEfficacyValue }
        guard !focusLegs.isEmpty else { return nil }

        let groups = SignatureComparability.partition(onTarget)
            .filter { !$0.basis.isPotency }

        // A ladder needs the focus *and* at least one peer actually measured beside it. Rows that
        // only document an efficacy class (a bare 100 % with no panel) can't make a group comparable
        // — otherwise a paper that called four fentanyl analogues "full agonists" would render as a
        // gated ladder of four identical ticks.
        let gated = groups
            .filter { group in
                let measured = group.legs.filter { !$0.isDocumentedClassOnly }
                guard measured.contains(where: { $0.substanceName == substanceName }) else { return false }
                return Set(measured.map(\.substanceName)).count >= 2
            }
            .max { rank(of: $0) < rank(of: $1) }

        let basis: SignatureBasis
        let solidNames: Set<String>
        var provenanceGroup: ComparableGroup?
        if let gated {
            basis = gated.basis
            solidNames = Set(gated.legs.filter { !$0.isDocumentedClassOnly }.map(\.substanceName))
            provenanceGroup = gated
        } else {
            // Ungated: the focus's own value stands alone. Everything is hollow and the caption says
            // the axis ranks across studies.
            guard let preferred = SignatureBasis.allCases.first(where: { candidate in
                !candidate.isPotency && focusLegs.contains { candidate.value(in: $0) != nil }
            }) else { return nil }
            basis = preferred
            solidNames = []
        }

        guard let focusLeg = bestLeg(focusLegs, basis: basis) else { return nil }
        let referenceKey = focusLeg.referenceAgonistKey

        // Every substance's best leg on this basis against this reference agonist.
        var byName: [String: SignatureLeg] = [:]
        for leg in onTarget where basis.value(in: leg) != nil {
            // A different reference agonist is a different yardstick; 60 % of CP55,940 and 60 % of
            // DAMGO are not the same claim.
            if let referenceKey, let key = leg.referenceAgonistKey, key != referenceKey { continue }
            if solidNames.contains(leg.substanceName), !solidNames.isEmpty {
                // Inside the gate the group's own choice wins, so a second study's row for the same
                // compound can't quietly displace it.
                guard let gated, let inGroup = gated.leg(substance: leg.substanceName, target: target) else { continue }
                byName[leg.substanceName] = inGroup
                continue
            }
            if let existing = byName[leg.substanceName], !isBetter(leg, than: existing, basis: basis) { continue }
            byName[leg.substanceName] = leg
        }
        byName[substanceName] = solidNames.contains(substanceName)
            ? (gated?.leg(substance: substanceName, target: target) ?? focusLeg)
            : focusLeg

        func mark(_ leg: SignatureLeg) -> EfficacyAxisModel.Mark? {
            guard let raw = basis.value(in: leg) else { return nil }
            return EfficacyAxisModel.Mark(
                id: leg.id,
                name: leg.substanceName,
                percent: basis == .tau ? raw * 100 : raw,
                valueText: efficacyValueText(raw, basis: basis),
                isFocus: leg.substanceName == substanceName,
                isGated: solidNames.contains(leg.substanceName) && !leg.isDocumentedClassOnly,
            )
        }

        guard let focusMark = byName[substanceName].flatMap(mark) else { return nil }
        let peers = byName
            .filter { $0.key != substanceName }
            .values
            .compactMap(mark)
        // Thin the hollow peers, never the gated ones. The gated marks *are* the evidence the
        // axis claims — dropping one to an even-index sample leaves the card saying "measured
        // together" while showing only across-study marks. THC's CB1 axis is where this bites:
        // three compounds share its experiment and fourteen more carry a bare CP-55,940 100 %,
        // so an undifferentiated sample of 7 reliably discards two of the three.
        let gatedPeers = peers.filter(\.isGated)
        let hollowPeers = peers.filter { !$0.isGated }
        let model = EfficacyAxisModel(
            focus: focusMark,
            marks: ([focusMark] + gatedPeers + spread(hollowPeers, keeping: 7 - gatedPeers.count))
                .sorted { $0.percent < $1.percent },
            headline: agonistHeadline(focusLeg.action, target: target),
            provenance: provenance(provenanceGroup, fallback: focusLeg, basis: basis),
            isGated: gated != nil,
        )
        return .efficacy(model)
    }

    /// Prefer τ (intrinsic efficacy, system-independent) over intrinsic activity, then human data,
    /// then the group with the most compounds in it.
    private static func rank(of group: ComparableGroup) -> Int {
        (group.basis == .tau ? 400 : 0) + (group.isHuman ? 200 : 0)
            + (group.key.isDeclaredPanel ? 100 : 0) + min(group.substanceNames.count, 20)
    }

    private static func bestLeg(_ legs: [SignatureLeg], basis: SignatureBasis) -> SignatureLeg? {
        legs.filter { basis.value(in: $0) != nil }.min { isBetter($0, than: $1, basis: basis) }
    }

    private static func isBetter(_ lhs: SignatureLeg, than rhs: SignatureLeg, basis _: SignatureBasis) -> Bool {
        // A fitted number beats a row that only documents the class.
        if lhs.isDocumentedClassOnly != rhs.isDocumentedClassOnly { return rhs.isDocumentedClassOnly }
        if lhs.isHuman != rhs.isHuman { return lhs.isHuman }
        if (lhs.comparableSet != nil) != (rhs.comparableSet != nil) { return lhs.comparableSet != nil }
        return (lhs.year ?? 0) > (rhs.year ?? 0)
    }

    private static func efficacyValueText(_ raw: Double, basis: SignatureBasis) -> String {
        basis == .tau
            ? "τ \(raw.formatted(.number.precision(.fractionLength(0 ... 2))))"
            : "\(raw.formatted(.number.precision(.fractionLength(0 ... 0))))%"
    }

    private static func agonistHeadline(_ action: String?, target: SignatureTarget) -> LocalizedStringResource? {
        guard let action, let parsed = BindingAction(rawValue: action) else { return nil }
        switch parsed {
        case .agonist: return target == .mu ? "Full μ-opioid agonist" : "Full agonist"
        case .partialAgonist: return target == .mu ? "Partial μ-opioid agonist" : "Partial agonist"
        case .antagonist, .inverseAgonist: return target == .mu ? "μ-opioid antagonist" : "Antagonist"
        default: return nil
        }
    }

    /// Thin a peer list down to `limit`, keeping both extremes and spreading the rest evenly across
    /// the value range — so the axis stays legible instead of stacking twenty ticks on one pixel.
    private static func spread(
        _ marks: [EfficacyAxisModel.Mark],
        keeping limit: Int,
    ) -> [EfficacyAxisModel.Mark] {
        // A budget of 0 or 1 must mean exactly 0 or 1 marks, never the full list.
        guard limit > 0 else { return [] }
        let sorted = marks.sorted { $0.percent < $1.percent }
        guard sorted.count > limit else { return sorted }
        guard limit > 1 else { return [sorted[sorted.count / 2]] }
        let step = Double(sorted.count - 1) / Double(limit - 1)
        var picked: [EfficacyAxisModel.Mark] = []
        var seen = Set<String>()
        for index in 0 ..< limit {
            let mark = sorted[Int((Double(index) * step).rounded())]
            if seen.insert(mark.id).inserted { picked.append(mark) }
        }
        return picked
    }

    static func provenance(
        _ group: ComparableGroup?,
        fallback: SignatureLeg,
        basis: SignatureBasis,
    ) -> SignatureProvenance {
        if let group {
            return SignatureProvenance(
                basis: basis,
                isDeclaredPanel: group.key.isDeclaredPanel,
                species: group.species,
                referenceAgonist: group.referenceAgonist,
                citationURL: group.citationURL,
            )
        }
        return SignatureProvenance(
            basis: basis,
            isDeclaredPanel: false,
            species: fallback.species,
            referenceAgonist: fallback.referenceAgonist,
            citationURL: fallback.pmid.map { URL(string: "https://pubmed.ncbi.nlm.nih.gov/\($0)/") }
                ?? fallback.doi.flatMap { $0.isEmpty ? nil : URL(string: "https://doi.org/\($0)") },
        )
    }
}

// MARK: - Balance (two targets)

nonisolated extension ClassSignature {
    /// The 5-HT2A ↔ 5-HT1A balance. 5-HT2A gates the visual, perceptual arm; 5-HT1A gates the warm,
    /// bodily one — and one ratio is why 5-MeO-DMT is an overwhelming non-visual state where DMT
    /// draws scenery.
    ///
    /// The focus's own two values **must** come from one experiment: the whole claim is a ratio, and
    /// a ratio across two studies is the exact error the gate exists to stop. When they don't, the
    /// card falls back to 5-HT2A alone and says why.
    static func balance(substanceName: String, legs: [SignatureLeg]) -> ClassSignature? {
        let relevant = legs.filter { $0.target == .serotonin2A || $0.target == .serotonin1A }
        let mine = relevant.filter { $0.substanceName == substanceName }
        guard !mine.isEmpty else { return nil }

        let paired = SignatureComparability.partition(relevant)
            .filter(\.basis.isPotency)
            .filter { group in
                group.leg(substance: substanceName, target: .serotonin2A) != nil
                    && group.leg(substance: substanceName, target: .serotonin1A) != nil
            }
        let group = paired.max { balanceRank($0, focus: substanceName) < balanceRank($1, focus: substanceName) }

        // Ticks for every substance whose own pair is itself gated — each tick is one study.
        var ticks: [TargetBalanceModel.Tick] = []
        var seen = Set<String>()
        for candidate in SignatureComparability.partition(relevant).filter(\.basis.isPotency) {
            for name in candidate.substanceNames where !seen.contains(name) {
                guard let two = candidate.leg(substance: name, target: .serotonin2A),
                      let one = candidate.leg(substance: name, target: .serotonin1A),
                      let twoValue = candidate.basis.value(in: two),
                      let oneValue = candidate.basis.value(in: one),
                      oneValue > 0, twoValue > 0
                else { continue }
                seen.insert(name)
                ticks.append(TargetBalanceModel.Tick(
                    id: "\(candidate.id):\(name)",
                    name: name,
                    ratio: twoValue / oneValue,
                    isFocus: name == substanceName,
                    isGated: group.map { $0.id == candidate.id } ?? false,
                ))
            }
        }

        guard let group,
              let two = group.leg(substance: substanceName, target: .serotonin2A),
              let one = group.leg(substance: substanceName, target: .serotonin1A),
              let twoValue = group.basis.value(in: two),
              let oneValue = group.basis.value(in: one),
              oneValue > 0, twoValue > 0
        else {
            // No gated pair — fall back to 5-HT2A alone rather than mint a ratio across studies.
            let fallback = mine
                .filter { $0.target == .serotonin2A && $0.kiNm != nil }
                .min { ($0.kiNm ?? .infinity) < ($1.kiNm ?? .infinity) }
            guard let fallback, let ki = fallback.kiNm else { return nil }
            return .balance(TargetBalanceModel(
                focus: nil,
                ticks: [],
                ratioText: "",
                valueText: concentrationText(ki, basis: .ki),
                provenance: provenance(nil, fallback: fallback, basis: .ki),
                withheldReason: """
                No single study in our data measured 5-HT2A and 5-HT1A for this compound on one \
                assay, so the balance is withheld — a ratio built from two studies is not a ratio. \
                The 5-HT2A value alone is shown.
                """,
            ))
        }

        let ratio = twoValue / oneValue
        let focusTick = ticks.first { $0.isFocus } ?? TargetBalanceModel.Tick(
            id: "focus", name: substanceName, ratio: ratio, isFocus: true, isGated: true,
        )
        return .balance(TargetBalanceModel(
            focus: focusTick,
            ticks: spreadTicks(ticks.filter { !$0.isFocus }, keeping: 5),
            ratioText: ratioText(ratio),
            valueText: "\(group.basis.symbol) \(shortNanomolar(oneValue)) · \(shortNanomolar(twoValue))",
            provenance: provenance(group, fallback: two, basis: group.basis),
            withheldReason: nil,
        ))
    }

    private static func balanceRank(_ group: ComparableGroup, focus _: String) -> Int {
        (group.key.isDeclaredPanel ? 200 : 0) + (group.isHuman ? 100 : 0) + min(group.substanceNames.count, 50)
    }

    /// "100× 1A" / "3× 2A" / "balanced" — the ratio is 5-HT2A Kᵢ ÷ 5-HT1A Kᵢ, so a big number means
    /// the compound needs far less drug at 5-HT1A.
    private static func ratioText(_ ratio: Double) -> String {
        if ratio >= 1.5 { return "\(scaleText(ratio))× 1A" }
        if ratio <= 0.67 { return "\(scaleText(1 / ratio))× 2A" }
        return String(localized: "balanced", comment: "5-HT2A/5-HT1A balance readout when neither dominates")
    }

    private static func scaleText(_ value: Double) -> String {
        value >= 1_000 ? ">1000" : value.formatted(.number.precision(.fractionLength(0 ... 0)))
    }

    private static func spreadTicks(
        _ ticks: [TargetBalanceModel.Tick],
        keeping limit: Int,
    ) -> [TargetBalanceModel.Tick] {
        let sorted = ticks.sorted { $0.ratio < $1.ratio }
        guard sorted.count > limit, limit > 1 else { return sorted }
        let step = Double(sorted.count - 1) / Double(limit - 1)
        var picked: [TargetBalanceModel.Tick] = []
        var seen = Set<String>()
        for index in 0 ..< limit {
            let tick = sorted[Int((Double(index) * step).rounded())]
            if seen.insert(tick.id).inserted { picked.append(tick) }
        }
        return picked
    }
}

// MARK: - Ternary (SERT / DAT / NET)

nonisolated extension ClassSignature {
    /// The transporter triangle. Potency share is the normalized reciprocal of the half-max
    /// concentration, so a point sits nearest the transporter the compound is most potent at.
    ///
    /// A releaser's EC₅₀ and a blocker's Kᵢ/IC₅₀ are never plotted together. MDMA legitimately has
    /// **two** passing triples — Baumann's rat-synaptosome release EC₅₀ and Simmler's human uptake
    /// IC₅₀ — and they must be carried as two separately-labeled triangles, never averaged, so the
    /// rendering offers a basis switch rather than one triangle.
    static func ternary(substanceName: String, legs: [SignatureLeg]) -> ClassSignature? {
        let transporters: Set<SignatureTarget> = [.sert, .dat, .net]
        let relevant = legs.filter { transporters.contains($0.target) }
        let mine = relevant.filter { $0.substanceName == substanceName }
        guard !mine.isEmpty else { return nil }

        let groups = SignatureComparability.partition(relevant).filter(\.basis.isPotency)

        func point(_ group: ComparableGroup, _ name: String, isGated: Bool) -> TransporterTernaryModel.Point? {
            guard let sert = group.leg(substance: name, target: .sert).flatMap({ group.basis.value(in: $0) }),
                  let dat = group.leg(substance: name, target: .dat).flatMap({ group.basis.value(in: $0) }),
                  let net = group.leg(substance: name, target: .net).flatMap({ group.basis.value(in: $0) }),
                  sert > 0, dat > 0, net > 0
            else { return nil }
            return TransporterTernaryModel.Point(
                id: "\(group.id):\(name)",
                name: name,
                shares: .potencyShare(sert: sert, dat: dat, net: net),
                values: .init(sert: sert, dat: dat, net: net),
                isFocus: name == substanceName,
                isGated: isGated,
                popularity: group.leg(substance: name, target: .dat)?.popularity ?? 0,
            )
        }

        var triples: [TransporterTernaryModel.Triple] = []
        for group in groups {
            guard let focus = point(group, substanceName, isGated: true) else { continue }
            let peers = group.substanceNames
                .filter { $0 != substanceName }
                .compactMap { point(group, $0, isGated: true) }
            // The population on the same basis, each from its own study: context, not a ranking.
            // Ordered by popularity so the plot can name the recognizable ones — a cloud of
            // anonymous dots asks the reader to take the spread on faith, and "4-Fluoroamphetamine"
            // is not a landmark. One entry per compound: the same drug measured in three studies
            // must not spend three of the labelling slots.
            var seenGhost: Set<String> = []
            let ghosts = groups
                .filter { $0.id != group.id && $0.basis == group.basis }
                .flatMap { other in other.substanceNames.compactMap { point(other, $0, isGated: false) } }
                .filter { $0.name != substanceName }
                .sorted { $0.popularity > $1.popularity }
                .filter { seenGhost.insert($0.name).inserted }
            triples.append(TransporterTernaryModel.Triple(
                id: group.id,
                focus: focus,
                peers: peers,
                ghosts: Array(ghosts.prefix(40)),
                provenance: provenance(group, fallback: group.legs[0], basis: group.basis),
                action: dominantAction(group.legs),
            ))
        }

        guard !triples.isEmpty else {
            return .ternary(TransporterTernaryModel(triples: [], withheldReason: withheldTernaryReason(mine)))
        }
        triples.sort { lhs, rhs in
            let lp = lhs.peers.count + (lhs.provenance.isDeclaredPanel ? 10 : 0)
            let rp = rhs.peers.count + (rhs.provenance.isDeclaredPanel ? 10 : 0)
            return lp > rp
        }
        return .ternary(TransporterTernaryModel(triples: triples, withheldReason: nil))
    }

    /// Why the triangle is withheld, in the terms of what is actually missing. The three causes are
    /// genuinely different and a reader can act on the difference: an uncited row may become
    /// plottable when its citation lands, a partial panel never will until someone measures the
    /// third transporter, and a mixed-basis set is a refusal to average a release EC₅₀ against an
    /// uptake Kᵢ. Never collapse them back into one sentence.
    private static func withheldTernaryReason(_ mine: [SignatureLeg]) -> LocalizedStringResource {
        let measured = mine.filter { leg in
            SignatureBasis.allCases.contains { $0.isPotency && $0.value(in: leg) != nil }
        }
        guard !measured.isEmpty else {
            return """
            This compound's transporter rows carry no potency value, so there is nothing to place \
            on the triangle. The rows themselves are in Receptor Literature below.
            """
        }
        let keyed = measured.filter { $0.comparabilityKey != nil }
        guard !keyed.isEmpty else {
            return """
            No transporter measurement for this compound is tied to a study we can identify, and a \
            triangle built from rows that were never established as one panel is not a comparison. \
            The values are in Receptor Literature below.
            """
        }
        let covered = Set(keyed.map(\.target))
        if covered.count < 3 {
            let missing = [SignatureTarget.sert, .dat, .net]
                .filter { !covered.contains($0) }
                .map(\.label)
                .joined(separator: " and ")
            return """
            The triangle needs SERT, DAT and NET from one experiment; no study in our data measured \
            \(missing) for this compound alongside the rest. The values we do have are in Receptor \
            Literature below.
            """
        }
        // Verbatim the copy this card carried before the message was dropped: it names the failure
        // concretely, and it is already translated.
        return """
        No single study in our data measured SERT, DAT and NET for this compound on one basis. \
        Mixing them is how MDMA once rendered as a 95 % noradrenaline drug — a binding Kᵢ plotted \
        against a release EC₅₀ — so the triangle is withheld rather than drawn from rows that \
        can't be ranked together.
        """
    }

    private static func dominantAction(_ legs: [SignatureLeg]) -> BindingAction? {
        var counts: [String: Int] = [:]
        for leg in legs {
            guard let action = leg.action else { continue }
            counts[action, default: 0] += 1
        }
        return counts.max { $0.value < $1.value }.flatMap { BindingAction(rawValue: $0.key) }
    }
}

// MARK: - Shared formatting

nonisolated extension ClassSignature {
    /// "Kᵢ 2.5 nM" / "EC₅₀ 22 µM" — nM below 1000, µM above, matching the receptor rows.
    static func concentrationText(_ value: Double, basis: SignatureBasis) -> String {
        "\(basis.symbol) \(shortNanomolar(value))"
    }

    static func shortNanomolar(_ value: Double) -> String {
        if value >= 1_000_000 {
            return "\((value / 1_000_000).formatted(.number.precision(.fractionLength(0 ... 1)))) mM"
        }
        if value >= 1_000 {
            return "\((value / 1_000).formatted(.number.precision(.fractionLength(0 ... 1)))) µM"
        }
        return "\(value.formatted(.number.precision(.fractionLength(0 ... 2)))) nM"
    }
}

nonisolated extension SignatureBasis {
    /// The measurement's symbol, for a value readout (`Kᵢ 2.5 nM`).
    var symbol: String {
        switch self {
        case .ki: "Kᵢ"
        case .ec50: "EC₅₀"
        case .ic50: "IC₅₀"
        case .tau: "τ"
        case .intrinsicActivity, .emax: "%"
        }
    }
}

// MARK: - Models

/// Where a rendering's numbers came from, so the axis line can print its basis. Every signature
/// carries one; an axis is never allowed to be silent about what it measures.
nonisolated struct SignatureProvenance: Hashable, Sendable {
    let basis: SignatureBasis
    /// True when a curator declared the uniform panel (`comparable_set`) rather than the gate having
    /// inferred it from a shared citation.
    let isDeclaredPanel: Bool
    /// `nil` when the group mixes species.
    let species: String?
    let referenceAgonist: String?
    let citationURL: URL?
}

/// The partial→full efficacy axis.
nonisolated struct EfficacyAxisModel: Sendable {
    nonisolated struct Mark: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        /// Position on the axis: percent of the reference agonist (τ is stored as its ratio ×100).
        let percent: Double
        let valueText: String
        let isFocus: Bool
        /// Solid when this compound was measured in the same experiment as the focus; hollow when it
        /// is the same measure from a different study.
        let isGated: Bool
    }

    let focus: Mark
    let marks: [Mark]
    let headline: LocalizedStringResource?
    let provenance: SignatureProvenance
    /// True when at least one peer shares the focus's experiment. False means the whole ladder ranks
    /// across studies, and the caption has to say so.
    let isGated: Bool

    /// A single mark is not a ladder — §C's rule: degrade to a static readout rather than draw an
    /// axis with one tick on it.
    var isStaticReadout: Bool {
        marks.count < 2
    }

    /// Axis maximum: the reference agonist anchors 100 %, but a super-agonist (methadone at 116 % of
    /// DAMGO) must not fall off the end.
    var axisMaximum: Double {
        max(100, (marks.map(\.percent).max() ?? 100) * 1.04)
    }
}

/// The two-target balance arc (5-HT2A ↔ 5-HT1A).
nonisolated struct TargetBalanceModel: Sendable {
    nonisolated struct Tick: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        /// 5-HT2A Kᵢ ÷ 5-HT1A Kᵢ. Above 1 = 5-HT1A-selective.
        let ratio: Double
        let isFocus: Bool
        /// Solid when this tick's pair of Kᵢ values comes from the focus's own
        /// comparable group (same study or declared panel); hollow when it is
        /// cross-study context. The focus tick itself only exists when gated —
        /// an ungated focus renders as a withheld card, never a tick.
        let isGated: Bool

        /// 0 (fully 5-HT2A) … 1 (fully 5-HT1A) — two decades either side of parity.
        var position: Double {
            min(0.97, max(0.03, 0.5 + log10(max(ratio, 1e-6)) / 4))
        }
    }

    /// `nil` when no single study measured both receptors — the card then shows
    /// ``valueText`` alone and prints ``withheldReason``.
    let focus: Tick?
    let ticks: [Tick]
    let ratioText: String
    let valueText: String
    let provenance: SignatureProvenance?
    let withheldReason: LocalizedStringResource?

    var leadingPole: String {
        SignatureTarget.serotonin2A.label
    }
    var trailingPole: String {
        SignatureTarget.serotonin1A.label
    }
}

/// The SERT / DAT / NET triangle, one triple per gated study.
///
/// Not `Hashable`: `withheldReason` is a `LocalizedStringResource`, which isn't. Nothing hashes the
/// whole model — the views key off `Triple.id` — and `TargetBalanceModel` carries the same field
/// under the same conformances.
nonisolated struct TransporterTernaryModel: Sendable {
    nonisolated struct Shares: Hashable, Sendable {
        let sert: Double
        let dat: Double
        let net: Double

        /// Potency share: the normalized reciprocal of each half-max concentration.
        static func potencyShare(sert: Double, dat: Double, net: Double) -> Shares {
            let inverses = (s: 1 / sert, d: 1 / dat, n: 1 / net)
            let sum = inverses.s + inverses.d + inverses.n
            guard sum > 0 else { return Shares(sert: 1 / 3, dat: 1 / 3, net: 1 / 3) }
            return Shares(sert: inverses.s / sum, dat: inverses.d / sum, net: inverses.n / sum)
        }
    }

    nonisolated struct Values: Hashable, Sendable {
        let sert: Double
        let dat: Double
        let net: Double
    }

    nonisolated struct Point: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let shares: Shares
        let values: Values
        let isFocus: Bool
        /// Solid when measured in the focus's own experiment; hollow context otherwise.
        let isGated: Bool
        /// Wikipedia-pageview popularity [0,1] — decides which context dots get named.
        let popularity: Double
    }

    nonisolated struct Triple: Identifiable, Hashable, Sendable {
        let id: String
        let focus: Point
        /// Compounds measured beside the focus in the same experiment.
        let peers: [Point]
        /// The rest of the library on the same basis — each its own study, drawn faint and unlabeled.
        let ghosts: [Point]
        let provenance: SignatureProvenance
        let action: BindingAction?
    }

    let triples: [Triple]
    /// Set when the compound HAS transporter rows but none of them form a gated
    /// SERT+DAT+NET triple on one basis, so `triples` is empty by decision rather
    /// than by absence. The card prints this instead of vanishing — a section that
    /// disappears teaches the reader nothing, and 46 of the 82 transporter-class
    /// compounds with receptor data land here. `nil` whenever `triples` is populated.
    let withheldReason: LocalizedStringResource?
}
