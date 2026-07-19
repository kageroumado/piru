import Foundation
import Testing
@testable import Piru

/// D.3 — one resolver, one precedence (`Specs/psid-identity-consumption.md` LB-3):
/// relabel → product name → composed form title → snapshot → raw.
@Suite("Dose title")
@MainActor
struct DoseTitleTests {
    private func entry(
        _ substance: String,
        isomer: String? = nil,
        releaseForm: String? = nil,
        productName: String? = nil,
        snapshot: String? = nil,
        amount: Double = 10,
    ) -> DoseEntry {
        DoseEntry(
            substance: substance, amount: amount, unit: "mg", route: .oral,
            isomer: isomer, releaseForm: releaseForm, productName: productName,
            displayNameSnapshot: snapshot,
        )
    }

    // MARK: - The precedence

    @Test
    func `A plain dose titles from the catalog`() {
        #expect(DoseTitle.resolve(for: entry("Methylphenidate")) == "Methylphenidate")
    }

    @Test
    func `The product the user named wins over the catalog`() {
        // The payoff of the whole arc: this row said "Methylphenidate" before.
        #expect(DoseTitle.resolve(for: entry("Methylphenidate", releaseForm: "XR", productName: "Concerta")) == "Concerta")
        #expect(DoseTitle.resolve(for: entry("Lisdexamfetamine", productName: "Vyvanse")) == "Vyvanse")
    }

    @Test
    func `A picked isomer titles from the composed form`() {
        // Finding 2 of the spec: the user picks Esketamine on Ketamine, the string
        // never says so, and Stage A then hid the form they explicitly chose.
        #expect(DoseTitle.resolve(for: entry("Ketamine", isomer: "S")) == "Esketamine")
        #expect(DoseTitle.resolve(for: entry("Methylphenidate", isomer: "D")) == "Dexmethylphenidate")
    }

    @Test
    func `A recovered release form titles from the composed form`() {
        // No product name (a backfilled dose), but the facet survives.
        #expect(DoseTitle.resolve(for: entry("Methylphenidate", releaseForm: "XR")) == "Methylphenidate XR")
    }

    @Test
    func `Both axes compose`() {
        #expect(DoseTitle.resolve(for: entry("Methylphenidate", isomer: "D", releaseForm: "XR")) == "Dexmethylphenidate XR")
    }

    @Test
    func `Depot composes its prose, not its code`() {
        #expect(DoseTitle.resolve(for: entry("Aripiprazole", releaseForm: "DEP")) == "Aripiprazole Depot")
    }

    @Test
    func `An unresolvable dose keeps its raw string`() {
        // Never-drop. A typo, a deleted custom, a substance the catalog forgot.
        #expect(DoseTitle.resolve(for: entry("Blorbotropin")) == "Blorbotropin")
    }

    @Test
    func `An unresolvable dose prefers its snapshot to its raw string`() {
        #expect(DoseTitle.resolve(for: entry("Blorbotropin", snapshot: "Blorbotropin XR")) == "Blorbotropin XR")
    }

    @Test
    func `A resolvable dose ignores a stale snapshot`() {
        // In-app the snapshot is a fallback, not the source — it is canonical and
        // un-relabelled, so rendering it ahead of the live derive would regress
        // both regionalization and relabels.
        #expect(DoseTitle.resolve(for: entry("Methylphenidate", snapshot: "Something Stale")) == "Methylphenidate")
    }

    @Test
    func `An empty product name is not a title`() {
        #expect(DoseTitle.resolve(for: entry("Methylphenidate", productName: "   ")) == "Methylphenidate")
    }

    // MARK: - The snapshot writers agree

    @Test
    func `Every writer composes the same snapshot`() {
        // The writers disagreed: live log paths snapshotted only the isomer's name
        // (nil for the racemic case), the backfill the full composed title. Same
        // dose, different snapshot depending on how it arrived.
        #expect(DoseTitle.snapshot(canonicalName: "Methylphenidate", isomer: nil, releaseForm: "XR") == "Methylphenidate XR")
        #expect(DoseTitle.snapshot(canonicalName: "Methylphenidate", isomer: "D", releaseForm: "XR") == "Dexmethylphenidate XR")
        #expect(DoseTitle.snapshot(canonicalName: "Methylphenidate", isomer: nil, releaseForm: nil) == "Methylphenidate")
        #expect(DoseTitle.snapshot(canonicalName: "Blorbotropin", isomer: nil, releaseForm: nil) == nil)
    }

    @Test
    func `A staged Concerta snapshots its composed title, not nil`() {
        // Previously nil: `isomerDisplayName` returned nil for the racemic case,
        // so a newly logged Concerta snapshotted nothing while a backfilled one
        // got "Methylphenidate XR".
        let staged = StagedDose(
            substanceName: "Methylphenidate", amount: 36, unit: "mg", route: .oral,
            productName: "Concerta",
        )
        #expect(staged.displayNameSnapshot == "Methylphenidate XR")
    }

    @Test
    func `The snapshot stays canonical, never regionalized`() {
        // It must be a locale-stable anchor: `RegionalSubstanceName` keys on a
        // canonical substance name, so a regionalized snapshot could never be
        // resolved back (and "Methylphenidate XR" is not a canonical name at all).
        #expect(DoseTitle.snapshot(canonicalName: "Acetaminophen", isomer: nil, releaseForm: nil) == "Acetaminophen")
    }

    // MARK: - Dose level agrees with itself (D.3.4)

    @Test
    func `Dose level classifies against the isomer's ladder`() {
        // 7 mg is "common" on the D ladder (5–10) but nowhere near common on
        // racemic methylphenidate's (20–40). The row read the racemic ladder while
        // the staged editor and edit mode read the D one, so the same dose was
        // labelled differently in three places and visibly flipped on Edit/Cancel.
        // (7, not 10: 10 sits exactly on the D ladder's common/strong boundary,
        // where the classifier takes the higher band.)
        let dex = DayEntryCore.make(from: [entry("Methylphenidate", isomer: "D", amount: 7)])
        #expect(dex.first?.doseLevel == .common)

        let racemic = DayEntryCore.make(from: [entry("Methylphenidate", amount: 7)])
        #expect(racemic.first?.doseLevel != .common, "the same 7 mg is not a common racemic dose")
    }

    @Test
    func `Dose level for the racemic dose is unchanged`() {
        // 10 mg sits on the light/common boundary of racemic methylphenidate's
        // preferred (drug.community) ladder — light 5–10, common 10–30 — and the
        // classifier takes the higher band there, so it reads as common. The point
        // of this test is that racemic reads its OWN ladder (not the D isomer's).
        let cores = DayEntryCore.make(from: [entry("Methylphenidate")])
        #expect(cores.first?.doseLevel == .common, "10 mg is common on the racemic 10–30 ladder")
    }

    // MARK: - The derive layer

    @Test
    func `A row takes its title from the resolver and its color from the canonical name`() {
        // The color key must stay canonical: a Concerta row titles "Concerta" but
        // has to take Methylphenidate's color, or one substance renders in two
        // colors depending on what it was called.
        let cores = DayEntryCore.make(from: [entry("Methylphenidate", releaseForm: "XR", productName: "Concerta")])
        #expect(cores.first?.displayName == "Concerta")
        #expect(cores.first?.substanceKey == "methylphenidate")
    }

    @Test
    func `An unmodeled dose gets no rail`() {
        // `totalMinutes` nil ⇒ EntryRowView omits the elimination rail and its
        // countdown, matching the graph, which marks rather than draws it.
        let cores = DayEntryCore.make(from: [entry("Methylphenidate", releaseForm: "XR", productName: "Concerta")])
        #expect(cores.first?.totalMinutes == nil)
    }

    @Test
    func `A modeled dose keeps its rail`() {
        let cores = DayEntryCore.make(from: [entry("Methylphenidate")])
        #expect((cores.first?.totalMinutes ?? 0) > 0)
    }
}
