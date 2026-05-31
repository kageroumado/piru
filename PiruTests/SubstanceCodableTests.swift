import Foundation
import Testing
@testable import Piru

@Suite("Substance Codable")
struct SubstanceCodableTests {
    // MARK: - CodableRange

    @Test
    func `CodableRange converts to and from ClosedRange`() {
        let cr = CodableRange(10.5 ... 20.0)
        #expect(cr.lower == 10.5)
        #expect(cr.upper == 20.0)
        #expect(cr.closedRange == 10.5 ... 20.0)
    }

    // MARK: - DoseRange

    @Test
    func `DoseRange round-trips through JSON`() throws {
        let original = DoseRange(
            threshold: 5,
            light: 10 ... 20,
            common: 20 ... 40,
            strong: 40 ... 80,
            heavy: 80,
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DoseRange.self, from: data)
        #expect(decoded.threshold == 5)
        #expect(decoded.light == 10 ... 20)
        #expect(decoded.common == 20 ... 40)
        #expect(decoded.strong == 40 ... 80)
        #expect(decoded.heavy == 80)
    }

    @Test
    func `DoseRange with nil ranges round-trips`() throws {
        let original = DoseRange(
            threshold: nil, light: nil, common: 10 ... 20,
            strong: nil, heavy: nil,
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DoseRange.self, from: data)
        #expect(decoded.common == 10 ... 20)
        #expect(decoded.light == nil)
        #expect(decoded.threshold == nil)
        #expect(decoded.heavy == nil)
    }

    // MARK: - Single Substance

    @Test
    func `Substance round-trips through JSON`() throws {
        let original = Substance(
            name: "TestSubstance",
            aliases: ["TS", "TestS"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10 ... 20, common: 20 ... 40,
                    strong: 40 ... 80, heavy: 80,
                ), duration: DurationProfile(
                    onset: DurationRange(min: 15, max: 30),
                    comeup: DurationRange(min: 10, max: 20),
                    peak: DurationRange(min: 60, max: 120),
                    offset: DurationRange(min: 30, max: 60),
                    afterglow: nil,
                    total: DurationRange(min: 180, max: 300),
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5 ... 10, common: 10 ... 20,
                    strong: 20 ... 40, heavy: 40,
                )),
            ],
            effects: ["Focus", "Energy"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Focus", description: "Sharp concentration"),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 300,
            sources: ["PubMed"],
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Substance.self, from: data)

        #expect(decoded.name == "TestSubstance")
        #expect(decoded.aliases == ["TS", "TestS"])
        #expect(decoded.category == .stimulant)
        #expect(decoded.defaultRoute == .oral)
        #expect(decoded.routes.count == 2)
        #expect(decoded.routes[0].doses.light == 10 ... 20)
        #expect(decoded.routes[0].duration?.onset?.min == 15)
        #expect(decoded.routes[1].route == .insufflation)
        #expect(decoded.effects == ["Focus", "Energy"])
        #expect(decoded.subjectiveEffects.count == 1)
        #expect(decoded.toleranceInfo?.buildRate == "rapid")
        #expect(decoded.halfLifeMinutes == 300)
        #expect(decoded.sources == ["PubMed"])
        // id is regenerated, not preserved
        #expect(decoded.id != original.id)
    }

    @Test
    func `Substance with minimal fields round-trips`() throws {
        let original = Substance(
            name: "Minimal",
            aliases: [],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: nil, light: nil, common: 10 ... 20,
                    strong: nil, heavy: nil,
                )),
            ],
            effects: ["Effect"],
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Substance.self, from: data)

        #expect(decoded.name == "Minimal")
        #expect(decoded.subjectiveEffects.isEmpty)
        #expect(decoded.toleranceInfo == nil)
        #expect(decoded.halfLifeMinutes == nil)
        #expect(decoded.sources.isEmpty)
    }

    // MARK: - Full Library

    @Test
    func `Full library encodes without error`() throws {
        let data = try JSONEncoder().encode(SubstanceLibrary.all)
        #expect(data.count > 0)
    }

    @Test
    func `Full library round-trips with same count and names`() throws {
        let data = try JSONEncoder().encode(SubstanceLibrary.all)
        let decoded = try JSONDecoder().decode([Substance].self, from: data)
        #expect(decoded.count == SubstanceLibrary.all.count)

        let originalNames = Set(SubstanceLibrary.all.map(\.name))
        let decodedNames = Set(decoded.map(\.name))
        #expect(originalNames == decodedNames)
    }
}
