import Testing
@testable import Piru

/// ``SubstanceStore/displayRows(_:)`` — the per-route collapse behind the
/// Pharmacokinetics card. The raw table holds a row per *study*, and the card
/// renders only the metrics those rows tend to agree on, so an over-researched
/// route used to print what looked like the same card several times.
@Suite("PK display rows")
struct PKDisplayRowsTests {
    private func hit(
        id: Int64,
        route: String = "oral",
        bioavailability: Double? = nil,
        cmax: Double? = nil,
        tmax: Double? = nil,
        halfLife: Double? = nil,
        proteinBinding: Double? = nil,
        doseInStudyMg: Double? = nil,
        subjectN: Int? = nil,
        demographics: String? = nil,
        species: String? = nil,
        notes: String? = nil,
    ) -> SubstanceStore.PKRouteHit {
        SubstanceStore.PKRouteHit(
            id: id,
            route: route,
            bioavailabilityPct: bioavailability,
            cmaxNgPerMl: cmax,
            tmaxMin: tmax,
            halfLifeMin: halfLife,
            vdLPerKg: nil,
            clearanceMlPerMinPerKg: nil,
            proteinBindingPct: proteinBinding,
            doseInStudyMg: doseInStudyMg,
            subjectN: subjectN,
            demographics: demographics,
            species: species,
            sourceSlug: "peer-review-primary",
            doi: nil,
            pmid: nil,
            notes: notes,
        )
    }

    @Test
    func `A route collapses to one row`() {
        let rows = SubstanceStore.displayRows([
            hit(id: 1, route: "oral", bioavailability: 33),
            hit(id: 2, route: "oral", bioavailability: 33),
            hit(id: 3, route: "insufflation", bioavailability: 60),
        ])
        #expect(rows.count == 2)
        #expect(rows.map(\.hit.route) == ["oral", "insufflation"])
    }

    @Test
    func `Rows differing only in prose are one study, not two (the cocaine case)`() {
        // Cocaine shipped two inhalation rows with identical measurements and
        // citation, differing only in a `notes` field the card never renders.
        let rows = SubstanceStore.displayRows([
            hit(
                id: 1,
                route: "inhalation",
                bioavailability: 70,
                tmax: 5,
                halfLife: 56,
                proteinBinding: 91,
                notes: "Smoked free-base (crack).",
            ),
            hit(
                id: 2,
                route: "inhalation",
                bioavailability: 70,
                tmax: 5,
                halfLife: 56,
                proteinBinding: 91,
                notes: "Arterial-venous gradient produces a brain bolus.",
            ),
        ])
        #expect(rows.count == 1)
        #expect(rows[0].studyCount == 1)
    }

    @Test
    func `Genuinely different studies are counted, so the card can say so`() {
        // MDMA oral: S-MDMA vs R-MDMA vs a dose-doubled arm are real, distinct
        // measurements — collapsing them must not pretend there was only one.
        let rows = SubstanceStore.displayRows([
            hit(id: 1, tmax: 168, halfLife: 246, doseInStudyMg: 125, subjectN: 24),
            hit(id: 2, tmax: 192, halfLife: 720, doseInStudyMg: 125, subjectN: 24),
            hit(id: 3, tmax: 216, halfLife: 840, doseInStudyMg: 250, subjectN: 24),
        ])
        #expect(rows.count == 1)
        #expect(rows[0].studyCount == 3)
    }

    @Test
    func `The row filling in the most metrics wins`() {
        let rows = SubstanceStore.displayRows([
            hit(id: 1, bioavailability: 90),
            hit(id: 2, bioavailability: 90, tmax: 180, halfLife: 600, proteinBinding: 20),
            hit(id: 3, bioavailability: 90, tmax: 180),
        ])
        #expect(rows[0].hit.id == 2)
    }

    @Test
    func `Human data outranks animal data even when the animal row is richer`() {
        let rows = SubstanceStore.displayRows([
            hit(id: 1, bioavailability: 90, tmax: 180, halfLife: 600, proteinBinding: 20, species: "rat"),
            hit(id: 2, halfLife: 620, species: "human"),
        ])
        #expect(rows[0].hit.id == 2)
    }

    @Test
    func `A larger subject count breaks a tie between equally rich rows`() {
        let rows = SubstanceStore.displayRows([
            hit(id: 1, tmax: 120, halfLife: 500, subjectN: 6),
            hit(id: 2, tmax: 130, halfLife: 520, subjectN: 24),
        ])
        #expect(rows[0].hit.id == 2)
    }

    @Test
    func `The choice is stable when rows are otherwise indistinguishable`() {
        let rows = SubstanceStore.displayRows([
            hit(id: 7, tmax: 120, halfLife: 500),
            hit(id: 3, tmax: 120, halfLife: 500),
        ])
        #expect(rows[0].hit.id == 3)
    }

    @Test
    func `No rows in, no rows out`() {
        #expect(SubstanceStore.displayRows([]).isEmpty)
    }
}
