import Foundation
import GRDB
import Testing
@testable import Piru

/// "Limited data" is a claim about how much is known about the **molecule**, not
/// about how many rows Piru ingested. That makes it false for anything approved
/// or over-the-counter however thin the catalog entry is, so the badge and the
/// detail banner both gate on `CompoundDisplayClass.mayReportLimitedData` before
/// they consult `isStub`.
@Suite("Limited-data label")
struct LimitedDataLabelTests {
    @Test
    func `Only recreational and dual-use compounds may be called limited`() {
        #expect(CompoundDisplayClass.recreational.mayReportLimitedData)
        #expect(CompoundDisplayClass.dualUse.mayReportLimitedData)
        for approved: CompoundDisplayClass in [.otc, .medicalRx, .nonRecreational] {
            #expect(!approved.mayReportLimitedData, "\(approved.rawValue) is an approved drug")
        }
    }

    @Test
    @MainActor
    func `No approved or OTC substance in the bundled DB can show the label`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let stubbedApproved = try await SubstanceStore.shared.substancesDB.read { db in
            try String.fetchAll(db, sql: """
                SELECT canonical_name FROM substances
                 WHERE is_stub = 1 AND display_class IN ('otc', 'medical_rx', 'non_recreational')
                 ORDER BY popularity DESC LIMIT 20
            """)
        }
        // The build flags hundreds of these — atorvastatin, omeprazole, calcium,
        // testosterone. The flag is fine; what it must not do is reach the label.
        #expect(!stubbedApproved.isEmpty, "expected the bundled DB to carry thin approved entries")
        for name in stubbedApproved {
            guard let substance = SubstanceStore.shared.lookup(name) else { continue }
            #expect(
                !substance.displayClass.mayReportLimitedData,
                "\(name) is approved/OTC and must never be badged limited",
            )
        }
    }
}
