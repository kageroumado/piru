import Foundation
import Testing
@testable import Piru

/// Guards against the class of mechanism-of-action errors found in May 2026:
///   - a partial agonist (mitragynine) shown as a "full agonist"
///   - monoamine releasers (mephedrone, the MMC cathinones) shown as generic
///     "Modulator" despite having clear receptor data
///   - real DB binding data being discarded when no `mechanisms_summary` row
///     exists, falling through to the per-category generic template
@Suite("Mechanism of Action")
struct MechanismOfActionTests {
    // MARK: - Helpers

    private func binding(_ target: String, _ action: BindingAction, _ affinity: BindingAffinity = .primary) -> ReceptorBinding {
        ReceptorBinding(target: target, action: action, affinity: affinity)
    }

    private func moa(summary: String, bindings: [ReceptorBinding]) -> MechanismOfAction {
        MechanismOfAction(summary: summary, description: "", bindings: bindings)
    }

    // MARK: - Curated per-name entries are pharmacologically correct

    @Test
    @MainActor
    func `Cathinone transporter action comes from the DB, never a generic placeholder`() async {
        // The bug this guards: cathinones rendering as an undifferentiated "Modulator".
        // The claim used to live in a Swift class template that asserted DAT/NET/SERT for
        // every substituted cathinone; it was a restatement of the summary, so it is gone
        // and the measured rows carry it. A cathinone the literature never assayed now
        // shows no receptor list at all, which is the honest result.
        await SubstanceStore.shared.ensureAllLoaded()
        for name in ["Mephedrone", "Methylone", "MDPV", "a-PVP"] {
            guard let sub = SubstanceStore.shared.lookup(name) else {
                Issue.record("\(name) missing from bundled DB"); continue
            }
            let resolved = MechanismOfActionDatabase.resolvedMechanism(
                dbMechanism: sub.mechanismOfAction, substanceName: sub.name, category: sub.category,
            )
            let transporters = (resolved?.bindings ?? []).filter { ["DAT", "NET", "SERT"].contains($0.target) }
            #expect(!transporters.isEmpty, "\(name) has measured transporter rows and must show them")
            for t in transporters {
                #expect(
                    t.action == .releasingAgent || t.action == .reuptakeInhibitor,
                    "\(name) \(t.target) is \(t.action.rawValue) — the releaser/blocker split is the whole claim",
                )
            }
            // Narrow on purpose: a modulator row is fine in general — MDPV's σ1 is one, cited —
            // but a *transporter* reading "Modulator" is the original bug, an undifferentiated
            // label standing where the releaser/blocker distinction belongs.
            #expect(
                transporters.contains { $0.action == .modulator } == false,
                "\(name) shows a transporter as a generic Modulator",
            )
        }
    }

    @Test
    func `A class fallback never invents a receptor out of a category name`() {
        // Every category placeholder ("Various", "Pain pathways", "Microbial targets",
        // "Cardiovascular system") is gone: a system is not a target, and a dot beside
        // one claims a measurement that was never made. A substance with nothing
        // measured now shows prose and no receptor list — an absence, not a placeholder.
        for category in SubstanceCategory.allCases {
            let targets = (MechanismOfActionDatabase.categoryFallback(for: category)?.bindings ?? [])
                .map(\.target)
            #expect(
                targets.allSatisfy { !$0.contains(" system") && $0 != "Various" },
                "\(category) still names a system rather than a target: \(targets)",
            )
        }
    }

    @Test
    @MainActor
    func `Mitragynine and kratom are partial MOR agonists with adrenergic activity`() {
        // The curated mitragynine/kratom data now lives in the bundled DB
        // (`piru-curated`), no longer the Swift `substanceData`, so this is an
        // end-to-end check through the same hydration path the detail view uses.
        for name in ["Mitragynine", "Kratom"] {
            guard let sub = SubstanceStore.shared.lookup(name) else {
                Issue.record("\(name) missing from bundled DB"); continue
            }
            let m = MechanismOfActionDatabase.resolvedMechanism(
                dbMechanism: sub.mechanismOfAction, substanceName: sub.name, category: sub.category,
            )
            #expect(m != nil, "\(name) should resolve a mechanism")
            let mu = m?.bindings.first { $0.target.localizedCaseInsensitiveContains("opioid") }
            #expect(
                mu?.action == .partialAgonist,
                "\(name) μ-opioid action should be partialAgonist, got \(mu?.action.rawValue ?? "nil")",
            )
            #expect(mu?.action != .agonist, "\(name) must not be a full μ-opioid agonist")
            // Carries its non-opioid targets (the data that the measured opioid
            // panel omits and that motivated the curated entry).
            let hasAdrenergic = m?.bindings.contains { $0.target.localizedCaseInsensitiveContains("adrenergic") } ?? false
            #expect(hasAdrenergic, "\(name) should list α2-adrenergic activity")
        }
    }

    // MARK: - Composition precedence

    @Test
    func `Measured DB bindings beat the category's generic Modulator placeholder`() {
        // A substance with no curated per-name entry, no DB summary, but real
        // measured releaser bindings — must surface those, not the .stimulant
        // category fallback's [Dopamine .modulator, …] placeholders.
        let db = moa(summary: "", bindings: [
            binding("DAT", .releasingAgent), binding("NET", .releasingAgent), binding("SERT", .releasingAgent),
        ])
        let resolved = MechanismOfActionDatabase.resolvedMechanism(
            dbMechanism: db, substanceName: "zzzSyntheticReleaser-NoHandEntry", category: .stimulant,
        )
        #expect(resolved != nil)
        #expect(
            resolved?.bindings.allSatisfy { $0.action == .releasingAgent } == true,
            "Composed bindings should be the measured releasingAgent rows, not category .modulator",
        )
        #expect(resolved?.bindings.contains { $0.action == .modulator } == false)
    }

    @Test
    func `A class template never displaces a DB binding target`() {
        // The rule the Mechanism card rests on: the cited panel outranks the generic list.
        // fluoxetine maps to the SSRI template (SERT only) while its DB row carries NET,
        // 5-HT2C and sigma-1 — substituting the template would drop all three.
        let db = moa(summary: "DB summary", bindings: [
            binding("SERT", .reuptakeInhibitor), binding("NET", .reuptakeInhibitor),
            binding("5-HT2C", .antagonist), binding("sigma-1", .agonist),
        ])
        let resolved = MechanismOfActionDatabase.resolvedMechanism(
            dbMechanism: db, substanceName: "fluoxetine", category: .antidepressant,
        )
        for target in ["SERT", "NET", "5-HT2C", "sigma-1"] {
            #expect(
                resolved?.bindings.contains { $0.target == target } == true,
                "\(target) came from the DB and must survive the SSRI template",
            )
        }
        #expect(resolved?.bindings.first?.target == "SERT", "DB rows keep their tier order and lead")
    }

    @Test
    @MainActor
    func `No class-mapped substance loses a DB binding target end-to-end`() async {
        // The blanket form of the rule above, over every key the Swift table maps.
        // This is the invariant `resolvedMechanism`'s doc comment asserts; it went
        // false once already, silently, when the two sets stopped being disjoint.
        await SubstanceStore.shared.ensureAllLoaded()
        for key in MechanismOfActionDatabase.substanceKeys {
            guard let sub = SubstanceStore.shared.lookup(key),
                  let dbBindings = sub.mechanismOfAction?.bindings, !dbBindings.isEmpty else { continue }
            let resolved = MechanismOfActionDatabase.resolvedMechanism(
                dbMechanism: sub.mechanismOfAction, substanceName: sub.name, category: sub.category,
            )
            let shown = Set((resolved?.bindings ?? []).map { SubstanceReadModel.normalizedBindingTarget($0.target) })
            let missing = dbBindings
                .map { SubstanceReadModel.normalizedBindingTarget($0.target) }
                .filter { !shown.contains($0) }
            #expect(missing.isEmpty, "\(key) drops DB targets \(missing.sorted())")
        }
    }

    @Test
    @MainActor
    func `The class-level receptor profile now comes from the DB, not from Swift`() async {
        // A tricyclic's H1/M1/α1 profile is the sedation-and-orthostasis story and appears in no
        // part of the phrase "Tricyclic Antidepressant", so it survived the tautology cull — and
        // it now lives in `bindings` via data/curated/class-mechanism-bindings.json rather than
        // in a Swift template. This is the end-to-end proof of that move.
        await SubstanceStore.shared.ensureAllLoaded()
        guard let sub = SubstanceStore.shared.lookup("Amitriptyline") else {
            Issue.record("Amitriptyline missing from bundled DB"); return
        }
        let resolved = MechanismOfActionDatabase.resolvedMechanism(
            dbMechanism: sub.mechanismOfAction, substanceName: sub.name, category: sub.category,
        )
        for target in ["H1", "M1", "α1-adrenergic", "SERT", "NET"] {
            #expect(
                resolved?.bindings.contains { $0.target == target } == true,
                "amitriptyline should show \(target) from the DB",
            )
        }
        // And Swift contributes nothing: the template is prose now.
        #expect(MechanismOfActionDatabase.mechanism(for: "amitriptyline")?.bindings.isEmpty == true)
    }

    @Test
    @MainActor
    func `Relocated class prose resolves from the DB in place of the template`() async {
        // Fluvoxamine had no mechanism summary from any source, so the SSRI class paragraph in
        // Swift was the only text on its card. It now ships as a `piru-curated` row in each of
        // en / zh-Hans / zh-Hant, lifted from the translations the template already carried.
        await SubstanceStore.shared.ensureAllLoaded()
        guard let sub = SubstanceStore.shared.lookup("Fluvoxamine") else {
            Issue.record("Fluvoxamine missing from bundled DB"); return
        }
        #expect(
            sub.mechanismOfAction?.summary.contains("SSRI") == true,
            "the class summary should come from the DB now, got \(sub.mechanismOfAction?.summary ?? "nil")",
        )
        let resolved = MechanismOfActionDatabase.resolvedMechanism(
            dbMechanism: sub.mechanismOfAction, substanceName: sub.name, category: sub.category,
        )
        #expect(resolved?.summary == sub.mechanismOfAction?.summary, "the DB row is what displays")
    }

    @Test
    func `No class template carries a receptor list any more`() {
        // The whole Swift table is prose. A binding list here would be a second copy of the
        // panel with no citation and no way to be corrected without an app release; where a
        // class genuinely knows an unmeasured target, it belongs in
        // data/curated/class-mechanism-bindings.json.
        for key in MechanismOfActionDatabase.substanceKeys {
            #expect(
                MechanismOfActionDatabase.mechanism(for: key)?.bindings.isEmpty != false,
                "\(key)'s template grew a binding list back",
            )
        }
    }

    @Test
    func `A real DB summary is preferred verbatim over fallbacks`() {
        let db = moa(summary: "Bespoke measured summary", bindings: [binding("5-HT2A", .agonist)])
        let resolved = MechanismOfActionDatabase.resolvedMechanism(
            dbMechanism: db, substanceName: "zzzUnknown", category: .psychedelic,
        )
        #expect(resolved?.summary == "Bespoke measured summary")
        #expect(resolved?.bindings.first?.target == "5-HT2A")
    }

    @Test
    func `An unknown substance falls back to its category mechanism (the floor)`() {
        // Every real category provides a generic fallback, so resolution never
        // dead-ends to nil for a known category — it bottoms out at the category
        // mechanism. (nil is reserved for the no-category / no-data degenerate.)
        let resolved = MechanismOfActionDatabase.resolvedMechanism(
            dbMechanism: nil, substanceName: "zzzCompletelyUnknownCompound", category: .stimulant,
        )
        #expect(resolved != nil)
        #expect(resolved?.summary == MechanismOfActionDatabase.categoryFallback(for: .stimulant)?.summary)
    }

    @Test
    func `DORAs resolve to an orexin-receptor mechanism, never the GABA depressant fallback`() {
        // The bug: daridorexant/lemborexant/suvorexant were categorised Depressant and
        // showed the generic "GABA + Glutamate" CNS-depressant text — pharmacologically
        // wrong. With the .orexinAntagonist category they must resolve to OX1R/OX2R
        // antagonism and carry NO GABA/glutamate bindings.
        let resolved = MechanismOfActionDatabase.resolvedMechanism(
            dbMechanism: nil, substanceName: "Suvorexant", category: .orexinAntagonist,
        )
        #expect(resolved != nil)
        #expect(resolved?.bindings.contains { $0.target == "OX1R" && $0.action == .antagonist } == true)
        #expect(resolved?.bindings.contains { $0.target == "OX2R" && $0.action == .antagonist } == true)
        #expect(
            resolved?.bindings.contains { $0.target.localizedCaseInsensitiveContains("GABA") } == false,
            "A DORA must not show any GABA binding",
        )
        #expect(resolved?.summary.localizedCaseInsensitiveContains("orexin") == true)
    }

    // MARK: - Integration against the bundled database

    //
    // These exercise the same hydration path the detail view uses
    // (`lookup` → `resolveSubstance`, which populates `mechanismOfAction`).
    // `SubstanceStore.all` deliberately does NOT load mechanisms, so tests must
    // go through `lookup`.

    @Test
    @MainActor
    func `Mephedrone resolves to a releaser mechanism, not generic Modulator`() {
        guard let sub = SubstanceStore.shared.lookup("Mephedrone") else {
            Issue.record("Mephedrone missing from bundled DB"); return
        }
        let resolved = MechanismOfActionDatabase.resolvedMechanism(
            dbMechanism: sub.mechanismOfAction, substanceName: sub.name, category: sub.category,
        )
        #expect(resolved != nil)
        let transporters = resolved?.bindings.filter { ["DAT", "NET", "SERT"].contains($0.target) } ?? []
        #expect(!transporters.isEmpty, "Mephedrone should show transporter bindings")
        #expect(
            transporters.allSatisfy { $0.action == .releasingAgent },
            "Mephedrone transporters must be releasing agents, not modulators",
        )
        #expect(
            resolved?.bindings.contains { $0.action == .modulator } == false,
            "Mephedrone must not show any .modulator placeholder bindings",
        )
    }

    @Test
    @MainActor
    func `Approved DORAs are categorised orexinAntagonist in the bundled DB and read OX receptors`() {
        // Guards the pipeline → app wiring: the curated `OrexinAntagonist` category must
        // survive the rebuild and drive the OX1R/OX2R mechanism (not the GABA fallback).
        for name in ["Daridorexant", "Lemborexant", "Suvorexant"] {
            guard let sub = SubstanceStore.shared.lookup(name) else {
                Issue.record("\(name) missing from bundled DB"); continue
            }
            #expect(sub.category == .orexinAntagonist, "\(name) should be .orexinAntagonist, got \(sub.category)")
            let resolved = MechanismOfActionDatabase.resolvedMechanism(
                dbMechanism: sub.mechanismOfAction, substanceName: sub.name, category: sub.category,
            )
            #expect(resolved?.bindings.contains { $0.target == "OX1R" } == true, "\(name) should list OX1R")
            #expect(
                resolved?.bindings.contains { $0.target.localizedCaseInsensitiveContains("GABA") } == false,
                "\(name) must not show a GABA binding",
            )
        }
    }

    @Test
    @MainActor
    func `Mitragynine resolves to partial agonist end-to-end, never 'Full Agonist'`() {
        guard let sub = SubstanceStore.shared.lookup("Mitragynine") else {
            Issue.record("Mitragynine missing from bundled DB"); return
        }
        let resolved = MechanismOfActionDatabase.resolvedMechanism(
            dbMechanism: sub.mechanismOfAction, substanceName: sub.name, category: sub.category,
        )
        #expect(resolved?.summary.localizedCaseInsensitiveContains("full agonist") == false)
        let mu = resolved?.bindings.first { $0.target.localizedCaseInsensitiveContains("opioid") }
        #expect(mu?.action == .partialAgonist)
    }

    @Test
    @MainActor
    func `Substances with measured bindings expose them even without a summary row`() {
        // The original bug: resolvedMechanism (in SubstanceStore) bailed entirely
        // when a substance had bindings but no mechanisms_summary row. Mephedrone
        // has measured releaser bindings in the bundled DB but no summary, so its
        // hydrated `mechanismOfAction` must still be non-nil and carry them.
        guard let sub = SubstanceStore.shared.lookup("Mephedrone") else {
            Issue.record("Mephedrone missing from bundled DB"); return
        }
        #expect(
            sub.mechanismOfAction != nil,
            "Mephedrone's DB mechanism should be non-nil (bindings present)",
        )
        #expect(
            sub.mechanismOfAction?.bindings.isEmpty == false,
            "Mephedrone's DB mechanism should carry its measured bindings",
        )
    }

    // MARK: - MOA relocation (Stage 3): curated prose + bindings now in the DB

    @Test
    @MainActor
    func `Relocated curated mechanism surfaces its summary and preserves affinity tiers`() {
        // Mitragynine's bespoke MOA was relocated from the Swift file into the
        // bundled DB (`piru-curated`). Its summary must surface and its ordinal
        // affinity tiers must round-trip via the new `affinity_tier` column
        // (no numeric Ki) — μ-opioid primary, α2-adrenergic significant.
        guard let sub = SubstanceStore.shared.lookup("Mitragynine") else {
            Issue.record("Mitragynine missing from bundled DB"); return
        }
        let m = MechanismOfActionDatabase.resolvedMechanism(
            dbMechanism: sub.mechanismOfAction, substanceName: sub.name, category: sub.category,
        )
        #expect(m?.summary.localizedCaseInsensitiveContains("partial") == true)
        let mu = m?.bindings.first { $0.target.localizedCaseInsensitiveContains("opioid") }
        #expect(mu?.affinity == .primary, "μ-opioid tier should be primary (affinity_tier=3)")
        let a2 = m?.bindings.first { $0.target.localizedCaseInsensitiveContains("adrenergic") }
        #expect(a2?.affinity == .significant, "α2-adrenergic tier should be significant (affinity_tier=2)")
    }

    @Test
    @MainActor
    func `A prose-only relocated mechanism (no bindings) still resolves a summary`() {
        // 5-HTP is a serotonin precursor: relocated with prose but deliberately
        // no binding chip (precursor steps aren't receptor targets). Its mechanism
        // must still resolve a non-empty summary, not nil.
        guard let sub = SubstanceStore.shared.lookup("5-Hydroxytryptophan") else {
            Issue.record("5-Hydroxytryptophan missing from bundled DB"); return
        }
        let m = MechanismOfActionDatabase.resolvedMechanism(
            dbMechanism: sub.mechanismOfAction, substanceName: sub.name, category: sub.category,
        )
        #expect(m?.summary.isEmpty == false, "5-HTP should resolve a curated summary")
    }
}
