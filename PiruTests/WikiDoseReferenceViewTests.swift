import SwiftUI
import Testing
#if canImport(UIKit)
    import UIKit
#endif
@testable import Piru

@Suite("Wiki dose reference presentation")
@MainActor
struct WikiDoseReferenceViewTests {
    @Test
    func `future source vocabulary remains visible verbatim`() {
        #expect(WikiDoseReferenceLabels.status("future_status") == "future_status")
        #expect(WikiDoseReferenceLabels.confidence(.string("future confidence wording")) == "future confidence wording")
        #expect(WikiDoseReferenceLabels.confidence(.number(0.25)) == "0.25")
        #expect(WikiDoseReferenceLabels.evidence("future_evidence_tier") == "future_evidence_tier")
        #expect(WikiDoseReferenceLabels.access("future_access_context") == "future_access_context")
        #expect(WikiDoseReferenceLabels.status("editorial_hypothesis") == String(localized: "Editorial hypothesis"))
        #expect(WikiDoseReferenceLabels.confidence(.string("very_low")) == String(localized: "Very low"))
        #expect(WikiDoseReferenceLabels.status(nil) == String(localized: "Status not specified"))
        #expect(WikiDoseReferenceLabels.status("") == String(localized: "Status not specified"))
        #expect(WikiDoseReferenceLabels.confidence(nil) == String(localized: "Not specified"))
        #expect(WikiDoseReferenceLabels.confidence(.null) == String(localized: "Not specified"))
        #expect(WikiDoseReferenceLabels.evidence(nil) == nil)
        #expect(WikiDoseReferenceLabels.access("") == nil)
    }

    @Test
    func `unfamiliar prose qualifications stay readable without inventing numbers`() throws {
        let record = try WikiDoseReferenceFixtures.record()
        let observation = try #require(record.model.groups.first?.observations.first)
        let context = WikiDoseReferenceSourceText.additionalProse(observation, excluding: [
            "id", "source_ids", "dose", "population", "route", "chemical_form", "mass_basis",
            "observed_effects", "adverse_effects", "limitations",
        ])
        #expect(context == ["Preserve this qualification"])
        let future: WikiDoseReferenceJSON = .object([
            "context": .object(["prose": .string("Original future caveat"), "unresolved": .null]),
            "unknown_boundary": .number(99),
        ])
        #expect(WikiDoseReferenceSourceText.additionalProse(future, excluding: []) == ["Original future caveat"])
    }

    #if canImport(UIKit)
        @Test
        func `expanded provisional references render and grow with Dynamic Type`() throws {
            var object = WikiDoseReferenceFixtures.model()
            var groups = try #require(object["groups"] as? [[String: Any]])
            groups[0]["kind"] = "provisional_human"
            groups[0]["calculationEligible"] = false
            var bands = try #require(groups[0]["bands"] as? [[String: Any]])
            for index in bands.indices { bands[index]["calculationEligible"] = false }
            groups[0]["bands"] = bands
            object["groups"] = groups
            let group = try #require(WikiDoseReferenceFixtures.record(object).model.groups.first)
            let regular = try #require(image(group: group, size: .large))
            let accessible = try #require(image(group: group, size: .accessibility5))
            #expect(regular.size.width == 390)
            #expect(regular.size.height > 0)
            #expect(accessible.size.width == regular.size.width)
            #expect(accessible.size.height > regular.size.height)
        }

        @Test(arguments: ["unavailable", "withdrawn"])
        func `reference absence and withdrawal render explicitly`(status: String) throws {
            var object = WikiDoseReferenceFixtures.model()
            object["status"] = status
            if status == "unavailable" {
                var groups = try #require(object["groups"] as? [[String: Any]])
                groups[0]["bands"] = [[String: Any]]()
                object["groups"] = groups
            }
            let record = try WikiDoseReferenceFixtures.record(object)
            let renderer = ImageRenderer(content: WikiDoseReferenceContent(record: record).frame(width: 390))
            let image = try #require(renderer.uiImage)
            #expect(image.size.width == 390)
            #expect(image.size.height > 0)
        }

        private func image(group: WikiDoseReferenceGroup, size: DynamicTypeSize) -> UIImage? {
            let content = WikiDoseReferenceGroupContent(group: group)
                .environment(\.dynamicTypeSize, size)
                .frame(width: 390)
                .fixedSize(horizontal: false, vertical: true)
            return ImageRenderer(content: content).uiImage
        }
    #endif
}
