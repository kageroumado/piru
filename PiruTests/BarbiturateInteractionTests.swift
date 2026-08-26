import Foundation
import Testing
@testable import Piru

/// The barbiturate class and methylene blue's MAOI routing, both of which
/// existed only as `.other` — the class that matches no rule at all — until
/// the DrugBank pair scan showed how much they were swallowing.
///
/// What is gated here is that a logged name still *reaches* the class it was
/// given, and that the class ordering the pharmacology demands survives. The
/// severities themselves are rows now, gated with their reasoning in
/// `pipeline/build/tests/test_sqlite.py`; restating them here would only make a
/// second copy that has to be kept in step by hand.
@Suite("Barbiturate & MAOI class coverage")
struct BarbiturateInteractionTests {
    init() async {
        await SubstanceStore.shared.ensureAllLoaded()
    }

    private func makeEntry(substance: String, amount: Double = 100) -> DoseEntry {
        DoseEntry(substance: substance, amount: amount, route: .oral, timestamp: .now)
    }

    // MARK: - Class resolution

    @Test
    func `Barbiturates resolve to the barbiturate class`() {
        for name in [
            "Phenobarbital", "Pentobarbital", "Secobarbital", "Amobarbital",
            "Barbital", "Allobarbital", "Hexobarbital", "Thiopental", "Butalbital",
        ] {
            #expect(InteractionChecker.drugClasses(for: name) == [.barbiturate], "\(name) should be a barbiturate")
        }
    }

    @Test
    func `A barbiturate with no catalog substance still carries its class`() {
        // Butalbital and its neighbours have no `substances` row, so they resolve
        // by literal spelling alone. Nothing else would give them a class, and a
        // barbiturate with no class is invisible to every depressant rule.
        for name in ["Butalbital", "Butabarbital", "Methohexital", "Aprobarbital", "Talbutal"] {
            #expect(SubstanceLibrary.lookup(name) == nil, "\(name) unexpectedly has a catalog row")
            #expect(InteractionChecker.drugClasses(for: name) == [.barbiturate], "\(name) lost its class")
        }
    }

    @Test
    func `Primidone rides the barbiturate class via its phenobarbital metabolite`() {
        #expect(InteractionChecker.drugClasses(for: "Primidone") == [.barbiturate])
    }

    @Test
    func `A barbiturate alias resolves to the same class as its canonical name`() {
        // An override applies to every alias of its substance, so a dose logged
        // under a trade name is classed like the one it was written under.
        for alias in ["Nembutal", "Luminal", "Seconal", "Phenobarb"] {
            #expect(InteractionChecker.drugClasses(for: alias) == [.barbiturate], "\(alias) should resolve")
        }
    }

    @Test
    func `Methylene blue is an MAOI under both of its names`() {
        #expect(InteractionChecker.drugClasses(for: "Methylene blue") == [.maoi])
        #expect(InteractionChecker.drugClasses(for: "Methylthioninium chloride") == [.maoi])
    }

    // MARK: - Ordering invariants

    @Test
    func `Barbiturate plus benzodiazepine outranks benzodiazepine stacking`() {
        // The whole reason barbiturates are not routed into `.benzodiazepine`: a
        // benzodiazepine only modulates GABA-A, so its depression plateaus, while
        // a barbiturate opens the channel directly and keeps going.
        let barb = InteractionChecker.check("Pentobarbital", against: [makeEntry(substance: "Diazepam")])
        let benzo = InteractionChecker.check("Alprazolam", against: [makeEntry(substance: "Diazepam")])
        #expect(!barb.isEmpty && !benzo.isEmpty)
        #expect(barb[0].severity > benzo[0].severity)
    }

    @Test(arguments: ["Alprazolam", "Morphine", "Alcohol", "GHB", "Secobarbital"])
    func `Barbiturate stacking with another depressant is the top warning`(_ other: String) {
        // Not the severity — that the pairing produces a warning at all, and that
        // it is the one shown first. A barbiturate that returns nothing here has
        // fallen back to `.other` again.
        let results = InteractionChecker.check("Phenobarbital", against: [makeEntry(substance: other)])
        #expect(!results.isEmpty, "Phenobarbital + \(other) returned nothing")
        #expect(results[0].prominence == .blocking, "Phenobarbital + \(other) should stop the reader")
    }

    @Test(arguments: ["Pregabalin", "Diphenhydramine", "Ketamine", "Clonidine", "Risperidone"])
    func `Every barbiturate pairing the table covers produces a warning`(_ other: String) {
        let results = InteractionChecker.check("Phenobarbital", against: [makeEntry(substance: other)])
        #expect(!results.isEmpty, "Phenobarbital + \(other) returned nothing")
        #expect(!results[0].description.isEmpty, "Phenobarbital + \(other) warned with no explanation")
    }

    // MARK: - Methylene blue

    @Test(arguments: ["Sertraline", "Venlafaxine", "Amitriptyline", "MDMA", "Amphetamine"])
    func `Methylene blue plus a serotonergic or stimulant warns`(_ other: String) {
        let results = InteractionChecker.check("Methylene blue", against: [makeEntry(substance: other)])
        #expect(!results.isEmpty, "Methylene blue + \(other) returned nothing")
        #expect(results[0].prominence == .blocking, "Methylene blue + \(other) should stop the reader")
    }
}
