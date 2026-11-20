import SwiftData
import SwiftUI

/// Async-loaded detail data for ``SubstanceDetailView``, pulled off the SQLite
/// store in `.task` and swapped in reactively. Holding it in an `@Observable`
/// model (rather than a fistful of `@State` on the view) means each loaded field
/// invalidates only the section that reads it — the receptor list appearing
/// doesn't re-run the whole screen — and the loading logic lives next to the
/// data instead of in the view body.
@MainActor
@Observable
final class SubstanceDetailModel {
    private let store = SubstanceStore.shared

    /// Per-field source attribution (which database supplied category, half-life,
    /// mechanism, and per-route dose/duration). Fetched for every tier.
    var provenance: SubstanceStore.SubstanceProvenance?

    var wikiTimings: [WikiTimingRecord] = []

    /// Measured receptor binding rows: they feed both the "Receptor Literature"
    /// list and the unified Pharmacology card's class hero.
    var literatureBindings: [BindingHit] = []

    /// The receptor rows worth showing, derived once per `literatureBindings`
    /// assignment (the filter/dedup/sort pipeline is too heavy to re-run per
    /// body pass). See ``ReceptorLiterature/visibleBindings(from:)`` for the relevance rules.
    var visibleLiteratureBindings: [BindingHit] = []

    /// Per-route pharmacokinetics (bioavailability / tmax / half-life), one row
    /// per route: the table holds a row per *study*, which rendered as the same
    /// card several times over. See ``SubstanceStore/displayRows(_:)``.
    var pkRoutes: [SubstanceStore.PKDisplayRow] = []

    /// CYP/enzyme clearance pathways and their metabolites.
    var metabolismRows: [SubstanceStore.MetabolismHit] = []

    /// Grapefruit / smoking / self-edge metabolic-modulation education.
    var metabolicEducation: [MetabolicModulation.Effect] = []

    /// Measured PK interactions from the literature: what a named drug or drug
    /// class does to this substance's exposure. Sourced facts, not warnings.
    var pkInteractions: [SubstanceStore.PKInteractionHit] = []

    /// Things the compound acts on that are not why anyone takes it — the hERG
    /// / bladder / taste-receptor rows. One per target, most-consequential first.
    var offTargets: [SubstanceStore.OffTargetHit] = []

    /// Genes whose variants change what this substance does — the enzymes that
    /// clear it, and the receptors and transporters it acts on. One row per
    /// gene.
    var pharmacogenetics: [SubstanceStore.PharmacogeneticHit] = []

    /// Pathway bias, receptor complexes and in-vivo imaging — the evidence about
    /// a target that is not an affinity number.
    var targetEvidence: [SubstanceStore.TargetEvidence] = []

    /// What happens after the receptor binds.
    var signalingCascade: SubstanceStore.SignallingCascade?

    /// The plasma concentrations at which named effects appear — what makes the
    /// PK curve readable rather than merely shaped.
    var concentrationThresholds: [SubstanceStore.ConcentrationThreshold] = []

    /// The pharmacological family this substance belongs to, and what its
    /// members share. Carries most of what is known about the long tail.
    var classContext: SubstanceStore.ClassContext?

    /// Which source supplied which field, for the Sources ledger. Loaded here
    /// rather than by the section itself: the ledger folds now, and a `.task`
    /// inside a collapsed disclosure doesn't run until the user opens it — so
    /// the layout's presence gate would be deciding whether to show the section
    /// from data that only arrives once the section is already on screen.
    var sourceContributions: SubstanceStore.SourceContributions = .empty

    /// Metabolites doing some of the work — the "Also Active" surface. Folded
    /// from ``metabolismRows`` by metabolite (the table groups by enzyme), and
    /// filtered to the ones that can actually say something, so the section is
    /// absent for the ~90% of the library with nothing to report.
    var activeMetabolites: [ActiveMetabolite] = []

    /// Set when this substance is a meaningful CYP3A4 inducer (modafinil,
    /// rifampicin…) — it can lower hormonal-contraception levels.
    var contraceptionCaution: MetabolicModulation.Modulator?

    /// CYP2D6 metabolism classification, derived from ``metabolismRows``. Non-nil when the
    /// substance has at least one metabolism row where CYP2D6 is a primary pathway.
    var cyp2d6Info: CYP2D6Info?

    /// DA↔5-HT character / releaser-blocker card, derived from the bindings.
    var monoamineProfile: MonoamineProfile?

    /// The heart-valve warning — the substance's own 5-HT2B bindings or its
    /// class's declaration. Loaded at every tier, like a boxed warning.
    var valvularWarning: ValvularWarning?

    /// The class signature for the Pharmacology card — the gated comparison that says where this
    /// compound sits among the ones it is actually comparable to (efficacy axis / 5-HT balance /
    /// transporter ternary), or the stated absence when nothing passed the gate. `nil` for classes
    /// with no signature and for compounds with no rows of the kind at all.
    var classSignature: ClassSignature?

    /// The substance's 2D skeleton, drawn faint behind the whole screen.
    var moleculeStructure: MoleculeStructure?

    /// O(n) dose-history aggregates for the history card.
    var historyStats = HistoryStats()

    /// Ladder counts per route for the substance last asked about, filled on
    /// first read: each count is a SQL query, and the dose card reads it on
    /// every route, salt or brand pick.
    @ObservationIgnored private var ladderSourceCounts: (substanceName: String, byRoute: [RouteOfAdministration: Int])?

    /// The merged Sources ledger and the inputs it was built from. Rebuilt
    /// only when one of those inputs changes.
    @ObservationIgnored private var sourceLinksCache: (key: SourceLinksKey, links: [DetailSourceLink])?

    struct HistoryStats: Equatable {
        var minDose: Double = 0
        var maxDose: Double = 0
        var mostCommon: Double = 0
        /// The unit the three are read in — the newest measured dose's.
        var unit: String?
    }

    /// Resolve every store-backed field for the substance at the current
    /// disclosure tier. Each query is skipped for tiers that don't show its
    /// surface.
    func load(substanceName: String, category: SubstanceCategory, policy: DisclosurePolicy) {
        // Always fetch provenance — per-field source attribution is shown to
        // every tier so users can see where each fact came from.
        provenance = store.provenance(forSubstanceName: substanceName)
        wikiTimings = store.wikiTimings(forSubstanceName: substanceName)

        moleculeStructure = store.moleculeStructure(forSubstanceName: substanceName)

        // Ungated by tier. A row here is a consequence ("ulcerative cystitis in
        // chronic high-dose users"), not an affinity table, and tiering in this
        // app governs density rather than access — the card ships folded at
        // every tier instead.
        offTargets = store.offTargets(forSubstanceName: substanceName)
        pharmacogenetics = store.pharmacogenetics(forSubstanceName: substanceName)
        targetEvidence = store.targetEvidence(forSubstanceName: substanceName)
        signalingCascade = store.signallingCascade(forSubstanceName: substanceName)
        concentrationThresholds = store.concentrationThresholds(forSubstanceName: substanceName)
        classContext = store.classContext(forSubstanceName: substanceName)
        sourceContributions = store.sourceContributions(forSubstanceName: substanceName)

        // Contraceptive-efficacy caution — a CYP3A4 inducer (modafinil,
        // rifampicin…) can lower hormonal-contraception levels. Ungated like a
        // boxed warning: a safety fact for every tier.
        contraceptionCaution = MetabolicModulation.contraceptiveEfficacyCaution(
            forSubstance: substanceName, in: store.enzymeModulators(),
        )
        valvularWarning = SubstanceLibrary.valvularWarning(for: substanceName)

        // Binding rows feed two surfaces, the "Receptor Literature" list and the
        // "Monoamine Profile" card, so fetch once when either is shown.
        if policy.showsMechanism || policy.showsReceptorLiterature {
            let binds = store.bindings(forSubstanceName: substanceName)
            monoamineProfile = MonoamineProfile.from(
                bindings: binds,
                isSoldAsMDMA: store.hasFlag(PharmacologyParameters.Flag.missoldAsMDMA, forSubstanceName: substanceName),
            )
            literatureBindings = binds
            visibleLiteratureBindings = ReceptorLiterature.visibleBindings(from: binds)
        } else {
            monoamineProfile = nil
            literatureBindings = []
            visibleLiteratureBindings = []
        }

        // The class signature is a *comparison*, so unlike everything else here it reads the whole
        // family's rows rather than this substance's. Only the mechanism audience sees it.
        //
        // Resolved through ``ActiveIngredient`` like the bindings above, and for a sharper reason:
        // the axis marks its focus by NAME. Left unresolved, cannabis would look for a "Cannabis"
        // leg among rows that are all filed under THC, find none, and drop the axis entirely on the
        // one page where "how far does this switch the receptor on" is the whole question.
        classSignature = policy.showsMechanism
            ? ClassSignature.family(for: category).flatMap { family in
                ClassSignature.resolve(
                    substanceName: ActiveIngredient.pharmacologyName(for: substanceName),
                    category: category,
                    legs: store.signatureLegs(family: family),
                )
            }
            : nil

        // Per-route PK and CYP metabolism.
        if policy.showsPharmacokinetics {
            pkRoutes = SubstanceStore.displayRows(store.pharmacokinetics(forSubstanceName: substanceName))
            metabolismRows = store.metabolism(forSubstanceName: substanceName)
            pkInteractions = store.pkInteractions(forSubstanceName: substanceName)
        } else {
            pkRoutes = []
            metabolismRows = []
            pkInteractions = []
        }

        // One metabolism fetch feeds "Also Active", the CYP2D6 note and the
        // grapefruit/smoking education.
        let rows = policy.showsPharmacokinetics ? metabolismRows : store.metabolism(forSubstanceName: substanceName)
        activeMetabolites = Self.foldActiveMetabolites(from: rows)
        cyp2d6Info = CYP2D6Info.from(metabolismRows: rows)
        metabolicEducation = policy.showsMechanism
            ? MetabolicModulation.educationalEffects(
                forSubstance: substanceName, metabolism: rows, catalog: store.enzymeModulators(),
            )
            : []
    }

    /// Group the metabolism rows by metabolite and keep the ones with something
    /// to say. Excretion rows (no metabolite) and inactive byproducts drop out
    /// here — an "Also Active" card for an inactive metabolite is a
    /// contradiction, and one that only reads "Active" is noise.
    static func foldActiveMetabolites(from rows: [SubstanceStore.MetabolismHit]) -> [ActiveMetabolite] {
        var order: [String] = []
        var byName: [String: [SubstanceStore.MetabolismHit]] = [:]
        for row in rows {
            guard row.metaboliteActive == true, let name = row.metaboliteName, !name.isEmpty else { continue }
            // "unchanged <parent>" is an excretion row wearing a metabolite
            // field — it names no new molecule. Mirrors `MetabolismRow`'s own
            // elimination detection.
            guard !name.lowercased().hasPrefix("unchanged") else { continue }
            // Combination-only species (cocaethylene, ethylphenidate) form solely
            // while a second drug is onboard, so they must not read as an
            // unconditional metabolite of the parent — they surface through
            // `CombinationMetabolite.formed(among:catalog:)`, gated on co-occurrence.
            guard row.conditionalCombinationID == nil else { continue }
            let key = name.lowercased()
            if byName[key] == nil { order.append(key) }
            byName[key, default: []].append(row)
        }
        return order
            .compactMap { ActiveMetabolite.from(rows: byName[$0] ?? []) }
            .filter(\.isWorthShowing)
    }

    /// Read in the newest measured dose's unit. An unknown dose, or one in a unit
    /// that can't be read in it (mL against mg), stays out — 1 g and 500 mg are
    /// 1 000 and 500 mg, never "500–1".
    func rebuildHistoryStats(from entries: [DoseEntry]) {
        let measured = entries.compactMap { entry in entry.quantity.map { (entry.unit, $0) } }
        guard let (unit, unitOf) = measured.first else {
            historyStats = HistoryStats()
            return
        }
        let amounts = measured.compactMap { $0.1.value(inUnitOf: unitOf) }
        var freq: [Double: Int] = [:]
        for a in amounts {
            freq[a, default: 0] += 1
        }
        historyStats = HistoryStats(
            minDose: amounts.min() ?? 0,
            maxDose: amounts.max() ?? 0,
            mostCommon: freq.max(by: { $0.value < $1.value })?.key ?? 0,
            unit: unit,
        )
    }

    /// The metabolites worth an "Also Active" card — the ones that outlive the
    /// dose. See ``ActiveMetabolite/earnsOwnSection(parentHalfLifeMinutes:parentDurationMinutes:)``;
    /// the rest stay in the Metabolism disclosure rather than being promoted to
    /// a headline that implies news.
    func durationChangingMetabolites(for substance: Substance) -> [ActiveMetabolite] {
        activeMetabolites.filter {
            $0.earnsOwnSection(
                parentHalfLifeMinutes: substance.halfLifeMinutes,
                parentDurationMinutes: substance.longestRouteDurationMinutes,
            )
        }
    }

    /// How many sources carry a dose ladder for `route`.
    func ladderSourceCount(substanceName: String, route: RouteOfAdministration) -> Int {
        var byRoute = ladderSourceCounts?.substanceName == substanceName ? ladderSourceCounts?.byRoute ?? [:] : [:]
        if let count = byRoute[route] { return count }
        let count = store.doseLadders(forSubstanceName: substanceName, route: route).count
        byRoute[route] = count
        ladderSourceCounts = (substanceName, byRoute)
        return count
    }

    /// The merged, de-duplicated Sources ledger for `substance`
    /// (``SubstanceSourceLinks/mergedLinks(for:contributions:)``), paired with
    /// the loaded ``sourceContributions``. Reading it observes the
    /// contributions and the user's source order, so the ledger follows both.
    func sourceLinks(for substance: Substance) -> [DetailSourceLink] {
        let key = SourceLinksKey(
            substance: substance, contributions: sourceContributions, sourceOrder: store.enabledSourceOrder,
        )
        if let cached = sourceLinksCache, cached.key == key { return cached.links }
        let links = SubstanceSourceLinks.mergedLinks(for: substance, contributions: sourceContributions)
        sourceLinksCache = (key, links)
        return links
    }

    /// Every input ``SubstanceSourceLinks/mergedLinks(for:contributions:)``
    /// reads, so a cached ledger is reused only while all of them hold.
    struct SourceLinksKey: Equatable {
        let name: String
        let sources: [String]
        let references: [Citation]
        let pageSlugs: [String?]
        let identifiers: [String?]
        let pubchemCID: Int?
        let contributions: SubstanceStore.SourceContributions
        let sourceOrder: [String]

        init(substance: Substance, contributions: SubstanceStore.SourceContributions, sourceOrder: [String]) {
            name = substance.name
            sources = substance.sources
            references = substance.references
            pageSlugs = [
                substance.drugCommunitySlug, substance.freeodwikiSlug, substance.dosewikiSlug,
                substance.psychonautwikiPage, substance.tripsitSlug,
            ]
            identifiers = [substance.formula, substance.cas, substance.inchikey, substance.smiles]
            pubchemCID = substance.pubchemCID
            self.contributions = contributions
            self.sourceOrder = sourceOrder
        }
    }

    // MARK: - Literature derivations

    /// The class-specific hero for the unified Pharmacology card (opioid / benzo
    /// / dissociative receptor panel). `nil` for monoamine and other classes,
    /// which fall back to the slider/target grid.
    func pharmacologyHero(category: SubstanceCategory) -> PharmacologyHero? {
        PharmacologyHero.resolve(category: category, bindings: visibleLiteratureBindings)
    }
}
