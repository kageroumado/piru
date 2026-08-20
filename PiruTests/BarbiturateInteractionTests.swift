import Foundation
import Testing
@testable import Piru

/// The barbiturate class and methylene blue's MAOI routing, both of which
/// existed only as `.other` — the class that matches no rule at all — until
/// the DrugBank pair scan showed how much they were swallowing.
@Suite("Barbiturate & MAOI class coverage")
struct BarbiturateInteractionTests {
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
    func `Primidone rides the barbiturate class via its phenobarbital metabolite`() {
        #expect(InteractionChecker.drugClasses(for: "Primidone") == [.barbiturate])
    }

    @Test
    func `A barbiturate alias resolves through the override table`() {
        // Overrides are keyed by one spelling; a logged dose may carry any alias.
        for alias in ["Nembutal", "Luminal", "Seconal", "Phenobarb"] {
            #expect(InteractionChecker.drugClasses(for: alias) == [.barbiturate], "\(alias) should resolve")
        }
    }

    @Test
    func `Methylene blue is an MAOI`() {
        #expect(InteractionChecker.drugClasses(for: "Methylene blue") == [.maoi])
    }

    // MARK: - Dangerous pairings

    @Test(arguments: ["Alprazolam", "Morphine", "Alcohol", "GHB", "Secobarbital"])
    func `Barbiturate stacking with another depressant is dangerous`(_ other: String) {
        let results = InteractionChecker.check("Phenobarbital", against: [makeEntry(substance: other)])
        #expect(!results.isEmpty, "Phenobarbital + \(other) returned nothing")
        #expect(results[0].severity == .dangerous, "Phenobarbital + \(other) should be dangerous")
    }

    @Test
    func `Barbiturate plus benzodiazepine outranks benzodiazepine stacking`() {
        // The whole reason barbiturates are not routed into `.benzodiazepine`: the
        // benzo-on-benzo rule is `.unsafe`, and a barbiturate has no such ceiling.
        let barb = InteractionChecker.check("Pentobarbital", against: [makeEntry(substance: "Diazepam")])
        let benzo = InteractionChecker.check("Alprazolam", against: [makeEntry(substance: "Diazepam")])
        #expect(barb.first?.severity == .dangerous)
        #expect(benzo.first?.severity == .unsafe)
        #expect(barb[0].severity > benzo[0].severity)
    }

    // MARK: - Unsafe and caution pairings

    @Test(arguments: [
        ("Pregabalin", InteractionSeverity.unsafe),
        ("Diphenhydramine", InteractionSeverity.unsafe),
        ("Ketamine", InteractionSeverity.unsafe),
        ("Clonidine", InteractionSeverity.caution),
        ("Risperidone", InteractionSeverity.caution),
    ])
    func `Barbiturate pairings carry their expected severity`(_ other: String, _ expected: InteractionSeverity) {
        let results = InteractionChecker.check("Phenobarbital", against: [makeEntry(substance: other)])
        #expect(!results.isEmpty, "Phenobarbital + \(other) returned nothing")
        #expect(results[0].severity == expected, "Phenobarbital + \(other)")
    }

    // MARK: - Methylene blue

    @Test(arguments: ["Sertraline", "Venlafaxine", "Amitriptyline", "MDMA", "Amphetamine"])
    func `Methylene blue plus a serotonergic or stimulant is dangerous`(_ other: String) {
        let results = InteractionChecker.check("Methylene blue", against: [makeEntry(substance: other)])
        #expect(!results.isEmpty, "Methylene blue + \(other) returned nothing")
        #expect(results[0].severity == .dangerous, "Methylene blue + \(other) should be dangerous")
    }
}
