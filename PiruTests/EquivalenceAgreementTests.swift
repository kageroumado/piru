import Foundation
import Testing
@testable import Piru

/// Clinical-equivalence factors have exactly one home each: the bundled DB's `opioid_mme` and
/// `diazepam_equivalents`. Both are read by two consumers — a converter tool and the tolerance
/// engine's missing-PK fallback — and these tests gate that the consumers agree with each other and
/// that the rows keep the properties that make converting safe.
///
/// Individual factors are not restated here. The DB row is the cited value, and a test repeating it
/// is a second copy of the data wearing a test's clothes — which is exactly what these tests
/// replaced. The pipeline's `test_opioid_mme_*` gates the rows against their source at build time.
@Suite("EquivalenceAgreement")
struct EquivalenceAgreementTests {
    /// Morphine is the reference standard, so its factor is 1.0 by definition — the one value whose
    /// correctness needs no source, and the anchor every other factor is expressed against. An
    /// inverted or rescaled table breaks here first.
    @Test
    @MainActor
    func `Morphine anchors the MME table at 1.0`() {
        let opioids = SubstanceStore.shared.opioidEquivalences()
        #expect(!opioids.isEmpty, "no opioid_mme rows in the bundled DB")
        #expect(opioids.first { $0.name == "morphine" }?.mmePerMg == 1.0)
    }

    /// The un-convertible opioids must never gain a linear factor. Methadone's potency rises with
    /// dose, transdermal fentanyl is dosed in mcg/hr with no oral-mg analogue, and buprenorphine's
    /// ceiling means overdose risk does not scale — so a factor for any of them would let the
    /// converter produce a confident number for exactly the drugs where being wrong is most
    /// dangerous. Both the converter and the tolerance resolver must read nil.
    @Test
    @MainActor
    func `Un-convertible opioids carry no linear factor`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        let opioids = SubstanceStore.shared.opioidEquivalences()
        for name in ["methadone", "fentanyl", "buprenorphine"] {
            let row = opioids.first { $0.name == name }
            #expect(row != nil, "\(name) must stay in the converter so it can explain itself")
            #expect(row?.mmePerMg == nil, "\(name) must stay un-convertible")
            #expect(row?.convertibility != .linear)
            #expect(row?.unconvertibleReason != nil, "\(name) must say why it will not convert")
            let params = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: name)
            #expect(params.opioidMMEPerMg == nil, "\(name) reached the tolerance fallback as convertible")
        }
    }

    /// The converter's batched read and the tolerance resolver's per-substance read must agree.
    /// They resolve the same row through different SQL, so a divergence means one of them picked a
    /// different source — the drift this suite exists to catch.
    @Test
    @MainActor
    func `Both MME read paths agree`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        var compared = 0
        for opioid in SubstanceStore.shared.opioidEquivalences() where opioid.convertibility == .linear {
            let resolved = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: opioid.name).opioidMMEPerMg
            #expect(
                resolved == opioid.mmePerMg,
                "\(opioid.name): converter \(String(describing: opioid.mmePerMg))× vs resolver \(String(describing: resolved))×",
            )
            compared += 1
        }
        #expect(compared >= 6, "only \(compared) linear opioids compared across the two read paths")
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
    /// tolerance resolver's per-substance read — resolve the same row through different SQL, so where
    /// both return a number they must agree; a divergence means one picked a different source.
    ///
    /// They diverge in exactly one way, on purpose. The resolver's number *raises the tolerance
    /// engine's confidence floor*, so it takes only rows whose value is cited; the converter is a
    /// display and shows every row, marking which are sourced. So the invariant is two-sided: cited
    /// rows agree, and an uncited row is visible in the converter and absent from the resolver.
    @Test
    @MainActor
    func `Both diazepam-equivalence read paths agree where both speak`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        var agreed = 0
        var gated = 0
        for benzo in SubstanceStore.shared.benzoEquivalences() {
            guard let batched = benzo.diazepamPerMg else { continue }
            let resolved = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: benzo.name).diazepamPerMg
            if benzo.equivalent.isCited {
                #expect(resolved == batched, "\(benzo.name): converter \(batched)× vs resolver \(String(describing: resolved))×")
                agreed += 1
            } else {
                #expect(resolved == nil, "\(benzo.name) is uncited and must not reach the engine")
                gated += 1
            }
        }
        #expect(agreed >= 23, "only \(agreed) cited benzos compared across the two read paths")
        #expect(gated > 0, "the citation gate stopped gating anything — check the ingester")
    }
}
