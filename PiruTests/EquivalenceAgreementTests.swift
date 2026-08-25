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

    /// The benzo side cannot share one table — the converter parses cited
    /// `diazepam_equivalents` rows from the bundled DB at the user's source
    /// priority, while the tolerance fallback needs a static nonisolated
    /// table. Equivalence tables legitimately disagree (Ashton vs
    /// manufacturer), so this asserts agreement within a ×2 band: tight
    /// enough to catch a typo, a unit swap, or an inverted ratio, loose
    /// enough to survive a data rebuild that switches sources.
    @Test
    @MainActor
    func `Static diazepam factors agree with the bundled DB within 2x`() {
        let dbEquivalences = SubstanceStore.shared.benzoEquivalences()
        guard !dbEquivalences.isEmpty else {
            Issue.record("No diazepam_equivalents rows in the bundled DB")
            return
        }
        var compared = 0
        for benzo in dbEquivalences {
            guard let dbRatio = benzo.diazepamPerMg,
                  let staticRatio = ToleranceStore.gabaDiazepamPerMg[benzo.name.lowercased()]
            else { continue }
            compared += 1
            let drift = staticRatio / dbRatio
            #expect(
                drift >= 0.5 && drift <= 2.0,
                "\(benzo.name): static \(staticRatio)× vs DB \(dbRatio)× diazepam-per-mg",
            )
        }
        // The static table was authored against the DB — if the overlap ever
        // collapses, the test is comparing nothing and must say so.
        #expect(compared >= 10, "only \(compared) benzos overlap between the static table and the DB")
    }
}
