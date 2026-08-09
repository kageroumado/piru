import Foundation
import Testing
@testable import Piru

/// D.4 — a dose that names a form we don't model draws a marker, not a curve.
///
/// See `Specs/psid-identity-consumption.md` LB-5/LB-6. The rule: a release form
/// other than the standard one is denied the base curve in
/// `ActiveSubstanceCalculator.from(entry:)`, because it would answer with the
/// base form's kinetics. **The exception (adhd-audience-fit):** a named ER
/// *product* with an authored `product_durations` envelope (Concerta, Adderall
/// XR) is modeled per-product and draws its own curve — see `ProductDurationTests`.
/// So the unmodeled exemplar here is a bare `XR` naming no known product, which we
/// genuinely can't place. (Curve resolution was two tiers when these tests were
/// written; the half-life tier has since been removed, so several nets below now
/// hold for two independent reasons.)
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
        // IR is immediate release — the base ladder every source publishes IS
        // measured on it, so it draws a curve like the unspecified form. Treating
        // it as unmodeled meant "Adderall IR" drew nothing while a bare
        // "Adderall" drew a full curve, for the same dose of the same drug.
        #expect(entry("Amphetamine", releaseForm: "IR").namesUnmodeledForm == false)
        #expect(entry("Amphetamine", releaseForm: "ir").namesUnmodeledForm == false, "case-insensitive")
    }

    // MARK: - Tier 1: a substance that HAS durations

    @Test
    func `An XR naming no known product draws no curve`() {
        // Methylphenidate's duration rows are all the ~150–240 min immediate-release
        // profile. A dose tagged XR but naming no product we've authored could be any
        // of several formulations (Concerta 12 h, Ritalin LA 8 h…), so we draw
        // nothing rather than the IR curve. (A *named* Concerta draws — see
        // `ProductDurationTests`.)
        let state = ActiveSubstanceState.from(entry: entry("Methylphenidate", releaseForm: "XR"), colorHex: "#FF0000")
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

    // MARK: - Half-life is never a curve (the old tier 2, now removed)

    @Test
    func `Depot aripiprazole does not synthesize a half-life curve`() {
        // Aripiprazole has zero duration rows, so it never reaches the duration
        // tier. It used to fall through to half-life synthesis — and
        // `resolveHalfLifeMinutes` searches by name and by every alias, so its
        // ORAL half-life (4,500 min / 75 h) drew a ~15-day arc under a depot
        // injection that actually lasts a month. Now nil for two independent
        // reasons: the unmodeled form, and the absence of any half-life fallback.
        let state = ActiveSubstanceState.from(
            entry: entry("Aripiprazole", releaseForm: "DEP", productName: "Abilify Maintena", amount: 400),
            colorHex: "#FF0000",
        )
        #expect(state == nil, "the alias half-life lookup must not resurrect a curve for an unmodeled form")
    }

    @Test
    func `Oral aripiprazole draws no curve either`() {
        // The half-life fallback is gone, so a *plain* oral dose of a substance
        // with no acute duration profile draws nothing either. An antipsychotic
        // has no acute curve to draw; deriving one from elimination kinetics
        // plotted a flat multi-week plateau over every real curve on the graph
        // (fluoxetine's 16-day t½ → a 69-day "effect", `1,638h left`). The
        // release-form guard's genuine control is
        // `Bare methylphenidate still draws its curve` above — a substance that
        // actually has durations, which is what makes it a control.
        let state = ActiveSubstanceState.from(entry: entry("Aripiprazole", amount: 10), colorHex: "#FF0000")
        #expect(state == nil, "a half-life is not an effect profile")
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
        let doses = [entry("Methylphenidate", releaseForm: "XR")]
        let timeline = ActiveSubstanceState.timeline(for: doses, colors: [])
        #expect(timeline.states.isEmpty)
        #expect(timeline.markers.count == 1)
    }

    @Test
    func `A mixed day keeps the modeled curve and marks the rest`() {
        let doses = [
            entry("Methylphenidate", releaseForm: "XR"),
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
        let doses = [entry("Methylphenidate", releaseForm: "XR")]
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
            entry("Methylphenidate", releaseForm: "XR"),
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
        let concerta = entry("Methylphenidate", releaseForm: "XR")
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
