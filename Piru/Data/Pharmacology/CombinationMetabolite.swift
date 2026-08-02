import Foundation

/// **Combination-generated active species** — the rare case where two co-ingested drugs don't merely
/// add but *react* to form a third active compound with its own pharmacology and (often) worse
/// toxicity (`Specs/pharmacology-axis-meta-plan.md`, Stage 4d). This is inexpressible in both the
/// additive combined-depression index *and* the per-substance active-metabolite path, because the new
/// species is a property of the **pair**, not of either drug alone.
///
/// The canonical (and essentially only well-evidenced) case is **cocaethylene** from cocaine + ethanol.
///
/// ## Readout-only (v1), faithful to the evidence
/// The Foundation-C evidence run (`cocaethylene-evidence.json`, 2026-06-22) graded the parameters and
/// found **no shippable human Vd or clearance** for cocaethylene — only canine numbers, below the human
/// floor. Without a Vd the species cannot get its own absolute-exposure PK curve, so v1 does **not**
/// simulate it through the occupancy pipeline (that waits on a human Vd). Instead this is an
/// evidence-anchored **readout**: when both precursors are onboard, surface that the metabolite forms,
/// what it does (longer-lived active stimulant), and the real harm-reduction signal (extra cardiac and
/// hepatic strain) — while explicitly **rejecting the laundered "18–25× sudden death" myth** the same
/// run debunked (it traces to a single 1997 narrative review with no primary cohort).
///
/// Formation is **gated on the precursors co-occurring** — the temporal-overlap signal the interaction
/// engine already computes (`activeEntries`) — because cocaethylene only forms while ethanol is present
/// at the time cocaine is metabolized (CES1/hCE1 transesterification).
nonisolated enum CombinationMetabolite {
    /// A curated pair-generated active species.
    struct Definition: Identifiable {
        let id: String
        let displayName: LocalizedStringResource
        /// One matcher set **per precursor**; every precursor must be onboard for the species to form.
        /// Matchers are lowercased names/aliases, matched against the onboard substance names.
        let precursors: [[String]]
        let confidence: ConfidenceTier
        /// What it is and how it forms (mechanism + the overlap requirement), for non-experts.
        let formationNote: LocalizedStringResource
        /// The harm-reduction caution — the real signal, with the myth explicitly defused.
        let cautionNote: LocalizedStringResource
    }

    /// Cocaethylene — cocaine + ethanol → a longer-lived, DAT-dominant active stimulant metabolite.
    /// Parameters and copy anchored to the gate-clean evidence run (faithful over comprehensive).
    static let cocaethylene = Definition(
        id: "cocaethylene",
        displayName: "Cocaethylene",
        precursors: [
            ["cocaine", "crack", "crack cocaine", "cocaine hydrochloride", "coke", "benzoylmethylecgonine"],
            ["ethanol", "alcohol", "ethyl alcohol"],
        ],
        confidence: .medium,
        formationNote: "Cocaine and alcohol together form cocaethylene — an active stimulant your body makes only while both are present. It lasts noticeably longer than cocaine, so the stimulant effect (and its strain) is drawn out.",
        cautionNote: "Cocaethylene adds extra strain on the heart and liver beyond cocaine alone, so this combination is harder on your body. (The widely-repeated \"18–25× sudden death\" figure is not supported by the evidence — but the added cardiac and liver strain is real, so it's worth avoiding the mix.)",
    )

    /// Ethylphenidate — methylphenidate + ethanol → a longer-lived, more DAT-selective active stimulant.
    /// The exact structural analogue of cocaethylene: carboxylesterase (CES1) transesterifies the methyl
    /// ester to an ethyl ester **only while ethanol is present**, so like cocaethylene it is a property of
    /// the pair. Calmer confidence than cocaethylene — the human PK is thinner — but the formation chemistry
    /// and the "outlasts the parent" shape are well attested.
    static let ethylphenidate = Definition(
        id: "ethylphenidate",
        displayName: "Ethylphenidate",
        precursors: [
            ["methylphenidate", "ritalin", "concerta", "mph", "dexmethylphenidate", "focalin", "d-methylphenidate"],
            ["ethanol", "alcohol", "ethyl alcohol"],
        ],
        confidence: .low,
        formationNote: "Methylphenidate and alcohol together form ethylphenidate — an active stimulant your body makes only while both are present. It leans more on dopamine and lingers a little longer than methylphenidate, so the stimulant effect is drawn out.",
        cautionNote: "The mix adds cardiovascular strain beyond either alone, and the ethylphenidate it forms outlasts the methylphenidate itself, so the load on your heart is stretched out rather than added up.",
    )

    static let catalog: [Definition] = [cocaethylene, ethylphenidate]

    /// Metabolite names that form **only** when a second drug is co-present. They must never appear as an
    /// unconditional "Also Active" metabolite on the parent's own page — that would claim a species the body
    /// makes only in combination is always present. They are surfaced through ``formed(among:)`` instead,
    /// gated on co-occurrence, where the caution can name the pair. Matched case-insensitively against a
    /// metabolism row's `metabolite_name`.
    static let conditionalMetaboliteNames: Set<String> = ["cocaethylene", "ethylphenidate"]

    /// Whether a metabolite forms only in combination, so the per-substance active-metabolite fold must skip it.
    static func isConditional(_ metaboliteName: String) -> Bool {
        conditionalMetaboliteNames.contains(metaboliteName.lowercased().trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Detection

    /// A combination metabolite that forms among a set of onboard substances.
    struct Formation: Identifiable {
        let definition: Definition
        var id: String {
            definition.id
        }
        var displayName: LocalizedStringResource {
            definition.displayName
        }
        var confidence: ConfidenceTier {
            definition.confidence
        }
        var formationNote: LocalizedStringResource {
            definition.formationNote
        }
        var cautionNote: LocalizedStringResource {
            definition.cautionNote
        }
    }

    /// Pure: which combination metabolites form among `substances` (every precursor present). Gated on
    /// co-presence; the caller passes a set already filtered to what's concurrently onboard (the
    /// temporal-overlap signal) for the dose-entry path, or the hypothetical selection for the checker.
    static func formed(among substances: [String]) -> [Formation] {
        let onboard = Set(substances.map { $0.lowercased().trimmingCharacters(in: .whitespaces) })
        return catalog.compactMap { def in
            let allPresent = def.precursors.allSatisfy { matchers in
                matchers.contains { onboard.contains($0) }
            }
            return allPresent ? Formation(definition: def) : nil
        }
    }

    // MARK: - Temporal gate

    /// One substance and the window it is actually onboard for — the unit the
    /// dose-entry path gates on. The interaction checker asks a hypothetical
    /// ("what if I took these together"), so it has no windows and uses
    /// ``formed(among:)`` directly; a *logged* dose has real timestamps, and two
    /// doses eight hours apart are not a combination.
    struct Onboard: Hashable, Sendable {
        let name: String
        let interval: DateInterval

        init(name: String, interval: DateInterval) {
            self.name = name
            self.interval = interval
        }
    }

    /// Which combination metabolites form *around one dose* — the surface an entry
    /// screen needs.
    ///
    /// Two conditions beyond ``formed(among:)``, both of which keep the readout
    /// from over-claiming:
    ///
    /// - **`focus` must itself be a precursor.** Otherwise a session containing
    ///   cocaine and alcohol would print a cocaethylene note on the ibuprofen
    ///   logged alongside them.
    /// - **Windows must overlap.** Formation is transesterification *while the
    ///   co-drug is present*, so a peer whose activity window has closed before
    ///   this dose was taken contributes nothing. `DateInterval.intersects`
    ///   includes touching endpoints, which is the right boundary: a dose taken
    ///   exactly as the previous one clears still meets it.
    static func formed(overlapping focus: Onboard, with peers: [Onboard]) -> [Formation] {
        let concurrent = peers.filter { $0.interval.intersects(focus.interval) }
        let focusKey = focus.name.lowercased().trimmingCharacters(in: .whitespaces)
        return formed(among: [focus.name] + concurrent.map(\.name)).filter { formation in
            formation.definition.precursors.contains { $0.contains(focusKey) }
        }
    }
}
