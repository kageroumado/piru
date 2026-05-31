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
        MechanismOfAction(summary: summary, description: "", bindings: bindings, references: [])
    }

    // MARK: - Curated per-name entries are pharmacologically correct

    @Test
    func `Releaser cathinones bind transporters as releasing agents, never as modulators`() {
        for name in ["mephedrone", "4-mmc", "3-mmc", "2-mmc", "methylone", "methcathinone"] {
            let m = MechanismOfActionDatabase.mechanism(for: name)
            #expect(m != nil, "\(name) should have a curated mechanism entry")
            let transporters = m?.bindings.filter { ["DAT", "NET", "SERT"].contains($0.target) } ?? []
            #expect(!transporters.isEmpty, "\(name) should list DAT/NET/SERT")
            for t in transporters {
                #expect(
                    t.action == .releasingAgent,
                    "\(name) \(t.target) should be a releasingAgent, got \(t.action.rawValue)",
                )
            }
        }
    }

    @Test
    func `Pyrovalerone cathinones are DAT/NET reuptake inhibitors, not releasers`() {
        for name in ["mdpv", "α-pvp", "a-pvp", "α-php"] {
            let m = MechanismOfActionDatabase.mechanism(for: name)
            #expect(m != nil, "\(name) should have a curated mechanism entry")
            let transporters = m?.bindings.filter { ["DAT", "NET"].contains($0.target) } ?? []
            #expect(!transporters.isEmpty, "\(name) should list DAT/NET")
            for t in transporters {
                #expect(
                    t.action == .reuptakeInhibitor,
                    "\(name) \(t.target) should be a reuptakeInhibitor, got \(t.action.rawValue)",
                )
            }
        }
    }

    @Test
    func `Mitragynine and kratom are partial MOR agonists with adrenergic activity`() {
        for name in ["mitragynine", "kratom"] {
            let m = MechanismOfActionDatabase.mechanism(for: name)
            #expect(m != nil, "\(name) should have a curated mechanism entry")
            let mu = m?.bindings.first { $0.target.localizedCaseInsensitiveContains("opioid") }
            #expect(
                mu?.action == .partialAgonist,
                "\(name) μ-opioid action should be partialAgonist, got \(mu?.action.rawValue ?? "nil")",
            )
            // Not a full agonist
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
    func `A curated per-name entry's bindings win over a thinner DB panel`() {
        // Mirrors mitragynine: the measured DB panel has only the opioid receptors,
        // but the curated entry adds α2-adrenergic. The richer curated set must win.
        let db = moa(summary: "", bindings: [binding("MOR", .partialAgonist)])
        let resolved = MechanismOfActionDatabase.resolvedMechanism(
            dbMechanism: db, substanceName: "mitragynine", category: .opioid,
        )
        #expect(
            resolved?.bindings.contains { $0.target.localizedCaseInsensitiveContains("adrenergic") } == true,
            "Curated α2-adrenergic binding must survive composition",
        )
        // And the summary must be the curated partial-agonist one, not the
        // opioid category's "Full Agonist" default.
        #expect(
            resolved?.summary.localizedCaseInsensitiveContains("full agonist") == false,
            "Mitragynine must not resolve to the opioid 'Full Agonist' category default",
        )
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
}
