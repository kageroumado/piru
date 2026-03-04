import Testing
@testable import Piru

@Suite("SubstanceCategory")
struct SubstanceCategoryTests {

    // MARK: - TripSit category mapping

    @Test("Maps stimulant")
    func stimulant() {
        #expect(SubstanceCategory.from(tripSitCategory: "stimulant") == .stimulant)
    }

    @Test("Maps psychedelic and hallucinogen")
    func psychedelic() {
        #expect(SubstanceCategory.from(tripSitCategory: "psychedelic") == .psychedelic)
        #expect(SubstanceCategory.from(tripSitCategory: "hallucinogen") == .psychedelic)
    }

    @Test("Maps dissociative")
    func dissociative() {
        #expect(SubstanceCategory.from(tripSitCategory: "dissociative") == .dissociative)
    }

    @Test("Maps opioid and opiate")
    func opioid() {
        #expect(SubstanceCategory.from(tripSitCategory: "opioid") == .opioid)
        #expect(SubstanceCategory.from(tripSitCategory: "opiate") == .opioid)
    }

    @Test("Maps benzodiazepine")
    func benzodiazepine() {
        #expect(SubstanceCategory.from(tripSitCategory: "benzodiazepine") == .benzodiazepine)
    }

    @Test("Maps depressant variants")
    func depressant() {
        #expect(SubstanceCategory.from(tripSitCategory: "depressant") == .depressant)
        #expect(SubstanceCategory.from(tripSitCategory: "barbiturate") == .depressant)
        #expect(SubstanceCategory.from(tripSitCategory: "sedative") == .depressant)
    }

    @Test("Maps empathogen and entactogen")
    func empathogen() {
        #expect(SubstanceCategory.from(tripSitCategory: "empathogen") == .empathogen)
        #expect(SubstanceCategory.from(tripSitCategory: "entactogen") == .empathogen)
    }

    @Test("Maps cannabinoid")
    func cannabinoid() {
        #expect(SubstanceCategory.from(tripSitCategory: "cannabinoid") == .cannabinoid)
    }

    @Test("Maps nootropic")
    func nootropic() {
        #expect(SubstanceCategory.from(tripSitCategory: "nootropic") == .nootropic)
    }

    @Test("Maps antidepressant subtypes")
    func antidepressant() {
        #expect(SubstanceCategory.from(tripSitCategory: "ssri") == .antidepressant)
        #expect(SubstanceCategory.from(tripSitCategory: "snri") == .antidepressant)
        #expect(SubstanceCategory.from(tripSitCategory: "maoi") == .antidepressant)
        #expect(SubstanceCategory.from(tripSitCategory: "antidepressant") == .antidepressant)
    }

    @Test("Maps antipsychotic")
    func antipsychotic() {
        #expect(SubstanceCategory.from(tripSitCategory: "antipsychotic") == .antipsychotic)
    }

    @Test("Maps antihistamine and deliriant")
    func antihistamine() {
        #expect(SubstanceCategory.from(tripSitCategory: "antihistamine") == .antihistamine)
        #expect(SubstanceCategory.from(tripSitCategory: "deliriant") == .antihistamine)
    }

    @Test("Maps supplement variants")
    func supplement() {
        #expect(SubstanceCategory.from(tripSitCategory: "supplement") == .supplement)
        #expect(SubstanceCategory.from(tripSitCategory: "vitamin") == .supplement)
        #expect(SubstanceCategory.from(tripSitCategory: "steroid") == .supplement)
    }

    @Test("Maps gabapentinoid variants")
    func gabapentinoid() {
        #expect(SubstanceCategory.from(tripSitCategory: "gabapentinoid") == .gabapentinoid)
        #expect(SubstanceCategory.from(tripSitCategory: "gabaergic") == .gabapentinoid)
    }

    @Test("Maps analgesic")
    func analgesic() {
        #expect(SubstanceCategory.from(tripSitCategory: "analgesic") == .analgesic)
    }

    @Test("Unknown category maps to other")
    func unknown() {
        #expect(SubstanceCategory.from(tripSitCategory: "notacategory") == .other)
        #expect(SubstanceCategory.from(tripSitCategory: "") == .other)
    }

    @Test("Mapping is case-insensitive")
    func caseInsensitive() {
        #expect(SubstanceCategory.from(tripSitCategory: "STIMULANT") == .stimulant)
        #expect(SubstanceCategory.from(tripSitCategory: "Psychedelic") == .psychedelic)
    }

    // MARK: - Modifier categories

    @Test("Modifier categories contains expected values")
    func modifierCategories() {
        #expect(SubstanceCategory.modifierCategories.contains("common"))
        #expect(SubstanceCategory.modifierCategories.contains("habit-forming"))
        #expect(SubstanceCategory.modifierCategories.contains("research-chemical"))
        #expect(SubstanceCategory.modifierCategories.contains("tentative"))
        #expect(SubstanceCategory.modifierCategories.contains("inactive"))
    }

    @Test("Modifier categories does not contain substantive categories")
    func modifierCategoriesExclusions() {
        #expect(!SubstanceCategory.modifierCategories.contains("stimulant"))
        #expect(!SubstanceCategory.modifierCategories.contains("opioid"))
    }

    // MARK: - Enum properties

    @Test("Has 22 cases")
    func caseCount() {
        #expect(SubstanceCategory.allCases.count == 22)
    }

    @Test("ID matches raw value")
    func idIsRawValue() {
        for category in SubstanceCategory.allCases {
            #expect(category.id == category.rawValue)
        }
    }

    @Test("All raw values are capitalized display strings")
    func rawValuesAreDisplayStrings() {
        for category in SubstanceCategory.allCases {
            #expect(!category.rawValue.isEmpty)
            // First character should be uppercase
            #expect(category.rawValue.first?.isUppercase == true)
        }
    }
}
