import XCTest
@testable import SubstanceValidator

// MARK: - Monotonicity

final class MonotonicityCheckTests: XCTestCase {
    func testMonotonicLadderPasses() {
        let route = AuditRoute(
            route: "oral",
            unit: "mg",
            doses: AuditDoseRange(
                threshold: 5,
                light: AuditCodableRange(lower: 10, upper: 20),
                common: AuditCodableRange(lower: 20, upper: 40),
                strong: AuditCodableRange(lower: 40, upper: 80),
                heavy: 100
            )
        )
        let s = AuditSubstance(name: "Test", category: "Stimulant", defaultRoute: "oral", routes: [route])
        XCTAssertEqual(MonotonicityCheck.check(substance: s, route: route).count, 0)
    }

    func testInvertedRangeFails() {
        // light upper (40) overshoots common lower (20).
        let route = AuditRoute(
            route: "oral",
            unit: "mg",
            doses: AuditDoseRange(
                threshold: 5,
                light: AuditCodableRange(lower: 10, upper: 40),
                common: AuditCodableRange(lower: 20, upper: 30),
                strong: AuditCodableRange(lower: 30, upper: 80),
                heavy: 100
            )
        )
        let s = AuditSubstance(name: "Test", category: "Stimulant", defaultRoute: "oral", routes: [route])
        let findings = MonotonicityCheck.check(substance: s, route: route)
        XCTAssertGreaterThan(findings.count, 0)
        XCTAssertTrue(findings.allSatisfy { $0.severity == .error })
        XCTAssertTrue(findings.contains { $0.detail.contains("common.lower") && $0.detail.contains("light.upper") })
    }

    func testNilsAreSkipped() {
        // Only threshold + heavy populated; everything else nil.
        let route = AuditRoute(
            route: "oral",
            unit: "mg",
            doses: AuditDoseRange(threshold: 10, heavy: 200)
        )
        let s = AuditSubstance(name: "Test", category: "Opioid", defaultRoute: "oral", routes: [route])
        XCTAssertEqual(MonotonicityCheck.check(substance: s, route: route).count, 0)
    }

    func testCompletelyEmptyDoseIsFine() {
        let route = AuditRoute(route: "oral", unit: "mg", doses: AuditDoseRange())
        let s = AuditSubstance(name: "Test", category: "Other", defaultRoute: "oral", routes: [route])
        XCTAssertEqual(MonotonicityCheck.check(substance: s, route: route).count, 0)
    }
}

// MARK: - Plausibility

final class PlausibilityCheckTests: XCTestCase {
    func testAlcoholAtSixtyGramsPasses() {
        let route = AuditRoute(
            route: "oral",
            unit: "g",
            doses: AuditDoseRange(threshold: 10, heavy: 60)
        )
        let alcohol = AuditSubstance(
            name: "Alcohol",
            aliases: ["ethanol"],
            category: "Depressant",
            defaultRoute: "oral",
            routes: [route]
        )
        XCTAssertEqual(PlausibilityCheck.check(substance: alcohol, route: route).count, 0)
    }

    func testStimulantInGramsTripsUnitMismatch() {
        // Stimulant + oral accepts {mg, µg}. A stimulant labeled in `g` is
        // therefore outside the acceptable list and trips the unit-mismatch
        // warning. (Depressant accepts {mg, g, µg} — alcohol mislabeled as
        // mg can't be caught at the category level anymore; the ground-truth
        // check covers that specific case via the alcohol entry.)
        let route = AuditRoute(
            route: "oral",
            unit: "g", // way wrong for a stimulant
            doses: AuditDoseRange(threshold: 0.1, heavy: 1)
        )
        let s = AuditSubstance(
            name: "TestStim",
            category: "Stimulant",
            defaultRoute: "oral",
            routes: [route]
        )
        let findings = PlausibilityCheck.check(substance: s, route: route)
        XCTAssertTrue(
            findings.contains { $0.detail.contains("verify not a unit-conversion slip") },
            "Stimulant in `g` should trip the unit-mismatch warning"
        )
    }

    func testAlcoholInMilligramsCaughtByGroundTruth() {
        // Confirms the architecture: Depressant + oral now accepts mg/g/µg
        // so alcohol-in-mg isn't a plausibility unit-mismatch hit anymore.
        // The protection moved to GroundTruthCheck, which compares against
        // the 60 g reference value (~6e4 mg) and fires an ERROR.
        let route = AuditRoute(
            route: "oral",
            unit: "mg",
            doses: AuditDoseRange(threshold: 1, heavy: 10)
        )
        let alcohol = AuditSubstance(
            name: "Alcohol",
            aliases: ["ethanol"],
            category: "Depressant",
            defaultRoute: "oral",
            routes: [route]
        )
        // No plausibility unit-mismatch — that's by design now.
        let plausibility = PlausibilityCheck.check(substance: alcohol, route: route)
        XCTAssertFalse(
            plausibility.contains { $0.detail.contains("verify not a unit-conversion slip") },
            "Depressant accepts mg, so unit-mismatch shouldn't fire"
        )
        // Ground-truth catches it.
        let groundTruth = GroundTruthCheck.run([alcohol])
        XCTAssertTrue(
            groundTruth.contains { $0.severity == .error && $0.substance.lowercased() == "alcohol" },
            "Alcohol at 10 mg vs 60 g reference should fire a ground-truth ERROR"
        )
    }

    func testStimulantWayOutOfRangeFlagsError() {
        // 5000 mg heavy oral stimulant = 10× over the 500 mg bound → ERROR.
        let route = AuditRoute(
            route: "oral",
            unit: "mg",
            doses: AuditDoseRange(heavy: 50_000)
        )
        let s = AuditSubstance(name: "Test", category: "Stimulant", defaultRoute: "oral", routes: [route])
        let findings = PlausibilityCheck.check(substance: s, route: route)
        XCTAssertTrue(findings.contains { $0.severity == .error })
    }

    func testRouteWithoutBoundProducesNoFinding() {
        // No table row for Nootropic + oral, so the check skips silently.
        let route = AuditRoute(route: "oral", unit: "mg", doses: AuditDoseRange(heavy: 1))
        let s = AuditSubstance(name: "Piracetam", category: "Nootropic", defaultRoute: "oral", routes: [route])
        XCTAssertEqual(PlausibilityCheck.check(substance: s, route: route).count, 0)
    }
}

// MARK: - Ground truth

final class GroundTruthCheckTests: XCTestCase {
    func testInRangeProducesNoFinding() {
        // MDMA 180 mg heavy is within 200 ±30% = [140, 260].
        let route = AuditRoute(
            route: "oral",
            unit: "mg",
            doses: AuditDoseRange(heavy: 180)
        )
        let mdma = AuditSubstance(name: "MDMA", category: "Empathogen", defaultRoute: "oral", routes: [route])
        let findings = GroundTruthCheck.run([mdma])
        XCTAssertFalse(findings.contains { $0.substance.lowercased() == "mdma" })
    }

    func testOutOfRangeFiresError() {
        // MDMA 50 mg heavy is well below 200 ±30%.
        let route = AuditRoute(
            route: "oral",
            unit: "mg",
            doses: AuditDoseRange(heavy: 50)
        )
        let mdma = AuditSubstance(name: "MDMA", category: "Empathogen", defaultRoute: "oral", routes: [route])
        let findings = GroundTruthCheck.run([mdma])
        let mdmaFindings = findings.filter { $0.substance.lowercased() == "mdma" }
        XCTAssertEqual(mdmaFindings.count, 1)
        XCTAssertEqual(mdmaFindings.first?.severity, .error)
    }

    func testMissingHeavyFiresWarning() {
        // MDMA route present but heavy omitted → ground-truth warning.
        let route = AuditRoute(
            route: "oral",
            unit: "mg",
            doses: AuditDoseRange(threshold: 30, common: AuditCodableRange(lower: 100, upper: 150))
        )
        let mdma = AuditSubstance(name: "MDMA", category: "Empathogen", defaultRoute: "oral", routes: [route])
        let findings = GroundTruthCheck.run([mdma])
        let mdmaFindings = findings.filter { $0.substance.lowercased() == "mdma" }
        XCTAssertEqual(mdmaFindings.count, 1)
        XCTAssertEqual(mdmaFindings.first?.severity, .warning)
    }

    func testAliasMatchWorks() {
        // Match by alias "ethanol" instead of canonical name "alcohol".
        let route = AuditRoute(
            route: "oral",
            unit: "g",
            doses: AuditDoseRange(heavy: 5) // way below the 60 g ground-truth → error
        )
        let s = AuditSubstance(
            name: "Ethanol",
            aliases: ["alcohol"],
            category: "Depressant",
            defaultRoute: "oral",
            routes: [route]
        )
        let findings = GroundTruthCheck.run([s])
        XCTAssertTrue(findings.contains { $0.severity == .error })
    }
}
