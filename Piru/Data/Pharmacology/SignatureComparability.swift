import Foundation

/// The **comparability gate** for the class signatures (the ternary, the efficacy axis, the
/// 5-HT2A↔5-HT1A balance).
///
/// A set of binding / functional rows may be plotted on one axis only when both hold:
///
/// 1. **One experiment.** They share a non-null `comparable_set`, *or* — when no `comparable_set`
///    exists — a non-null `citation_id`. A declared `comparable_set` always wins: it is the
///    curator's statement of which rows form a uniform panel, so a row carrying one is never
///    merged with a row that doesn't merely because a citation matches.
/// 2. **One basis.** Every leg reports the *same measurement*: all `ki_nm`, or all `ec50_nm`, or
///    all `ic50_nm` — never mixed. Likewise on the efficacy side: all τ, or all intrinsic
///    activity, or all Emax.
///
/// The basis half is not optional and not cosmetic. MDMA rendered as a "95 % noradrenergic" drug
/// off exactly one mixed leg — a radioligand-binding Kᵢ (hDAT 22 µM) plotted against a synaptosomal
/// release EC₅₀ (hNET 77 nM) — and Eshleman 2013 reports binding Kᵢ and uptake IC₅₀ side by side for
/// the same compounds diverging up to ~150×. The efficacy axis carries the same hazard from the
/// other side: morphine is 94 % of DAMGO by Emax but τ 0.18, so a τ value and an Emax value on one
/// axis renders every clinical opioid a full agonist.
///
/// When nothing passes, the signature must degrade **and say why on screen** — never silently plot
/// mixed rows.
nonisolated enum SignatureComparability {
    /// Partition legs into every gate-passing group. One leg can appear in several groups when it
    /// reports more than one measurement (Methoxetamine's MK-801-site row carries both a Kᵢ and an
    /// IC₅₀); those are genuinely separate comparisons and are kept separate.
    ///
    /// Legs with neither a `comparable_set` nor a `citation_id` are dropped: an uncited value was
    /// never established as part of any panel, which is *not* the same as "comparable to
    /// everything".
    static func partition(_ legs: [SignatureLeg]) -> [ComparableGroup] {
        var buckets: [BucketKey: [SignatureLeg]] = [:]
        var order: [BucketKey] = []
        for leg in legs {
            guard let key = leg.comparabilityKey else { continue }
            for basis in SignatureBasis.allCases where basis.value(in: leg) != nil {
                let bucket = BucketKey(key: key, basis: basis)
                if buckets[bucket] == nil { order.append(bucket) }
                buckets[bucket, default: []].append(leg)
            }
        }
        return order.compactMap { bucket in
            guard let rows = buckets[bucket] else { return nil }
            return ComparableGroup(key: bucket.key, basis: bucket.basis, legs: rows)
        }
    }

    /// Does this exact set of legs form **one** comparable measurement?
    ///
    /// Returns the group when every leg shares one comparability key and at least one basis is
    /// populated on all of them; `nil` when the keys disagree or the legs mix bases. When several
    /// bases are shared the strongest is chosen (Kᵢ before EC₅₀ before IC₅₀; τ before intrinsic
    /// activity before Emax) — τ first because it is intrinsic *efficacy* and system-independent,
    /// where intrinsic activity is inflated by receptor reserve.
    static func admits(_ legs: [SignatureLeg]) -> ComparableGroup? {
        guard let first = legs.first, let key = first.comparabilityKey else { return nil }
        guard legs.allSatisfy({ $0.comparabilityKey == key }) else { return nil }
        let basis = SignatureBasis.allCases.first { candidate in
            legs.allSatisfy { candidate.value(in: $0) != nil }
        }
        guard let basis else { return nil }
        return ComparableGroup(key: key, basis: basis, legs: legs)
    }

    /// One (experiment × basis) bucket — the unit the gate partitions into.
    private struct BucketKey: Hashable {
        let key: ComparabilityKey
        let basis: SignatureBasis
    }
}

// MARK: - Leg

/// One measured row, normalized out of `bindings` or `functional_assays`, ready for the gate.
///
/// Deliberately a plain value type with no store dependency so the gate is testable without the
/// bundled database.
nonisolated struct SignatureLeg: Identifiable, Hashable, Sendable {
    /// Table-namespaced row id (`"b:412"` / `"f:37"`) — `bindings` and `functional_assays` number
    /// their rows independently, so a bare integer would collide across the union.
    let id: String
    let substanceName: String
    let target: SignatureTarget
    /// Raw `action` string (`"releasingAgent"`, `"partialAgonist"`, …); `nil` for functional rows,
    /// which carry a readout rather than an action.
    let action: String?
    let kiNm: Double?
    let ec50Nm: Double?
    let ic50Nm: Double?
    /// Black–Leff operational efficacy as a ratio to the reference agonist in the same experiment.
    let relativeTau: Double?
    let intrinsicActivityPct: Double?
    let emaxPct: Double?
    let comparableSet: String?
    let citationID: Int64?
    let species: String?
    let referenceAgonist: String?
    let doi: String?
    let pmid: Int?
    let year: Int?
    /// Wikipedia-pageview popularity [0,1] for the leg's substance. Purely a
    /// presentation signal: it decides which context points on a plot are worth
    /// naming, never which are comparable.
    let popularity: Double

    init(
        id: String,
        substanceName: String,
        target: SignatureTarget,
        action: String? = nil,
        kiNm: Double? = nil,
        ec50Nm: Double? = nil,
        ic50Nm: Double? = nil,
        relativeTau: Double? = nil,
        intrinsicActivityPct: Double? = nil,
        emaxPct: Double? = nil,
        comparableSet: String? = nil,
        citationID: Int64? = nil,
        species: String? = nil,
        referenceAgonist: String? = nil,
        doi: String? = nil,
        pmid: Int? = nil,
        year: Int? = nil,
        popularity: Double = 0,
    ) {
        self.id = id
        self.substanceName = substanceName
        self.target = target
        self.action = action
        self.kiNm = kiNm
        self.ec50Nm = ec50Nm
        self.ic50Nm = ic50Nm
        self.relativeTau = relativeTau
        self.intrinsicActivityPct = intrinsicActivityPct
        self.emaxPct = emaxPct
        self.comparableSet = comparableSet
        self.citationID = citationID
        self.species = species
        self.referenceAgonist = referenceAgonist
        self.doi = doi
        self.pmid = pmid
        self.year = year
        self.popularity = popularity
    }

    /// Which experiment this row belongs to. A declared `comparable_set` **wins** over the citation:
    /// when a curator has tagged the uniform panel, rows outside it were deliberately left out, so a
    /// shared paper is not enough to re-admit them. `nil` for a row with neither — never plottable.
    var comparabilityKey: ComparabilityKey? {
        if let comparableSet, !comparableSet.isEmpty { return .panel(comparableSet) }
        if let citationID { return .citation(citationID) }
        return nil
    }

    /// Is this row an efficacy measurement of *any* kind (τ, intrinsic activity, or Emax)?
    var hasEfficacyValue: Bool {
        relativeTau != nil || intrinsicActivityPct != nil || emaxPct != nil
    }

    /// A bare **100.0 %** with no declared panel is a *documented efficacy class*, not a fitted
    /// measurement — the convention a paper uses to say "full agonist" about a compound it did not
    /// characterize further. About twenty nitazene and fentanyl analogue rows are exactly this shape.
    ///
    /// They may be drawn (hollow), but they never make a ladder comparable and never render as solid
    /// full-activation ticks: a flat row of identical 100 % marks is precisely the reading that turns
    /// every opioid into a full agonist. A τ row is never class-only — τ has to be fitted.
    var isDocumentedClassOnly: Bool {
        guard comparableSet == nil, relativeTau == nil else { return false }
        return intrinsicActivityPct == 100 || (intrinsicActivityPct == nil && emaxPct == 100)
    }

    /// The reference agonist folded to a comparison key — `"CP-55,940"` and `"CP55,940"` are the
    /// same compound, and `"JWH-018 (self, = 100% by definition…)"` is still JWH-018.
    var referenceAgonistKey: String? {
        guard let referenceAgonist else { return nil }
        let head = referenceAgonist.split(separator: "(").first.map(String.init) ?? referenceAgonist
        let folded = head.lowercased().filter { $0.isLetter || $0.isNumber }
        return folded.isEmpty ? nil : folded
    }

    var isHuman: Bool {
        species?.lowercased().contains("human") ?? false
    }
}

// MARK: - Key, basis, group

/// Which experiment a row belongs to.
nonisolated enum ComparabilityKey: Hashable, Sendable {
    /// A curated uniform panel (`bindings.comparable_set`) — the strong form.
    case panel(String)
    /// One publication (`bindings.citation_id`) — the fallback when no panel is declared. Weaker: a
    /// paper can report several incomparable tables.
    case citation(Int64)

    /// Whether the group's comparability was *declared* by a curator rather than inferred from a
    /// shared citation. Surfaced in the caption so the reader can tell the two apart.
    var isDeclaredPanel: Bool {
        if case .panel = self { return true }
        return false
    }
}

/// The measurement a comparison is built on. Two legs may only share an axis when they share one of
/// these — never across.
nonisolated enum SignatureBasis: String, CaseIterable, Sendable {
    /// Equilibrium binding affinity.
    case ki
    /// Functional half-maximal *effect* (a releaser's substrate EC₅₀, an agonist's activation EC₅₀).
    case ec50
    /// Half-maximal *inhibition* (uptake blockade).
    case ic50
    /// Black–Leff operational efficacy τ, as a ratio to the reference agonist. Intrinsic efficacy:
    /// system-independent, and the only honest efficacy ranking.
    case tau
    /// Intrinsic activity as a percentage of the reference agonist. Receptor reserve inflates it.
    case intrinsicActivity
    /// Maximal effect as a percentage of the reference agonist. Same caveat as intrinsic activity.
    case emax

    func value(in leg: SignatureLeg) -> Double? {
        switch self {
        case .ki: leg.kiNm
        case .ec50: leg.ec50Nm
        case .ic50: leg.ic50Nm
        case .tau: leg.relativeTau
        case .intrinsicActivity: leg.intrinsicActivityPct
        case .emax: leg.emaxPct
        }
    }

    /// Is this a potency measure (lower = stronger) rather than an efficacy measure?
    var isPotency: Bool {
        switch self {
        case .ki, .ec50, .ic50: true
        case .tau, .intrinsicActivity, .emax: false
        }
    }

    /// The axis-line label. Every rendering prints this; the axis is never allowed to be silent
    /// about what it is measuring.
    var axisLabel: LocalizedStringResource {
        switch self {
        case .ki: "binding Kᵢ"
        case .ec50: "functional EC₅₀"
        case .ic50: "inhibition IC₅₀"
        case .tau: "efficacy τ"
        case .intrinsicActivity: "intrinsic activity"
        case .emax: "Emax"
        }
    }
}

/// A set of legs that passed the gate: one experiment, one basis.
nonisolated struct ComparableGroup: Identifiable, Hashable, Sendable {
    let key: ComparabilityKey
    let basis: SignatureBasis
    let legs: [SignatureLeg]

    var id: String {
        switch key {
        case let .panel(name): "panel:\(name):\(basis.rawValue)"
        case let .citation(cid): "cite:\(cid):\(basis.rawValue)"
        }
    }

    /// Distinct substances measured in this group. A ladder needs at least two of them; below that
    /// there is nothing to rank and the rendering degrades to a static readout.
    var substanceNames: [String] {
        var seen = Set<String>()
        return legs.compactMap { seen.insert($0.substanceName).inserted ? $0.substanceName : nil }
    }

    /// The best leg for one substance × target in this group: prefer human, then the tighter value.
    func leg(substance: String, target: SignatureTarget) -> SignatureLeg? {
        legs
            .filter { $0.substanceName == substance && $0.target == target }
            .min { lhs, rhs in
                if lhs.isDocumentedClassOnly != rhs.isDocumentedClassOnly { return rhs.isDocumentedClassOnly }
                if lhs.isHuman != rhs.isHuman { return lhs.isHuman }
                let lv = basis.value(in: lhs) ?? .greatestFiniteMagnitude
                let rv = basis.value(in: rhs) ?? .greatestFiniteMagnitude
                return basis.isPotency ? lv < rv : lv > rv
            }
    }

    /// Every leg in the group carries the same species, or the group is mixed.
    var species: String? {
        let all = Set(legs.compactMap(\.species))
        return all.count == 1 ? all.first : nil
    }

    var isHuman: Bool {
        legs.allSatisfy(\.isHuman)
    }

    /// The group's shared reference agonist, when it has one.
    var referenceAgonist: String? {
        let keys = Set(legs.compactMap(\.referenceAgonistKey))
        guard keys.count == 1 else { return nil }
        return legs.compactMap(\.referenceAgonist)
            .map { $0.split(separator: "(").first.map(String.init) ?? $0 }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first
    }

    var year: Int? {
        legs.compactMap(\.year).max()
    }

    /// The group's citation deep link, preferring PMID over DOI. `nil` for a free-text or broken
    /// citation — the caption then renders as non-tappable text rather than a dead link.
    var citationURL: URL? {
        for leg in legs {
            if let pmid = leg.pmid { return URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/") }
            if let doi = leg.doi, !doi.isEmpty { return URL(string: "https://doi.org/\(doi)") }
        }
        return nil
    }
}

// MARK: - Targets

/// The receptor / transporter targets the signatures plot, normalized out of the free-text
/// `bindings.target` column (`"MOR (μ1)"`, `"CB1 (human)"`, `"μ-opioid receptor (human, hMOR)"` all
/// name one target; `"MOR / DOR / KOR / NOP"` names four and is deliberately not matched).
nonisolated enum SignatureTarget: String, Hashable, Sendable, CaseIterable {
    case sert = "SERT"
    case dat = "DAT"
    case net = "NET"
    case serotonin2A = "5-HT2A"
    case serotonin1A = "5-HT1A"
    case mu = "MOR"
    case cannabinoid1 = "CB1"
    case nmda = "NMDA"

    /// Display name for the axis vertices and pole labels. Receptor names are proper nouns and are
    /// never localized.
    var label: String {
        rawValue
    }

    /// Normalize one raw `target` string. A trailing parenthetical qualifier (`"(human)"`,
    /// `"(MK-801 site, racemate)"`) is stripped; anything else must match exactly, so a multi-target
    /// row never masquerades as a single leg.
    static func normalized(_ raw: String) -> SignatureTarget? {
        var base = raw.trimmingCharacters(in: .whitespaces)
        if let paren = base.firstIndex(of: "(") {
            base = String(base[base.startIndex ..< paren]).trimmingCharacters(in: .whitespaces)
        }
        let folded = base.lowercased()
        switch folded {
        case "sert", "5-htt": return .sert
        case "dat": return .dat
        case "net": return .net
        case "5-ht2a": return .serotonin2A
        case "5-ht1a": return .serotonin1A
        case "cb1": return .cannabinoid1
        default: break
        }
        if folded == "mor" || folded.hasPrefix("μ-opioid") || folded.hasPrefix("mu-opioid") {
            return .mu
        }
        if folded.hasPrefix("nmda") { return .nmda }
        return nil
    }
}
