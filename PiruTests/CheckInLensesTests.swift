import Foundation
import Testing
@testable import Piru

/// Which questions a check-in asks, given what is in the session.
@Suite("CheckInLenses")
struct CheckInLensesTests {
    @Test
    func `A medication is asked whether it worked, a psychedelic how strong it is`() {
        let stimulant = CheckInLenses.lenses(for: .stimulant)
        #expect(stimulant.worked)
        #expect(!stimulant.intensity)

        let psychedelic = CheckInLenses.lenses(for: .psychedelic)
        #expect(psychedelic.intensity)
        #expect(!psychedelic.worked)
    }

    @Test
    func `Every class offers side effects to check, and none offers them all`() {
        for category in SubstanceCategory.allCases {
            let lenses = CheckInLenses.lenses(for: category)
            #expect(!lenses.sideEffects.isEmpty, "\(category.rawValue) offers nothing to check")
            #expect(lenses.worked || lenses.intensity, "\(category.rawValue) asks neither question")
            #expect(lenses.sideEffects.count <= 10, "\(category.rawValue) offers too many at once")
            #expect(Set(lenses.sideEffects).count == lenses.sideEffects.count)
            #expect(Set(lenses.highlights).count == lenses.highlights.count)
            // A slug cannot be both the thing you took it for and a side effect.
            #expect(Set(lenses.highlights).isDisjoint(with: Set(lenses.sideEffects)))
        }
    }

    @Test
    func `Sociability is asked where people take the drug for company`() {
        #expect(CheckInLenses.lenses(for: .empathogen).social)
        #expect(CheckInLenses.lenses(for: .stimulant).social)
        #expect(!CheckInLenses.lenses(for: .psychedelic).social)
        #expect(!CheckInLenses.lenses(for: .opioid).social)
    }

    @Test
    func `The split classes each ask their own questions`() {
        let benzo = CheckInLenses.lenses(for: .benzodiazepine)
        let gaba = CheckInLenses.lenses(for: .gabapentinoid)
        #expect(benzo.sideEffects != gaba.sideEffects)
        #expect(benzo.sideEffects.contains("amnesia"))
        #expect(gaba.sideEffects.contains("blurred-vision"))

        let deliriant = CheckInLenses.lenses(for: .deliriant)
        let dysdelic = CheckInLenses.lenses(for: .dysdelic)
        let psychedelic = CheckInLenses.lenses(for: .psychedelic)
        #expect(deliriant.sideEffects != psychedelic.sideEffects)
        #expect(dysdelic.sideEffects != psychedelic.sideEffects)
        // Nobody takes a deliriant *for* something; a row of pleasant effects
        // would be an invitation the pharmacology does not support.
        #expect(deliriant.highlights.isEmpty)
        #expect(deliriant.sideEffects.contains("complex-visual-hallucination"))
    }

    @Test
    func `Reassurance exists for what frightens people and nothing else`() {
        #expect(CheckInLenses.reassurance(for: "anxiety") != nil)
        #expect(CheckInLenses.reassurance(for: "palpitations") != nil)
        #expect(CheckInLenses.reassurance(for: "itching") != nil)
        // A dry mouth needs no reassuring.
        #expect(CheckInLenses.reassurance(for: "dry-mouth") == nil)
        #expect(CheckInLenses.reassurance(for: "not-a-slug") == nil)
    }

    // MARK: - The form

    @Test
    func `One substance needs no name tag; two do`() {
        var single = CheckInForm(asksWorked: true, workedNames: ["Dexamfetamine"], distinctSubstances: 1)
        #expect(single.tag(single.workedNames) == nil)

        single.distinctSubstances = 2
        single.asksIntensity = true
        single.intensityNames = ["LSD"]
        #expect(single.tag(single.workedNames) == "Dexamfetamine")
        #expect(single.tag(single.intensityNames) == "LSD")
    }

    @Test
    func `A session that resolves nothing widens the questions rather than narrowing them`() {
        let form = CheckInForm.unresolved
        #expect(form.asksIntensity)
        #expect(form.showsMood)
        #expect(form.showsEnergy)
    }
}
