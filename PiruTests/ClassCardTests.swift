import Foundation
import Testing
@testable import Piru

/// The two class cards' pure models. Both resolve from data that is messier than
/// it looks — mixed-case tags, and a reference ladder whose subject may or may
/// not already be on it.
@Suite("Class cards")
@MainActor
struct ClassCardTests {
    // MARK: - Antidepressant class

    @Test
    func `Class tags fold case, because the table holds both SSRI and ssri`() {
        #expect(AntidepressantClass.resolve(tags: ["SSRI"]) == [.ssri])
        #expect(AntidepressantClass.resolve(tags: ["ssri"]) == [.ssri])
        // A substance carrying both casings from two sources resolves once.
        #expect(AntidepressantClass.resolve(tags: ["SSRI", "ssri"]) == [.ssri])
    }

    @Test
    func `Multiple classes come back in declaration order, not tag order`() {
        let resolved = AntidepressantClass.resolve(tags: ["maoi", "SSRI"])
        #expect(resolved == [.ssri, .maoi])
    }

    @Test
    func `Unrelated tags resolve to nothing`() {
        #expect(AntidepressantClass.resolve(tags: ["cathinone", "research-chemical"]).isEmpty)
    }

    @Test
    func `Sertraline resolves as an SSRI from the shipped tags`() throws {
        let sertraline = try #require(SubstanceLibrary.lookup("Sertraline"))
        #expect(AntidepressantClass.resolve(tags: sertraline.tags) == [.ssri])
    }

    @Test
    func `Methamphetamine carries the NDRI tag, which is why the card gates on category`() throws {
        // The tag is mechanistically right and the card must still not appear:
        // an antidepressant-class card frames the compound as something it isn't.
        let meth = try #require(SubstanceLibrary.lookup("Methamphetamine"))
        #expect(AntidepressantClass.resolve(tags: meth.tags) == [.ndri])
        #expect(meth.category != .antidepressant)
        #expect(!meth.extraBrowseCategories.contains(.antidepressant))
    }

    // MARK: - Benzodiazepine duration ladder

    @Test
    func `The ladder ascends and marks exactly the drug whose page it is`() throws {
        let clonazepam = try #require(SubstanceLibrary.lookup("Clonazepam"))
        let rungs = BenzoDurationLadder.rungs(for: clonazepam) { SubstanceLibrary.lookup($0) }
        #expect(rungs.count > 1)
        #expect(rungs.filter { $0.role == .subject }.count == 1)
        #expect(rungs.first { $0.role == .subject }?.name == clonazepam.displayTitle)
        for (earlier, later) in zip(rungs, rungs.dropFirst()) {
            #expect(earlier.halfLifeMinutes <= later.halfLifeMinutes)
        }
    }

    @Test
    func `A reference compound appears once on its own page, not twice`() throws {
        let diazepam = try #require(SubstanceLibrary.lookup("Diazepam"))
        let rungs = BenzoDurationLadder.rungs(for: diazepam) { SubstanceLibrary.lookup($0) }
        #expect(rungs.filter { $0.name == diazepam.displayTitle }.count == 1)
        #expect(rungs.last?.role == .subject)
    }

    @Test
    func `A substance with no half-life gets no ladder, rather than one it isn't on`() throws {
        let subject = try #require(SubstanceLibrary.lookup("Diazepam"))
        let noHalfLife = Substance(
            name: subject.name,
            aliases: [],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [],
            effects: [],
        )
        #expect(noHalfLife.halfLifeMinutes == nil)
        #expect(BenzoDurationLadder.rungs(for: noHalfLife) { SubstanceLibrary.lookup($0) }.isEmpty)
    }

    @Test
    func `Diazepam's nordazepam rung lands above it, which is the whole point`() throws {
        let diazepam = try #require(SubstanceLibrary.lookup("Diazepam"))
        let parent = try #require(diazepam.halfLifeMinutes)
        let model = SubstanceDetailModel()
        model.load(
            substanceName: diazepam.name,
            category: diazepam.category,
            policy: DisclosurePolicy(profile: .pharmaNerd),
        )
        let rungs = BenzoDurationLadder.rungs(for: diazepam, metabolites: model.activeMetabolites) {
            SubstanceLibrary.lookup($0)
        }
        let metabolites = rungs.filter { $0.role == .metabolite }
        #expect(!metabolites.isEmpty)
        // A metabolite rung exists only to say "longer than the parent", so one
        // that doesn't outlast it must never be drawn.
        for rung in metabolites {
            #expect(rung.halfLifeMinutes > parent)
        }
        // Ascending order therefore puts every metabolite after the subject.
        let subjectIndex = try #require(rungs.firstIndex { $0.role == .subject })
        for (index, rung) in rungs.enumerated() where rung.role == .metabolite {
            #expect(index > subjectIndex)
        }
    }
}
