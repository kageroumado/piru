import Foundation
import Testing
@testable import Piru

/// The two class cards' pure models. Both resolve from data that is messier than it looks — a
/// curated class column whose casing is the DB's and whose vocabulary is wider than the card's, and
/// a reference ladder whose subject may or may not already be on it.
@Suite("Class cards")
@MainActor
struct ClassCardTests {
    /// The ladder's rungs are `class_reference_compounds` rows now, so every ladder test needs the
    /// store up. A rung list that came back empty would make each of them pass vacuously, which is
    /// why the count is gated once here rather than asserted per test.
    private let references: [String]

    init() {
        references = SubstanceStore.shared.benzoLadderReferenceNames()
    }

    @Test
    func `The ladder has its reference compounds`() {
        #expect(references.count == 6, "expected 6 ladder rungs, found \(references.count)")
        // Ordered shortest-acting first: the ladder is drawn in that order and a
        // curated rank that inverted would draw it upside down.
        let halfLives = references.compactMap { SubstanceLibrary.lookup($0)?.halfLifeMinutes }
        #expect(halfLives.count == references.count)
        for (earlier, later) in zip(halfLives, halfLives.dropFirst()) {
            #expect(earlier <= later)
        }
    }

    // MARK: - Antidepressant class

    @Test
    func `The curated column's casing is the DB's, so resolution folds it`() {
        #expect(AntidepressantClass.resolve(drugClass: .init(value: "SSRI", isContested: false)) == .ssri)
        #expect(AntidepressantClass.resolve(drugClass: .init(value: "NaSSA", isContested: true)) == .nassa)
        #expect(AntidepressantClass.resolve(drugClass: nil) == nil)
    }

    /// These four are curated classes with no case here on purpose — the card lists a class against
    /// its family, and none of them is a point on the monoamine axis the family compares along.
    @Test
    func `The classes that are departures from the axis carry no card`() {
        for departure in ["MELATONERGIC", "NEUROSTEROID", "OPIOIDERGIC", "ATYPICAL"] {
            #expect(AntidepressantClass.resolve(drugClass: .init(value: departure, isContested: false)) == nil)
        }
    }

    /// The curated column exists because the tags disagree with it on exactly the compounds where
    /// precision matters. Each of these is a substance whose tag names the wrong class.
    @Test
    func `The curated column outranks the tags where they disagree`() {
        let store = SubstanceStore.shared
        #expect(AntidepressantClass.resolve(drugClass: store.drugClass(forName: "Atomoxetine")) == .nri)
        #expect(AntidepressantClass.resolve(drugClass: store.drugClass(forName: "Maprotiline")) == .nri)
        #expect(AntidepressantClass.resolve(drugClass: store.drugClass(forName: "Vortioxetine")) == .sms)
        #expect(AntidepressantClass.resolve(drugClass: store.drugClass(forName: "Vilazodone")) == .sms)
        #expect(AntidepressantClass.resolve(drugClass: store.drugClass(forName: "Sertraline")) == .ssri)
    }

    /// Every curated value either resolves to a case or is one of the four deliberate departures.
    /// A new value appearing in the column with neither would silently show no card at all.
    @Test
    func `Every curated drug class is accounted for`() {
        let departures: Set = ["melatonergic", "neurosteroid", "opioidergic", "atypical"]
        let classes = SubstanceReadModel.drugClasses(db: SubstanceStore.shared.substancesDB)
        #expect(!classes.isEmpty)
        for (name, curated) in classes {
            #expect(
                AntidepressantClass(rawValue: curated.value.lowercased()) != nil
                    || departures.contains(curated.value.lowercased()),
                "\(name) carries an unaccounted drug_class \(curated.value)",
            )
        }
    }

    /// The hedge is the reason `drug_class_ambiguous` exists, so it has to reach a substance that
    /// carries it and stay off one that doesn't.
    @Test
    func `A contested classification is marked, a settled one is not`() {
        let store = SubstanceStore.shared
        #expect(store.drugClass(forName: "Bupropion")?.isContested == true)
        #expect(store.drugClass(forName: "Mirtazapine")?.isContested == true)
        #expect(store.drugClass(forName: "Sertraline")?.isContested == false)
        #expect(store.drugClass(forName: "Fluoxetine")?.isContested == false)
    }

    @Test
    func `Methamphetamine carries the NDRI tag, which is why the card gates on category`() throws {
        // The tag is mechanistically right and the card must still not appear: an
        // antidepressant-class card frames the compound as something it isn't. The curated column
        // leaves it empty, and the category gate is the second guard.
        let meth = try #require(SubstanceLibrary.resolveFull("Methamphetamine"))
        #expect(SubstanceStore.shared.drugClass(forName: meth.name) == nil)
        #expect(meth.category != .antidepressant)
        #expect(!meth.extraBrowseCategories.contains(.antidepressant))
    }

    // MARK: - Benzodiazepine duration ladder

    @Test
    func `The ladder ascends and marks exactly the drug whose page it is`() throws {
        let clonazepam = try #require(SubstanceLibrary.resolveFull("Clonazepam"))
        let rungs = BenzoDurationLadder.rungs(for: clonazepam, references: references) { SubstanceLibrary.resolveFull($0) }
        #expect(rungs.count > 1)
        #expect(rungs.filter { $0.role == .subject }.count == 1)
        #expect(rungs.first { $0.role == .subject }?.name == clonazepam.displayTitle)
        for (earlier, later) in zip(rungs, rungs.dropFirst()) {
            #expect(earlier.halfLifeMinutes <= later.halfLifeMinutes)
        }
    }

    @Test
    func `A reference compound appears once on its own page, not twice`() throws {
        let diazepam = try #require(SubstanceLibrary.resolveFull("Diazepam"))
        let rungs = BenzoDurationLadder.rungs(for: diazepam, references: references) { SubstanceLibrary.resolveFull($0) }
        #expect(rungs.filter { $0.name == diazepam.displayTitle }.count == 1)
        #expect(rungs.last?.role == .subject)
    }

    @Test
    func `A substance with no half-life gets no ladder, rather than one it isn't on`() throws {
        let subject = try #require(SubstanceLibrary.resolveFull("Diazepam"))
        let noHalfLife = Substance(
            name: subject.name,
            aliases: [],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [],
            effects: [],
        )
        #expect(noHalfLife.halfLifeMinutes == nil)
        #expect(BenzoDurationLadder.rungs(for: noHalfLife, references: references) { SubstanceLibrary.resolveFull($0) }.isEmpty)
    }

    @Test
    func `Diazepam's nordazepam rung lands above it, which is the whole point`() throws {
        let diazepam = try #require(SubstanceLibrary.resolveFull("Diazepam"))
        let parent = try #require(diazepam.halfLifeMinutes)
        let model = SubstanceDetailModel()
        model.load(
            substanceName: diazepam.name,
            category: diazepam.category,
            policy: DisclosurePolicy(profile: .pharmaNerd),
        )
        let rungs = BenzoDurationLadder.rungs(
            for: diazepam,
            metabolites: model.activeMetabolites,
            references: references,
        ) {
            SubstanceLibrary.resolveFull($0)
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

/// A preparation borrowing its molecule's pharmacology. Cannabis is the case
/// that forced it: it shipped a CB1 Kᵢ and intrinsic activity that were THC's,
/// under a citation resolving to a nursing-ethics bibliography, and the CB1
/// ladder drew one molecule twice as a result.
@Suite("Active ingredient")
@MainActor
struct ActiveIngredientTests {
    /// The mapping is installed from `substances.active_ingredient_substance_id` at index build, so
    /// this suite needs the store up rather than relying on another suite having warmed it.
    init() {
        _ = SubstanceStore.shared
    }

    @Test
    func `Cannabis resolves to THC, and almost nothing else resolves at all`() {
        #expect(ActiveIngredient.resolve("Cannabis") == "THC")
        #expect(ActiveIngredient.resolve("cannabis") == "THC") // case-folded
        #expect(ActiveIngredient.resolve("THC") == nil) // no self-reference
        #expect(ActiveIngredient.resolve("MDMA") == nil)
        // Ayahuasca is deliberately absent: its effect is the DMT × MAOI
        // interaction, so no single molecule's rows could stand for it.
        #expect(ActiveIngredient.resolve("Ayahuasca") == nil)
    }

    @Test
    func `pharmacologyName falls through for an ordinary substance`() {
        #expect(ActiveIngredient.pharmacologyName(for: "MDMA") == "MDMA")
        #expect(ActiveIngredient.pharmacologyName(for: "Cannabis") == "THC")
    }

    @Test
    func `Cannabis carries no binding rows of its own any more`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { tearDownIsolatedSubstanceStore(store, tempDir: tempDir) }
        // Read by id, bypassing the ActiveIngredient hop, so this asserts the DB
        // and not the proxy. The rows it used to carry were THC's (CB1/CB2,
        // "Original Felder/Showalter measurement") and CBD's (GPR55) — a plant
        // has no Kᵢ.
        let cannabisID = try #require(store.substanceID(forNameOrAlias: "Cannabis"))
        #expect(SubstanceReadModel.bindingRows(substanceID: cannabisID, db: store.substancesDB).isEmpty)
    }

    @Test
    func `Cannabis reads THC's bindings through the store`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { tearDownIsolatedSubstanceStore(store, tempDir: tempDir) }
        let viaCannabis = store.bindings(forSubstanceName: "Cannabis")
        let viaTHC = store.bindings(forSubstanceName: "THC")
        #expect(!viaCannabis.isEmpty)
        #expect(viaCannabis.map(\.id) == viaTHC.map(\.id))
    }

    @Test
    func `The CB1 ladder no longer draws the same molecule twice`() {
        let legs = SubstanceStore.shared.signatureLegs(family: .cannabinoid1)
        guard case let .efficacy(model)? = ClassSignature.resolve(
            substanceName: ActiveIngredient.pharmacologyName(for: "Cannabis"),
            category: .cannabinoid, legs: legs,
        ) else {
            Issue.record("Cannabis lost the CB1 efficacy axis it borrows from THC")
            return
        }
        // The focus is the molecule, and Cannabis appears nowhere on the axis:
        // 25 % (mislabelled) sitting beside 36.1 % (correct) read as two drugs.
        #expect(model.focus.name == "THC")
        #expect(!model.marks.contains { $0.name == "Cannabis" })
    }
}
