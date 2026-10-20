import Foundation
import Testing
@testable import Piru

@Suite("Published wiki dose reference semantics")
@MainActor
struct WikiDoseReferenceRecordTests {
    @Test(arguments: [
        ("3-Methyl-4-fluoro-α-pyrrolidinovalerophenone", "3-methyl-4-fluoro-pyrrolidinovalerophenone"),
        ("Butylone (βk-MBDB)", "butylone-k-mbdb"),
        ("Δ Fictional é ①", "fictional"),
    ])
    func `source links mirror the fetcher slug exactly`(name: String, slug: String) throws {
        let record = try WikiDoseReferenceRecord(
            id: "fictional", sourceName: name,
            profileSHA256: String(repeating: "a", count: 64), snapshotSHA256: String(repeating: "b", count: 64),
            releaseID: nil, modelJSON: WikiDoseReferenceFixtures.json(WikiDoseReferenceFixtures.model()),
        )
        #expect(record.sourceURL?.absoluteString == "https://substance.wiki/drug/\(slug)")
    }

    @Test
    func `all amount kinds and original text remain distinct`() throws {
        let record = try WikiDoseReferenceFixtures.record()
        let group = try #require(record.model.groups.first)
        #expect(group.bands.map(\.amount.kind) == ["range", "exact", "lower_bound", "upper_bound", "text"])
        #expect(group.bands.map(\.text) == (0 ..< 5).map { "Original amount wording \($0)" })
        #expect(group.bands[0].amount.lower == 1)
        #expect(group.bands[0].amount.upper == 2)
        #expect(group.bands[0].amount.lowerInclusive == nil)
        #expect(group.bands[2].amount.upper == nil)
        #expect(group.bands[2].amount.lowerInclusive == false)
        #expect(group.bands[3].amount.lower == nil)
        #expect(group.bands[3].amount.upperInclusive == true)
        #expect(group.bands[4].amount.lower == nil)
        #expect(group.bands[4].amount.upper == nil)
        #expect(group.bands[4].amount.units == nil)
        #expect(group.bands[4].amount.basis == "unparsed")
    }

    @Test
    func `source context and unknown qualifications survive`() throws {
        let record = try WikiDoseReferenceFixtures.record()
        let group = try #require(record.model.groups.first)
        #expect(record.releaseID == "fictional-release")
        #expect(record.profileSHA256 == String(repeating: "a", count: 64))
        #expect(record.snapshotSHA256 == String(repeating: "b", count: 64))
        #expect(group.formulation == "Fictional formulation")
        #expect(group.materialBasis == "Unspecified chemical form; no conversion")
        #expect(group.populationLimits == "One fictional participant, not a population threshold")
        #expect(group.sources[0].details["lineage"]?.arrayValue?.first?.stringValue == "Independent fictional account")
        #expect(group.sources[0].details["unknown_field"] == .null)
        let observation = try #require(group.observations.first)
        #expect(observation["limitations"]?.arrayValue?.first?.stringValue == "Fictional uncertainty must remain visible")
        #expect(observation["future_qualification"]?["unknown_boundary"] == .null)
        #expect(observation["future_qualification"]?["text"]?.stringValue == "Preserve this qualification")
        #expect(group.bands[0].provenance?["unresolved"] == .null)
        #expect(record.model.reportedAmountDistributions[0]["unresolved"] == .null)
    }

    @Test
    func `eligibility and confidence are never inferred`() throws {
        let group = try #require(WikiDoseReferenceFixtures.record().model.groups.first)
        #expect(group.calculationEligible == nil)
        #expect(group.bands[0].calculationEligible == nil)
        #expect(group.bands[4].calculationEligible == false)
        #expect(group.bands[0].confidence?.stringValue == "very_low")
        #expect(group.bands[1].confidence?.numberValue == 0.25)
        #expect(group.bands[2].confidence == nil)
        #expect(group.bands[0].status == "editorial_hypothesis")
    }

    @Test
    func `withdrawn references cannot display stale content`() throws {
        var object = WikiDoseReferenceFixtures.model()
        object["status"] = "withdrawn"
        // The status must win even when stale content is no longer decodable.
        object["groups"] = "stale unsupported group content"
        let model = try WikiDoseReferenceFixtures.record(object).model
        #expect(model.status == "withdrawn")
        #expect(model.groups.isEmpty)
        #expect(model.reportedAmountDistributions.isEmpty)
        #expect(model.notes == ["Fictional model context"])
    }

    @Test
    func `unavailable references retain context without stale bands`() throws {
        var object = WikiDoseReferenceFixtures.model()
        object["status"] = "unavailable"
        #expect(throws: DecodingError.self) { try WikiDoseReferenceFixtures.record(object) }
        var groups = try #require(object["groups"] as? [[String: Any]])
        groups[0]["bands"] = [[String: Any]]()
        object["groups"] = groups
        let model = try WikiDoseReferenceFixtures.record(object).model
        #expect(model.groups.count == 1)
        #expect(model.groups[0].bands.isEmpty)
        #expect(model.groups[0].materialBasis == "Unspecified chemical form; no conversion")
        #expect(model.reportedAmountDistributions.count == 1)
    }

    @Test
    func `unknown contracts and states fail closed`() throws {
        var object = WikiDoseReferenceFixtures.model()
        object["schemaVersion"] = "drug-community-dose-bands/999"
        #expect(throws: DecodingError.self) { try WikiDoseReferenceFixtures.record(object) }
        object = WikiDoseReferenceFixtures.model()
        object["status"] = "future_state"
        #expect(throws: DecodingError.self) { try WikiDoseReferenceFixtures.record(object) }
    }

    @Test
    func `provisional and fatal entries cannot acquire eligibility`() throws {
        var object = WikiDoseReferenceFixtures.model()
        var groups = try #require(object["groups"] as? [[String: Any]])
        groups[0]["kind"] = "provisional_human"
        groups[0]["calculationEligible"] = false
        var bands = try #require(groups[0]["bands"] as? [[String: Any]])
        for index in bands.indices { bands[index]["calculationEligible"] = false }
        groups[0]["bands"] = bands
        object["groups"] = groups
        let model = try WikiDoseReferenceFixtures.record(object).model
        #expect(model.groups[0].calculationEligible == false)
        #expect(model.groups[0].bands.allSatisfy { $0.calculationEligible == false })
        bands[0]["calculationEligible"] = NSNull()
        groups[0]["bands"] = bands
        object["groups"] = groups
        #expect(throws: DecodingError.self) { try WikiDoseReferenceFixtures.record(object) }

        groups[0]["kind"] = "published_route"
        bands[4]["calculationEligible"] = true
        groups[0]["bands"] = bands
        object["groups"] = groups
        #expect(throws: DecodingError.self) { try WikiDoseReferenceFixtures.record(object) }
    }

    @Test(arguments: ["unknown_kind", "reversed", "invented_unit", "broken_evidence", "broken_confidence", "broken_provenance"])
    func `invalid amounts and unresolved evidence are rejected`(failure: String) throws {
        var object = WikiDoseReferenceFixtures.model()
        var groups = try #require(object["groups"] as? [[String: Any]])
        var bands = try #require(groups[0]["bands"] as? [[String: Any]])
        switch failure {
        case "unknown_kind": bands[0]["amount"] = WikiDoseReferenceFixtures.amount("future_amount")
        case "reversed": bands[0]["amount"] = WikiDoseReferenceFixtures.amount("range", lower: 9, upper: 1)
        case "invented_unit": groups[0]["units"] = "g"
        case "broken_confidence": bands[0]["confidence"] = ["unrecognized": true]
        case "broken_provenance": bands[0]["provenance"] = ["unqualified array"]
        default: bands[0]["sourceObservationIds"] = ["missing-observation"]
        }
        groups[0]["bands"] = bands
        object["groups"] = groups
        #expect(throws: DecodingError.self) { try WikiDoseReferenceFixtures.record(object) }
    }

    @Test
    func `generic metadata round trips nulls and nested values`() throws {
        let original = Data(#"{"null":null,"bool":false,"number":0.25,"array":["qualification",{"nested":null}]}"#.utf8)
        let decoder = JSONDecoder()
        let value = try decoder.decode(WikiDoseReferenceJSON.self, from: original)
        let roundTrip = try decoder.decode(WikiDoseReferenceJSON.self, from: JSONEncoder().encode(value))
        #expect(roundTrip == value)
        #expect(value["null"] == .null)
        #expect(value["bool"]?.boolValue == false)
    }

    @Test(arguments: ["javascript:alert(1)", "piru://journal", "file:///tmp/source", "https://user:secret@example.org/source"])
    func `source links accept only ordinary web addresses`(url: String) throws {
        let json = try WikiDoseReferenceFixtures.json(["id": "source", "title": NSNull(), "url": url, "details": [:]])
        let source = try JSONDecoder().decode(WikiDoseReferenceSource.self, from: Data(json.utf8))
        #expect(source.safeURL == nil)
        #expect(source.title == nil)
        let record = try WikiDoseReferenceFixtures.record()
        #expect(record.model.groups[0].sources[0].safeURL?.absoluteString == "https://example.org/source")
    }
}
