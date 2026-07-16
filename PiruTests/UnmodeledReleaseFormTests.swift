import Foundation
import Testing
@testable import Piru

/// D.4 — a dose that names a form we don't model draws a marker, not a curve.
///
/// See `Specs/psid-identity-consumption.md` LB-5/LB-6. The rule is uniform: any
/// release form other than the standard one is denied *both* resolution tiers in
/// `ActiveSubstanceCalculator.from(entry:)`, because both would answer with the
/// base form's kinetics.
@Suite("Unmodeled release forms")
@MainActor
struct UnmodeledReleaseFormTests {
    private func entry(
        _ substance: String,
        releaseForm: String? = nil,
        productName: String? = nil,
        amount: Double = 36,
    ) -> DoseEntry {
        DoseEntry(
            substance: substance, amount: amount, unit: "mg", route: .oral,
            releaseForm: releaseForm, productName: productName,
        )
    }

    // MARK: - The predicate

    @Test
    func `Only a non-standard release form counts as unmodeled`() {
        #expect(entry("Methylphenidate").namesUnmodeledForm == false)
        #expect(entry("Methylphenidate", releaseForm: "0").namesUnmodeledForm == false, "the PSID unspecified sentinel is the base form")
        #expect(entry("Methylphenidate", releaseForm: "").namesUnmodeledForm == false)
        #expect(entry("Methylphenidate", releaseForm: "XR").namesUnmodeledForm)
        #expect(entry("Aripiprazole", releaseForm: "DEP").namesUnmodeledForm)
        #expect(entry("Amphetamine", releaseForm: "IR").namesUnmodeledForm)
    }

    // MARK: - Tier 1: a substance that HAS durations

    @Test
    func `Concerta draws no curve`() {
        // Methylphenidate has 38 duration rows — all of them Ritalin's 150–240 min
        // immediate-release profile. Drawing it under an XR dose says the Concerta
        // is finished in three hours.
        let state = ActiveSubstanceState.from(entry: entry("Methylphenidate", releaseForm: "XR", productName: "Concerta"), colorHex: "#FF0000")
        #expect(state == nil)
    }

    @Test
    func `Bare methylphenidate still draws its curve`() {
        // The control. Suppression must be scoped to the form the dose named — a
        // dose that named no form is exactly what the base ladder models.
        let state = ActiveSubstanceState.from(entry: entry("Methylphenidate"), colorHex: "#FF0000")
        #expect(state != nil)
        #expect((state?.totalMinutes ?? 0) > 0)
    }

    @Test
    func `Ritalin draws its curve`() {
        // A bare brand names no form (the PSID `0` sentinel), so it keeps the base
        // curve. `releaseForm` arrives nil for it — see ProductNameCaptureTests.
        let staged = StagedDose(substanceName: "Methylphenidate", amount: 10, unit: "mg", route: .oral, productName: "Ritalin")
        let state = ActiveSubstanceState.from(
            entry: entry("Methylphenidate", releaseForm: staged.releaseForm, productName: "Ritalin"),
            colorHex: "#FF0000",
        )
        #expect(state != nil, "a bare brand is the standard form and keeps its curve")
    }

    // MARK: - Tier 2: the half-life trap (LB-6 — the whole failure mode)

    @Test
    func `Depot aripiprazole does not synthesize a half-life curve`() {
        // THE regression net. Aripiprazole has zero duration rows, so it never
        // reaches tier 1 — it falls to half-life synthesis, and
        // `resolveHalfLifeMinutes` searches by name and by every alias. Its ORAL
        // half-life is 4,500 min (75 h), which would draw a ~15-day arc under a
        // depot injection that actually lasts a month. Suppressing only the
        // duration tier would leave this fabricated curve in place, wearing a DEP
        // label — the exact bug the supplement carve-out was written to kill.
        let state = ActiveSubstanceState.from(
            entry: entry("Aripiprazole", releaseForm: "DEP", productName: "Abilify Maintena", amount: 400),
            colorHex: "#FF0000",
        )
        #expect(state == nil, "the alias half-life lookup must not resurrect a curve for an unmodeled form")
    }

    @Test
    func `Oral aripiprazole still synthesizes its curve`() {
        // The control for the above: proves the suppression is the release form
        // doing the work, not aripiprazole simply having no data.
        let state = ActiveSubstanceState.from(entry: entry("Aripiprazole", amount: 10), colorHex: "#FF0000")
        #expect(state != nil, "a plain oral dose keeps the synthesized fallback")
    }

    @Test
    func `Effexor XR draws no curve`() {
        // Venlafaxine: zero duration rows + a 300-min half-life ⇒ tier 2 today.
        let state = ActiveSubstanceState.from(
            entry: entry("Venlafaxine", releaseForm: "XR", productName: "Effexor XR", amount: 150),
            colorHex: "#FF0000",
        )
        #expect(state == nil)
    }

    // MARK: - Marker, not invisible

    @Test
    func `An unmodeled dose still lands as a marker`() {
        // Supplements drop off the graph entirely; a release form must not. The
        // user took a real psychoactive dose and the timestamp is the whole point
        // of what's left.
        let doses = [entry("Methylphenidate", releaseForm: "XR", productName: "Concerta")]
        let timeline = ActiveSubstanceState.timeline(for: doses, colors: [])
        #expect(timeline.states.isEmpty)
        #expect(timeline.markers.count == 1)
    }

    @Test
    func `A mixed day keeps the modeled curve and marks the rest`() {
        let doses = [
            entry("Methylphenidate", releaseForm: "XR", productName: "Concerta"),
            entry("Caffeine", amount: 100),
        ]
        let timeline = ActiveSubstanceState.timeline(for: doses, colors: [])
        #expect(timeline.states.count == 1)
        #expect(timeline.markers.count == 1)
    }

    // MARK: - Body load / elimination

    @Test
    func `An unmodeled dose contributes no body-load estimate`() {
        // The elimination half-life is a property of the molecule and survives the
        // delivery matrix — but this readout is not pure elimination: its `ka`
        // comes from the route's immediate-release profile, so a dose released
        // over ~10 h would be modelled as landing at once, and the "clear ~X" time
        // it prints has no basis. Better nothing than misleading.
        let doses = [entry("Methylphenidate", releaseForm: "XR", productName: "Concerta")]
        #expect(ActiveSubstanceCalculator.compute(from: doses, colorMap: [:]).isEmpty)
    }

    @Test
    func `A plain dose still contributes its body load`() {
        let doses = [entry("Methylphenidate")]
        #expect(!ActiveSubstanceCalculator.compute(from: doses, colorMap: [:]).isEmpty)
    }

    @Test
    func `An unmodeled dose does not suppress its neighbors' body load`() {
        let doses = [
            entry("Methylphenidate", releaseForm: "XR", productName: "Concerta"),
            entry("Caffeine", amount: 100),
        ]
        let active = ActiveSubstanceCalculator.compute(from: doses, colorMap: [:])
        #expect(active.count == 1)
        #expect(active.first?.name.localizedCaseInsensitiveContains("caffeine") == true)
    }

    // MARK: - What suppression must NOT touch

    @Test
    func `Interaction warnings still fire for an unmodeled form`() {
        // `InteractionChecker` resolves its active window from the raw `duration(for:)`,
        // deliberately decoupled from the graph gate (and falling back to a 24 h
        // safety window). Suppressing the curve must never suppress a warning —
        // this is exactly the kind of decoupling a later "cleanup" would collapse.
        let concerta = entry("Methylphenidate", releaseForm: "XR", productName: "Concerta")
        #expect(InteractionChecker.activeEntries(from: [concerta]).count == 1)
    }

    @Test
    func `Tolerance still counts an unmodeled dose`() async {
        // The line: kinetic *timing* estimates are suppressed; exposure and safety
        // accounting never are. Receptor adaptation is driven by how much drug
        // arrived, not by how fast the matrix released it — 36 mg of
        // methylphenidate is 36 mg either way. Excluding XR here would understate
        // tolerance, which errs in the dangerous direction.
        let concerta = entry("Methylphenidate", releaseForm: "XR", productName: "Concerta", amount: 36)
        let store = ToleranceStore.shared
        await store.recompute(from: [concerta], now: concerta.timestamp.addingTimeInterval(3_600))
        #expect(!store.states.isEmpty, "an XR dose still builds tolerance")
    }
}
