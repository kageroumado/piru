import Foundation
import Testing
@testable import Piru

/// The clinical-equivalence factors exist in two places each: the converter
/// tools' tables and the tolerance engine's Stage D fallback. The opioid side
/// is now derived (one table); these tests pin the shared values so drift like
/// the hydromorphone 4-vs-5 slip cannot recur silently.
@Suite("EquivalenceAgreement")
struct EquivalenceAgreementTests {
    /// CDC 2022 (MMWR RR-71 No. 3) oral MME factors, pinned literally. The
    /// tolerance fallback derives its table from ``OpioidEquivalence/table``,
    /// so this single assertion covers both consumers.
    @Test
    func `Opioid MME factors match CDC 2022`() {
        let expected: [String: Double] = [
            "morphine": 1, "codeine": 0.15, "hydrocodone": 1, "oxycodone": 1.5,
            "oxymorphone": 3, "hydromorphone": 5, "tramadol": 0.2, "tapentadol": 0.4,
        ]
        #expect(ToleranceStore.opioidMMEPerMg == expected)
    }

    /// The un-convertible opioids (nonlinear methadone, transdermal fentanyl,
    /// ceiling-limited buprenorphine) must never gain a linear factor — the
    /// tolerance fallback would silently start converting them.
    @Test
    func `Un-convertible opioids carry no linear factor`() {
        for name in ["methadone", "fentanyl", "buprenorphine"] {
            #expect(ToleranceStore.opioidMMEPerMg[name] == nil, "\(name) must stay un-convertible")
        }
    }

    /// Benzodiazepine diazepam-equivalence now has exactly one home: the bundled DB's
    /// `diazepam_equivalents`. Both consumers — the converter tool's batched
    /// ``SubstanceStore/benzoEquivalences()`` and the tolerance fallback's per-substance
    /// ``PharmacologyParameters/diazepamPerMg`` — resolve from it at the user's source priority, so
    /// this gates the rows themselves rather than pinning a second copy in Swift.
    ///
    /// The assertions are the ones a data rebuild can actually break: the identity anchor, an
    /// inversion check (potency ordering), and a unit-swap band. Individual factors are not
    /// re-asserted here — the DB row is the cited value, and a test restating it would only be a
    /// literal table wearing a different hat.
    @Test
    @MainActor
    func `Diazepam-equivalence rows are self-consistent`() {
        let dbEquivalences = SubstanceStore.shared.benzoEquivalences()
        guard !dbEquivalences.isEmpty else {
            Issue.record("No diazepam_equivalents rows in the bundled DB")
            return
        }
        let ratios = Dictionary(
            dbEquivalences.compactMap { benzo in benzo.diazepamPerMg.map { (benzo.name.lowercased(), $0) } },
            uniquingKeysWith: { first, _ in first },
        )
        #expect(ratios.count >= 25, "only \(ratios.count) benzos carry a numeric equivalence")

        // Identity: diazepam converts to itself 1:1. Catches an inverted ratio or a unit swap at the
        // one row whose correct answer needs no source at all.
        #expect(ratios["diazepam"] == 1)

        // Potency ordering. The high-potency benzos dose in fractions of a milligram, so one of their
        // mg is worth many diazepam mg; the low-potency ones are the reverse. An inverted or
        // dose_mg/equivalent_mg-swapped column flips both groups at once.
        for name in ["alprazolam", "clonazepam", "triazolam"] {
            guard let ratio = ratios[name] else { Issue.record("\(name) missing"); continue }
            #expect(ratio > 5, "\(name) is high-potency; expected ≫1 diazepam-mg per mg, got \(ratio)")
        }
        for name in ["chlordiazepoxide", "oxazepam", "temazepam"] {
            guard let ratio = ratios[name] else { Issue.record("\(name) missing"); continue }
            #expect(ratio < 1, "\(name) is low-potency; expected <1 diazepam-mg per mg, got \(ratio)")
        }

        // No row may carry an implausible magnitude — the shape a mg/µg or mg/g mix-up takes.
        for (name, ratio) in ratios {
            #expect(ratio > 0.05 && ratio < 100, "\(name): \(ratio)× diazepam-per-mg is out of range")
        }
    }

    /// The designer benzodiazepines ship a `diazepam_equivalents` row that carries the "no validated
    /// equivalence" prose and **no numbers**. The tolerance fallback must read `nil` for them and drop
    /// to the dose-fraction proxy: a back-derived multiplier from the forums would convert an RC benzo
    /// as though a clinical equivalence study existed for it.
    @Test
    @MainActor
    func `Designer benzos carry no equivalence factor`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        for name in ["Flubromazolam", "Flubromazepam", "Diclazepam", "Pyrazolam"] {
            let params = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: name)
            #expect(params.diazepamPerMg == nil, "\(name) must stay un-convertible")
        }
    }

    /// The two read paths over `diazepam_equivalents` — the converter's batched window query and the
    /// tolerance resolver's per-substance read — must agree. They resolve the same row through
    /// different SQL, so a divergence means one of them picked a different source.
    @Test
    @MainActor
    func `Both diazepam-equivalence read paths agree`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        var compared = 0
        for benzo in SubstanceStore.shared.benzoEquivalences() {
            guard let batched = benzo.diazepamPerMg else { continue }
            let resolved = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: benzo.name).diazepamPerMg
            #expect(resolved == batched, "\(benzo.name): converter \(batched)× vs resolver \(String(describing: resolved))×")
            compared += 1
        }
        #expect(compared >= 25, "only \(compared) benzos compared across the two read paths")
    }
}
