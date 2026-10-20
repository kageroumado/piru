import Foundation
@testable import Piru

/// Fictional source data exercises preservation without asserting scientific
/// dose values or changing the published catalog when a test runs.
@MainActor
enum WikiDoseReferenceFixtures {
    static func model() -> [String: Any] {
        let amounts: [[String: Any]] = [
            amount("range", lower: 1, upper: 2),
            amount("exact", lower: 3, upper: 3),
            amount("lower_bound", lower: 4, lowerInclusive: false),
            amount("upper_bound", upper: 5, upperInclusive: true),
            amount("text"),
        ]
        let bands: [[String: Any]] = amounts.enumerated().map { index, amount in
            let confidence: Any = switch index {
            case 0: "very_low"
            case 1: 0.25
            default: NSNull()
            }
            let eligibility: Any = index == 4 ? false : NSNull()
            return [
                "id": "band-\(index)", "band": index == 4 ? "fatal" : "fixture-\(index)",
                "label": "Fictional source label \(index)", "text": "Original amount wording \(index)",
                "amount": amount, "status": "editorial_hypothesis",
                "confidence": confidence,
                "sourceIds": ["source-1"], "sourceObservationIds": ["observation-1"],
                "notes": ["The band is a fictional hypothesis."],
                "calculationEligible": eligibility,
                "provenance": ["basis": "Fictional interpolation", "unresolved": NSNull()],
            ]
        }
        return [
            "schemaVersion": "drug-community-dose-bands/1", "status": "available",
            "notes": ["Fictional model context"], "warnings": ["Fictional model warning"],
            "reportedAmountDistributions": [["kind": "separate_observation", "unresolved": NSNull()]],
            "groups": [[
                "id": "group-1", "kind": "published_route", "sourcePath": "/fictional/path",
                "route": "oral", "units": "mg", "formulation": "Fictional formulation",
                "materialBasis": "Unspecified chemical form; no conversion",
                "populationLimits": "One fictional participant, not a population threshold",
                "notes": ["Fictional group context"], "warnings": ["Fictional group warning"],
                "calculationEligible": NSNull(),
                "sources": [[
                    "id": "source-1", "title": "Fictional primary source",
                    "url": "https://example.org/source",
                    "details": ["lineage": ["Independent fictional account"], "unknown_field": NSNull()],
                ]],
                "observations": [[
                    "id": "observation-1", "source_ids": ["source-1"],
                    "dose": ["text": "Original observation wording", "min": NSNull()],
                    "population": "One fictional participant", "route": "oral",
                    "chemical_form": "Unspecified", "mass_basis": "No conversion",
                    "observed_effects": ["Fictional reported effect"],
                    "adverse_effects": ["Fictional reported adverse effect"],
                    "limitations": ["Fictional uncertainty must remain visible"],
                    "future_qualification": ["unknown_boundary": NSNull(), "text": "Preserve this qualification"],
                ]],
                "bands": bands,
            ]],
        ]
    }

    static func amount(
        _ kind: String, lower: Double? = nil, upper: Double? = nil,
        lowerInclusive: Bool? = nil, upperInclusive: Bool? = nil,
    ) -> [String: Any] {
        [
            "kind": kind, "lower": lower as Any? ?? NSNull(), "upper": upper as Any? ?? NSNull(),
            "lowerInclusive": lowerInclusive as Any? ?? NSNull(), "upperInclusive": upperInclusive as Any? ?? NSNull(),
            "units": kind == "text" ? NSNull() : "mg", "basis": kind == "text" ? "unparsed" : "source_numeric",
        ]
    }

    static func json(_ object: [String: Any]) throws -> String {
        try String(decoding: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }

    static func record(_ object: [String: Any]? = nil, id: String = "fixture-profile") throws -> WikiDoseReferenceRecord {
        try WikiDoseReferenceRecord(
            id: id, sourceName: "Fictional compound", profileSHA256: String(repeating: "a", count: 64),
            snapshotSHA256: String(repeating: "b", count: 64), releaseID: "fictional-release",
            modelJSON: json(object ?? model()),
        )
    }
}
